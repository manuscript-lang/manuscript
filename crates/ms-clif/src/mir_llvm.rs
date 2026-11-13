//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Cc, Func, Imm, Inst, Mode, Module, Op, Target, Term};
use ms_mir::types::{Ty, TyKind};
use std::collections::HashMap;

/// A finished function: pieces of the `define` line, the body, and the callees it declares.
pub struct Emitted {
    /// Return type with its attributes (`void` for `Unit`).
    pub ret: String,
    /// Parameter list.
    pub params: String,
    /// Entry label through the closing brace.
    pub body: String,
    /// `(symbol, declare line)` of each callee.
    pub decls: Vec<(String, String)>,
}

/// LLVM type and parameter attribute of one register leaf. `I8` leaves (`Bool`, flags) are
/// zero-extended across calls, like the Cranelift ABI; narrow integers live in `i64` registers.
fn leaf(l: Leaf) -> (LTy, &'static str) {
    match l {
        Leaf::F64 | Leaf::F32 => (LTy::F64, ""),
        Leaf::I8 => (LTy::I8, " zeroext"),
        _ => (LTy::I64, ""),
    }
}

/// The leaves of a value of type `ty`, in calling-convention order.
fn leaves(lay: &Layouts, ty: Ty) -> Vec<(LTy, &'static str)> {
    lay.leaves(ty).into_iter().map(leaf).collect()
}

/// Whether this stage handles values of `ty`: scalars, strings and lists (every list is three
/// leaves, whatever its element).
fn supported_ty(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Unit
        | TyKind::Int
        | TyKind::Float
        | TyKind::Bool
        | TyKind::Str
        | TyKind::Bytes
        | TyKind::List(_) => true,
        // A pointer-backed optional needs allocation; a nullable one is one `i64` whatever it holds.
        TyKind::Opt(inner) => {
            !lay.opt_is_boxed(*inner) && (lay.opt_is_nullable(*inner) || supported_ty(lay, *inner))
        }
        // An alternative that holds itself lives in a heap block; the rest are tag and slots.
        TyKind::Alt(a) => {
            !lay.is_boxed(*a)
                && lay.m.alts[a.index()]
                    .cases
                    .iter()
                    .all(|c| c.fields.iter().all(|f| supported_ty(lay, f.1)))
        }
        _ => false,
    }
}

/// How an optional that is not behind a pointer is laid out (`layout.rs`).
#[derive(Clone, Copy, PartialEq, Eq)]
enum OptRepr {
    /// `present: i8`, then the payload's leaves.
    Tagged,
    /// A nullable pointer or handle: the payload itself, zero for none.
    Nullable,
    /// A string's leaves; none is a null pointer with the static tag.
    Str,
}

fn opt_repr(lay: &Layouts, opt: Ty) -> OptRepr {
    let TyKind::Opt(inner) = lay.m.types.kind(opt) else {
        unreachable!("an optional operand")
    };
    if lay.opt_is_nullable(*inner) {
        OptRepr::Nullable
    } else if lay.is_str_like(opt) {
        OptRepr::Str
    } else {
        OptRepr::Tagged
    }
}

/// The constant zero of a register leaf.
fn zero(l: Leaf) -> Val {
    match leaf(l).0 {
        LTy::F64 => Val::double(0),
        LTy::I8 => Val::byte(0),
        _ => Val::int(0),
    }
}

/// The values of an operation that only rearranges or names leaves, so it writes no instruction:
/// optional and alternative construction, tags and payload reads. `None` for any other op.
fn rearrange(lay: &Layouts, f: &Func, inst: &Inst, vals: &Vals) -> Option<Vec<Val>> {
    let arg = |i: usize| &vals[&inst.args[i].index()];
    let res_ty = || f.ty(inst.res.expect("a result"));
    Some(match (inst.op, inst.imm) {
        (Op::OptSome | Op::OptView, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Tagged => std::iter::once(Val::byte(1))
                .chain(arg(0).iter().cloned())
                .collect(),
            _ => arg(0).clone(),
        },
        (Op::OptNone, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Str => vec![Val::int(0), Val::int(ms_rt_abi::STR_STATIC as i64)],
            _ => lay.leaves(res_ty()).into_iter().map(zero).collect(),
        },
        (Op::OptIsSome, _) if opt_repr(lay, f.ty(inst.args[0])) == OptRepr::Tagged => {
            vec![arg(0)[0].clone()]
        }
        (Op::OptGet | Op::OptUnbox, _) => match opt_repr(lay, f.ty(inst.args[0])) {
            OptRepr::Tagged => arg(0)[1..].to_vec(),
            _ => arg(0).clone(),
        },
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            let mut out: Vec<Val> = lay.leaves(res_ty()).into_iter().map(zero).collect();
            out[0] = Val::int(c as i64);
            for (i, (_, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                for (k, v) in idx.iter().zip(arg(i)) {
                    out[*k] = v.clone();
                }
            }
            out
        }
        (Op::AltPlain, _) => arg(0).clone(),
        (Op::AltTag, _) => vec![arg(0)[0].clone()],
        (Op::AltGet | Op::AltTake, Imm::AltField(a, c, i)) => {
            let (_, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            idx.iter().map(|k| arg(0)[*k].clone()).collect()
        }
        (Op::AltRelease, _) => vec![],
        (Op::AltUnbox, Imm::AltField(a, c, i)) => {
            let (_, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            idx.iter().map(|k| arg(0)[*k].clone()).collect()
        }
        _ => return None,
    })
}

/// Whether `rearrange` or an instruction below handles this optional or alternative op with
/// nothing left to drop or allocate.
fn data_op_ok(m: &Module, lay: &Layouts, inst: &Inst) -> bool {
    // Payload fields that are neither moved out nor kept would be dropped, which needs glue.
    let droppable = |a, c, keep: Option<u32>, mask: u32| {
        lay.alt_fields(a)[c as usize]
            .iter()
            .enumerate()
            .all(|(k, (t, _))| mask >> k & 1 == 1 || keep == Some(k as u32) || !m.needs_drop(*t))
    };
    match (inst.op, inst.imm) {
        (
            Op::OptSome | Op::OptView | Op::OptNone | Op::OptIsSome | Op::OptGet | Op::OptUnbox,
            _,
        )
        | (Op::AltNew | Op::AltView | Op::AltPlain | Op::AltTag | Op::AltGet | Op::AltTake, _) => {
            true
        }
        (Op::AltRelease, Imm::AltMask(a, c, mask)) => droppable(a, c, None, mask),
        (Op::AltUnbox, Imm::AltField(a, c, i)) => droppable(a, c, Some(i), 0),
        _ => false,
    }
}

/// The result type: `void` for no leaves, the leaf itself for one, a tuple for several.
fn ret_ty(lay: &Layouts, ty: Ty) -> LTy {
    let mut ls = leaves(lay, ty);
    match ls.len() {
        0 => LTy::Void,
        1 => ls.remove(0).0,
        _ => LTy::Tuple(ls.into_iter().map(|l| l.0).collect()),
    }
}

/// The result attribute: only a single `Bool`-like leaf carries one.
fn ret_attr(lay: &Layouts, ty: Ty) -> &'static str {
    match leaves(lay, ty).as_slice() {
        [(_, a)] if !a.is_empty() => "zeroext ",
        _ => "",
    }
}

fn ret_text(lay: &Layouts, ty: Ty) -> String {
    format!(
        "{}{}",
        ret_attr(lay, ty),
        Types::default().text(&ret_ty(lay, ty))
    )
}

fn signature_ok(lay: &Layouts, params: &[ms_mir::ir::Param], ret: Ty) -> bool {
    supported_ty(lay, ret)
        && params
            .iter()
            .all(|p| p.mode != Mode::Var && supported_ty(lay, p.ty))
}

fn supported_op(op: Op) -> bool {
    matches!(
        op,
        Op::IConst
            | Op::FConst
            | Op::BConst
            | Op::UnitConst
            | Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::INeg
            | Op::And
            | Op::Or
            | Op::Xor
            | Op::Not
            | Op::ICmp
            | Op::UICmp
            | Op::FCmp
            | Op::FAdd
            | Op::FSub
            | Op::FMul
            | Op::FDiv
            | Op::FNeg
            | Op::Select
            | Op::B2I
            | Op::ListLen
            | Op::Call
    )
}

/// Whether stage 1 can emit `f`.
pub fn supports(m: &Module, lay: &Layouts, f: &Func) -> bool {
    if !matches!(f.kind, ms_mir::ir::FuncKind::Normal)
        || !f.scopes.is_empty()
        || !f.noalias.is_empty()
        || !signature_ok(lay, &f.params, f.ret)
    {
        return false;
    }
    let ty_ok = |v| supported_ty(lay, f.ty(v));
    let rpo = f.rpo();
    // The entry block must have no predecessors (LLVM forbids a branch to it).
    let mut entry_target = false;
    for b in &rpo {
        let bd = &f.blocks[b.index()];
        if bd.params.iter().any(|p| !ty_ok(p.value)) {
            return false;
        }
        for i in &bd.insts {
            let ok = supported_op(i.op) || data_op_ok(m, lay, i);
            if !ok || i.res.is_some_and(|r| !ty_ok(r)) {
                return false;
            }
            if i.op == Op::Call {
                let Imm::Func(c) = i.imm else { return false };
                let callee = &m.funcs[c.index()];
                if !signature_ok(lay, &callee.params, callee.ret) {
                    return false;
                }
            }
        }
        let ok = match &bd.term {
            Term::Br(t) => !is_entry(t),
            Term::CondBr { then, els, .. } => {
                then.block != els.block && !is_entry(then) && !is_entry(els)
            }
            Term::Ret(_) | Term::Unreachable => true,
            Term::Switch { cases, default, .. } => {
                // Two edges into one block are two phi entries and must carry the same values.
                let targets: Vec<&Target> = cases.iter().map(|c| &c.1).chain([default]).collect();
                targets.iter().all(|t| !is_entry(t))
                    && targets.iter().all(|a| {
                        targets
                            .iter()
                            .all(|b| a.block != b.block || a.args == b.args)
                    })
            }
            Term::Fault(_) => false,
        };
        if !ok {
            return false;
        }
        bd.term.for_each_target(|t| entry_target |= is_entry(t));
    }
    !entry_target
}

fn is_entry(t: &Target) -> bool {
    t.block.index() == 0
}

/// The values of one MIR value: one per register leaf.
type Vals = HashMap<usize, Vec<Val>>;

/// Emits `f`, which `supports` accepted. `symbol_of` names the function with MIR index `i`;
/// `loc` is the `DILocation` node every instruction carries.
pub fn emit(lay: &Layouts, f: &Func, loc: usize, symbol_of: &dyn Fn(usize) -> String) -> Emitted {
    let types = Types::default();
    let mut b = FnBuilder::new(&types, Some(loc));
    let rpo = f.rpo();
    // Name every value before emitting anything: a phi names values a later block defines (the
    // back edge of a loop), and a constant is its own text.
    let mut vals: Vals = HashMap::new();
    let mut params = Vec::new();
    for (i, p) in f.params.iter().enumerate() {
        let mut own = Vec::new();
        for (j, (t, attr)) in leaves(lay, p.ty).into_iter().enumerate() {
            params.push(format!("{}{attr} %a{i}_{j}", types.text(&t)));
            own.push(Val::new(format!("%a{i}_{j}"), t));
        }
        vals.insert(f.blocks[0].params[i].value.index(), own);
    }
    let reserve_all = |b: &mut FnBuilder, ty: Ty| -> Vec<Val> {
        leaves(lay, ty)
            .into_iter()
            .map(|l| b.reserve(l.0))
            .collect()
    };
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        if bb.index() != 0 {
            for p in &bd.params {
                let own = reserve_all(&mut b, f.ty(p.value));
                vals.insert(p.value.index(), own);
            }
        }
        for inst in &bd.insts {
            let Some(res) = inst.res else { continue };
            let own = match (inst.op, inst.imm) {
                (Op::IConst, Imm::Int(v)) => vec![Val::int(v)],
                (Op::FConst, Imm::Float(bits)) => vec![Val::double(bits)],
                (Op::BConst, Imm::Bool(v)) => vec![Val::byte(v as u8)],
                // The length is a leaf of the list: no instruction.
                (Op::ListLen, _) => vec![vals[&inst.args[0].index()][1].clone()],
                _ => match rearrange(lay, f, inst, &vals) {
                    Some(v) => v,
                    None => reserve_all(&mut b, f.ty(res)),
                },
            };
            vals.insert(res.index(), own);
        }
    }
    // Incoming edges of every block, for the phis.
    let mut incoming: HashMap<usize, Vec<(usize, Vec<ms_mir::ir::Value>)>> = HashMap::new();
    for bb in &rpo {
        f.blocks[bb.index()].term.for_each_target(|t| {
            incoming
                .entry(t.block.index())
                .or_default()
                .push((bb.index(), t.args.clone()))
        });
    }
    let mut decls = Vec::new();
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        b.label(&format!("b{}", bb.index()));
        if bb.index() != 0 {
            for (j, p) in bd.params.iter().enumerate() {
                for (k, dst) in vals[&p.value.index()].iter().enumerate() {
                    let edges: Vec<(Val, String)> = incoming
                        .get(&bb.index())
                        .map(Vec::as_slice)
                        .unwrap_or(&[])
                        .iter()
                        .map(|(from, args)| (vals[&args[j].index()][k].clone(), format!("b{from}")))
                        .collect();
                    b.phi(dst, &edges);
                }
            }
        }
        for inst in &bd.insts {
            if rearrange(lay, f, inst, &vals).is_none() {
                inst_text(lay, f, inst, symbol_of, &vals, &mut decls, &mut b);
            }
        }
        match &bd.term {
            Term::Br(t) => b.br(&format!("b{}", t.block.index())),
            Term::CondBr { cond, then, els } => {
                let c = b.icmp("ne", &vals[&cond.index()][0], &Val::byte(0));
                b.cond_br(
                    &c,
                    &format!("b{}", then.block.index()),
                    &format!("b{}", els.block.index()),
                );
            }
            Term::Switch {
                value,
                cases,
                default,
            } => {
                let label = |t: &Target| format!("b{}", t.block.index());
                let arms: Vec<(i64, String)> = cases.iter().map(|(k, t)| (*k, label(t))).collect();
                b.switch(&vals[&value.index()][0], &label(default), &arms);
            }
            Term::Ret(Some(v)) => match vals[&v.index()].as_slice() {
                [] => b.ret(None),
                [one] => b.ret(Some(one)),
                many => {
                    let t = b.tuple(many);
                    b.ret(Some(&t));
                }
            },
            Term::Ret(None) => b.ret(None),
            _ => b.unreachable(),
        }
    }
    Emitted {
        ret: ret_text(lay, f.ret),
        params: params.join(", "),
        body: b.finish(),
        decls,
    }
}

fn icc(cc: Cc, unsigned: bool) -> &'static str {
    match (cc, unsigned) {
        (Cc::Eq, _) => "eq",
        (Cc::Ne, _) => "ne",
        (Cc::Lt, false) => "slt",
        (Cc::Le, false) => "sle",
        (Cc::Gt, false) => "sgt",
        (Cc::Ge, false) => "sge",
        (Cc::Lt, true) => "ult",
        (Cc::Le, true) => "ule",
        (Cc::Gt, true) => "ugt",
        (Cc::Ge, true) => "uge",
    }
}

/// Ordered comparison, except `ne`, which holds for NaN (the MIR rule, `Cc`).
fn fcc(cc: Cc) -> &'static str {
    match cc {
        Cc::Eq => "oeq",
        Cc::Ne => "une",
        Cc::Lt => "olt",
        Cc::Le => "ole",
        Cc::Gt => "ogt",
        Cc::Ge => "oge",
    }
}

/// Writes one instruction. Each result leaf takes the name reserved for it in `vals`, which a phi
/// may already use.
fn inst_text(
    lay: &Layouts,
    f: &Func,
    inst: &Inst,
    symbol_of: &dyn Fn(usize) -> String,
    vals: &Vals,
    decls: &mut Vec<(String, String)>,
    b: &mut FnBuilder,
) {
    let m = lay.m;
    let arg = |i: usize| vals[&inst.args[i].index()][0].clone();
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    if matches!(
        inst.op,
        Op::IConst | Op::FConst | Op::BConst | Op::UnitConst | Op::ListLen
    ) {
        return;
    }
    // A single-leaf result is named in place; `Select` and `Call` handle several.
    if let [r] = out.as_slice() {
        b.name_next(r);
    }
    match inst.op {
        Op::IAdd => drop(b.bin(Bin::Add, &arg(0), &arg(1))),
        Op::ISub => drop(b.bin(Bin::Sub, &arg(0), &arg(1))),
        Op::IMul => drop(b.bin(Bin::Mul, &arg(0), &arg(1))),
        Op::And => drop(b.bin(Bin::And, &arg(0), &arg(1))),
        Op::Or => drop(b.bin(Bin::Or, &arg(0), &arg(1))),
        Op::Xor => drop(b.bin(Bin::Xor, &arg(0), &arg(1))),
        Op::FAdd => drop(b.bin(Bin::FAdd, &arg(0), &arg(1))),
        Op::FSub => drop(b.bin(Bin::FSub, &arg(0), &arg(1))),
        Op::FMul => drop(b.bin(Bin::FMul, &arg(0), &arg(1))),
        Op::FDiv => drop(b.bin(Bin::FDiv, &arg(0), &arg(1))),
        Op::INeg => drop(b.bin(Bin::Sub, &Val::int(0), &arg(0))),
        Op::FNeg => drop(b.fneg(&arg(0))),
        Op::Not => drop(b.bin(Bin::Xor, &arg(0), &Val::byte(1))),
        Op::ICmp | Op::UICmp | Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            // The comparison is an `i1`; the result is its zero-extension, so name only that.
            let pending = b.take_name();
            let c = if inst.op == Op::FCmp {
                b.fcmp(fcc(cc), &arg(0), &arg(1))
            } else {
                b.icmp(icc(cc, inst.op == Op::UICmp), &arg(0), &arg(1))
            };
            b.restore_name(pending);
            b.zext(&c, LTy::I8);
        }
        Op::Select => {
            b.take_name();
            let c = b.icmp("ne", &arg(0), &Val::byte(0));
            for (k, dst) in out.iter().enumerate() {
                b.name_next(dst);
                b.select(
                    &c,
                    &vals[&inst.args[1].index()][k],
                    &vals[&inst.args[2].index()][k],
                );
            }
        }
        Op::B2I => drop(b.zext(&arg(0), LTy::I64)),
        Op::OptIsSome => {
            // A niche optional is present unless its first leaf is null (a string also has the
            // static tag: an inline string may have a zero first word, but never that tag).
            let v = &vals[&inst.args[0].index()];
            let pending = b.take_name();
            let any = match opt_repr(lay, f.ty(inst.args[0])) {
                OptRepr::Str => {
                    let t = b.bin(Bin::Xor, &v[1], &Val::int(ms_rt_abi::STR_STATIC as i64));
                    b.bin(Bin::Or, &v[0], &t)
                }
                _ => v[0].clone(),
            };
            let c = b.icmp("ne", &any, &Val::int(0));
            b.restore_name(pending);
            b.zext(&c, LTy::I8);
        }
        Op::Call => {
            let Imm::Func(c) = inst.imm else { return };
            let callee = &m.funcs[c.index()];
            let sym = symbol_of(c.index());
            let ret = ret_ty(lay, callee.ret);
            let attr = ret_attr(lay, callee.ret);
            let mut args: Vec<(Val, &str)> = Vec::new();
            for (p, a) in callee.params.iter().zip(&inst.args) {
                for (v, (_, at)) in vals[&a.index()].iter().zip(leaves(lay, p.ty)) {
                    args.push((v.clone(), at));
                }
            }
            let formals: Vec<String> = args
                .iter()
                .map(|(v, a)| format!("{}{a}", Types::default().text(&v.ty)))
                .collect();
            decls.push((
                sym.clone(),
                format!(
                    "declare {attr}{} @\"{sym}\"({})",
                    Types::default().text(&ret),
                    formals.join(", ")
                ),
            ));
            if out.len() <= 1 {
                b.call(&ret, attr, &sym, &args);
            } else {
                let t = b.call(&ret, attr, &sym, &args).expect("a tuple result");
                for (k, dst) in out.iter().enumerate() {
                    b.name_next(dst);
                    b.extract(&t, k);
                }
            }
        }
        _ => unreachable!("supports rejects other ops"),
    }
}

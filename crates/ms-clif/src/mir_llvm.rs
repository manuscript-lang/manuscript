//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

mod calls;

use crate::glue_llvm::{OwnKind, clone_str, own_kind};
use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Cc, Func, Imm, Inst, Mode, Module, Op, Target, Term};
use ms_mir::types::{Ty, TyKind};
use ms_rt_abi::STR_INLINE;
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
    /// Symbols of the data objects the function addresses.
    pub data: Vec<String>,
}

/// What a function needs from the module before it is emitted: the symbols of the glue and data
/// its instructions refer to. The driver declares them (glue is queued for generation).
#[derive(Default)]
pub struct Plan {
    /// `Clone` glue symbol by type, for types cloned by a glue call.
    pub clone: HashMap<Ty, String>,
    /// `Drop` glue symbol by type, for types dropped by a glue call.
    pub drop: HashMap<Ty, String>,
    /// Type descriptor symbol by type.
    pub desc: HashMap<Ty, String>,
    /// The `closure.new` results that live in this function's frame (nothing escapes).
    pub framed: std::collections::HashSet<usize>,
    /// Clone and drop glue symbols of a closure's object, by the closure function and whether its
    /// object is in a frame.
    pub closures: HashMap<(usize, bool), ClosureSyms>,
}

/// The glue entries a closure object carries in its header.
pub struct ClosureSyms {
    pub clone: String,
    pub drop: String,
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
    matches!(
        lay.m.types.kind(ty),
        TyKind::Unit
            | TyKind::Int
            | TyKind::Float
            | TyKind::Bool
            | TyKind::Ptr
            | TyKind::Fn(..)
            | TyKind::Str
            | TyKind::Bytes
            | TyKind::List(_)
    )
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
            | Op::Clone
            | Op::Drop
            | Op::DropIf
            | Op::TypeDesc
            | Op::Call
    ) || calls::handles(op)
}

/// Whether stage 1 can emit `f`.
pub fn supports(m: &Module, lay: &Layouts, f: &Func) -> bool {
    if !f.scopes.is_empty() || !f.noalias.is_empty() || !signature_ok(lay, &f.params, f.ret) {
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
            if !supported_op(i.op) || i.res.is_some_and(|r| !ty_ok(r)) {
                return false;
            }
            if i.op == Op::Call {
                let Imm::Func(c) = i.imm else { return false };
                let callee = &m.funcs[c.index()];
                if !signature_ok(lay, &callee.params, callee.ret) {
                    return false;
                }
            }
            if i.op == Op::CallRt {
                let Imm::Ext(e) = i.imm else { return false };
                let def = &m.externs[e.index()];
                let tys_ok = def.params.iter().all(|p| supported_ty(lay, p.ty))
                    && supported_ty(lay, def.ret);
                if !tys_ok || !calls::extern_ok(m, def) {
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
            Term::Switch { .. } | Term::Fault(_) => false,
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
pub fn emit(
    m: &Module,
    lay: &Layouts,
    f: &Func,
    plan: &Plan,
    loc: usize,
    symbol_of: &dyn Fn(usize) -> String,
) -> Emitted {
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
                // Cloning plain data is the value itself.
                (Op::Clone, _) if own_kind(lay, f.ty(inst.args[0])) == OwnKind::Identity => {
                    vals[&inst.args[0].index()].clone()
                }
                _ => reserve_all(&mut b, f.ty(res)),
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
    let mut out = Out::default();
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
                        .map(|(from, args)| {
                            (vals[&args[j].index()][k].clone(), end_label(lay, f, *from))
                        })
                        .collect();
                    b.phi(dst, &edges);
                }
            }
        }
        let mut label = format!("b{}", bb.index());
        for (k, inst) in bd.insts.iter().enumerate() {
            let at = Site {
                label: &mut label,
                block: bb.index(),
                inst: k,
            };
            let cx = Cx {
                m,
                lay,
                f,
                plan,
                symbol_of,
                vals: &vals,
            };
            inst_text(&cx, inst, &mut out, at, &mut b);
        }
        debug_assert_eq!(label, end_label(lay, f, bb.index()));
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
        decls: out.decls,
        data: out.data,
    }
}

/// What emission reads: the module, the plan and the values of every MIR value.
struct Cx<'a> {
    m: &'a Module,
    lay: &'a Layouts<'a>,
    f: &'a Func,
    plan: &'a Plan,
    symbol_of: &'a dyn Fn(usize) -> String,
    vals: &'a Vals,
}

/// Callee declarations and data symbols the function uses.
#[derive(Default)]
struct Out {
    decls: Vec<(String, String)>,
    data: Vec<String>,
}

/// Where an instruction is written: the label of the LLVM block being filled, which a string
/// clone moves on, and the MIR block and instruction it came from.
struct Site<'a> {
    label: &'a mut String,
    block: usize,
    inst: usize,
}

/// Whether `inst` branches inside its MIR block, so that what follows is in another LLVM block:
/// a string clone, a drop that frees a string conditionally, and a guarded drop.
fn splits(lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    match inst.op {
        Op::Clone => own_kind(lay, f.ty(inst.args[0])) == OwnKind::Str,
        Op::Drop => own_kind(lay, f.ty(inst.args[0])) == OwnKind::Str,
        Op::DropIf => own_kind(lay, f.ty(inst.args[1])) != OwnKind::Identity,
        _ => false,
    }
}

/// The label of the LLVM block that ends MIR block `bb`: its own, or the join block of its last
/// splitting instruction.
fn end_label(lay: &Layouts, f: &Func, bb: usize) -> String {
    match f.blocks[bb].insts.iter().rposition(|i| splits(lay, f, i)) {
        Some(k) => format!("b{bb}.j{k}"),
        None => format!("b{bb}"),
    }
}

/// The declaration of a runtime function that takes one address-sized word and returns nothing.
fn rt_decl(name: &str) -> (String, String) {
    (name.into(), format!("declare void @\"{name}\"(i64)"))
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
fn inst_text(cx: &Cx, inst: &Inst, out_sinks: &mut Out, at: Site, b: &mut FnBuilder) {
    let Cx {
        m,
        lay,
        f,
        plan,
        symbol_of,
        vals,
    } = *cx;
    let decls = &mut out_sinks.decls;
    let arg = |i: usize| vals[&inst.args[i].index()][0].clone();
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    if matches!(
        inst.op,
        Op::IConst | Op::FConst | Op::BConst | Op::UnitConst | Op::ListLen
    ) || (inst.op == Op::Clone && own_kind(lay, f.ty(inst.args[0])) == OwnKind::Identity)
    {
        return;
    }
    if calls::handles(inst.op) {
        calls::emit(cx, inst, out_sinks, b);
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
        Op::TypeDesc => {
            let Imm::Ty(t) = inst.imm else { return };
            let sym = &plan.desc[&t];
            out_sinks.data.push(sym.clone());
            let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
            drop(b.ptrtoint(&addr));
        }
        Op::Clone => {
            let ty = f.ty(inst.args[0]);
            let ls = leaves(lay, ty);
            let args = &vals[&inst.args[0].index()];
            match own_kind(lay, ty) {
                OwnKind::Identity => {}
                OwnKind::Str => {
                    b.take_name();
                    let join = format!("b{}.j{}", at.block, at.inst);
                    let dup = format!("b{}.d{}", at.block, at.inst);
                    clone_str(b, decls, (at.label, &dup, &join), args, Some(&out));
                    *at.label = join;
                }
                OwnKind::Obj => {
                    decls.push((
                        "msrt_obj_clone".into(),
                        "declare i64 @\"msrt_obj_clone\"(i64)".into(),
                    ));
                    b.call(&LTy::I64, "", "msrt_obj_clone", &[(args[0].clone(), "")]);
                }
                OwnKind::Glue => {
                    let sym = &plan.clone[&ty];
                    let ret = ret_ty(lay, ty);
                    let attr = ret_attr(lay, ty);
                    let call_args: Vec<(Val, &str)> = args
                        .iter()
                        .zip(&ls)
                        .map(|(v, (_, a))| (v.clone(), *a))
                        .collect();
                    let formals: Vec<String> = ls
                        .iter()
                        .map(|(t, a)| format!("{}{a}", Types::default().text(t)))
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
                        b.call(&ret, attr, sym, &call_args);
                    } else {
                        let t = b.call(&ret, attr, sym, &call_args).expect("a tuple result");
                        for (k, dst) in out.iter().enumerate() {
                            b.name_next(dst);
                            b.extract(&t, k);
                        }
                    }
                }
            }
        }
        Op::Drop | Op::DropIf => {
            let guarded = inst.op == Op::DropIf;
            let ty = f.ty(inst.args[usize::from(guarded)]);
            let kind = own_kind(lay, ty);
            if kind == OwnKind::Identity {
                return;
            }
            let args = &vals[&inst.args[usize::from(guarded)].index()];
            let join = format!("b{}.j{}", at.block, at.inst);
            let mut n = 0;
            let mut fresh = |what: &str| {
                n += 1;
                format!("b{}.{what}{}.{n}", at.block, at.inst)
            };
            if guarded {
                let on = b.icmp("ne", &arg(0), &Val::byte(0));
                let then = fresh("t");
                b.cond_br(&on, &then, &join);
                b.label(&then);
            }
            match kind {
                OwnKind::Str => {
                    // Only an owned string (tag `00`) frees anything.
                    let owned = b.icmp("ult", &args[1], &Val::int(STR_INLINE as i64));
                    let (free, cont) =
                        (fresh("f"), if guarded { fresh("c") } else { join.clone() });
                    b.cond_br(&owned, &free, &cont);
                    b.label(&free);
                    decls.push(rt_decl("msrt_str_free"));
                    b.call(&LTy::Void, "", "msrt_str_free", &[(args[0].clone(), "")]);
                    b.br(&cont);
                    b.label(&cont);
                }
                OwnKind::Obj => {
                    decls.push(rt_decl("msrt_obj_drop"));
                    b.call(&LTy::Void, "", "msrt_obj_drop", &[(args[0].clone(), "")]);
                }
                _ => {
                    let sym = &plan.drop[&ty];
                    let ls = leaves(lay, ty);
                    let call_args: Vec<(Val, &str)> = args
                        .iter()
                        .zip(&ls)
                        .map(|(v, (_, a))| (v.clone(), *a))
                        .collect();
                    let formals: Vec<String> = ls
                        .iter()
                        .map(|(t, a)| format!("{}{a}", Types::default().text(t)))
                        .collect();
                    decls.push((
                        sym.clone(),
                        format!("declare void @\"{sym}\"({})", formals.join(", ")),
                    ));
                    b.call(&LTy::Void, "", sym, &call_args);
                }
            }
            if guarded {
                b.br(&join);
                b.label(&join);
            }
            *at.label = join;
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

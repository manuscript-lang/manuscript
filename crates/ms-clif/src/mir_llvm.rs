//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use crate::llvm_ir::DirectEnv;
mod records;
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
    records::ty_ok(lay, ty)
        || matches!(
            lay.m.types.kind(ty),
            TyKind::Unit
                | TyKind::Int
                | TyKind::Float
                | TyKind::Bool
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
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::Call
    ) || records::handles(op)
}

/// Whether stage 1 can emit `f`.
pub fn supports(m: &Module, lay: &Layouts, f: &Func) -> bool {
    if !matches!(f.kind, ms_mir::ir::FuncKind::Normal)
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
            if !supported_op(i.op)
                || i.res.is_some_and(|r| !ty_ok(r))
                || i.args.iter().any(|a| !ty_ok(*a))
                || !records::op_ok(lay, f, i)
                || (i.op == Op::Select && i.res.is_some_and(|r| records::is_mem(lay, f.ty(r))))
            {
                return false;
            }
            if matches!(i.op, Op::ListGet | Op::ListGetNn | Op::ListGetU) && !elem_ok(m, lay, f, i)
            {
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
            Term::Switch { .. } | Term::Fault(_) => false,
        };
        if !ok {
            return false;
        }
        bd.term.for_each_target(|t| entry_target |= is_entry(t));
    }
    !entry_target
}

/// Whether the element a list read loads is made of plain `i64`, `double` and `i8` leaves, which
/// sit in memory exactly as in registers.
fn elem_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    let Some(e) = m.seq_elem(f.ty(i.args[0])) else {
        return false;
    };
    i.res.is_some_and(|r| f.ty(r) == e)
        && lay
            .leaves(e)
            .iter()
            .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
}

fn is_entry(t: &Target) -> bool {
    t.block.index() == 0
}

/// What emitting one function needs besides the builder.
struct Cx<'a> {
    m: &'a Module,
    f: &'a Func,
    lay: &'a Layouts<'a>,
    /// Whether bounds checks are emitted.
    checks: bool,
    /// Fault call sites numbered so far in the module.
    sites: u32,
    symbol_of: &'a dyn Fn(usize) -> String,
    /// `(symbol, declare line)` of each callee.
    decls: Vec<(String, String)>,
    /// MIR block being written and the checks it has split off so far.
    block: usize,
    split: usize,
}

/// Whether `op` ends its block early to branch to a fault when checks are on.
fn checked(op: Op) -> bool {
    matches!(op, Op::ListGet | Op::ListGetNn)
}

/// The label a MIR block ends in: each check splits it, and a successor's phis name that label.
fn exit_label(f: &Func, checks: bool, bb: usize) -> String {
    let n = if checks {
        f.blocks[bb].insts.iter().filter(|i| checked(i.op)).count()
    } else {
        0
    };
    block_label(bb, n)
}

fn block_label(bb: usize, split: usize) -> String {
    if split == 0 {
        format!("b{bb}")
    } else {
        format!("b{bb}.{split}")
    }
}

/// The values of one MIR value: one per register leaf.
type Vals = HashMap<usize, Vec<Val>>;

/// Emits `f`, which `supports` accepted. `symbol_of` names the function with MIR index `i`;
/// `loc` is the `DILocation` node every instruction carries.
pub fn emit(
    m: &Module,
    lay: &Layouts,
    f: &Func,
    checks: bool,
    env: &mut DirectEnv,
    symbol_of: &dyn Fn(usize) -> String,
) -> Emitted {
    let types = Types::default();
    let mut b = FnBuilder::new(&types, Some(env.loc));
    let rpo = f.rpo();
    // Name every value before emitting anything: a phi names values a later block defines (the
    // back edge of a loop), and a constant is its own text.
    let mut vals: Vals = HashMap::new();
    let mut params = Vec::new();
    let mut entry = Vec::new();
    for (i, p) in f.params.iter().enumerate() {
        let mut abi = Vec::new();
        for (j, (t, attr)) in leaves(lay, p.ty).into_iter().enumerate() {
            params.push(format!("{}{attr} %a{i}_{j}", types.text(&t)));
            abi.push(Val::new(format!("%a{i}_{j}"), t));
        }
        let own = records::bind_param(&mut b, lay, p.ty, abi, &mut entry);
        vals.insert(f.blocks[0].params[i].value.index(), own);
    }
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        if bb.index() != 0 {
            for p in &bd.params {
                let own = records::block_param(&mut b, lay, f.ty(p.value));
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
                _ => match records::bind_early(&mut b, lay, f, &vals, inst) {
                    Some(own) => own,
                    None => records::reserve(&mut b, lay, f.ty(res)),
                },
            };
            vals.insert(res.index(), own);
        }
    }
    // Incoming edges of every block, for the phis.
    // Copies into a record's slot run only on their own edge, so a conditional edge that has some
    // is a block of its own, named after the block it leaves.
    let mut incoming: HashMap<usize, Vec<(String, Vec<ms_mir::ir::Value>)>> = HashMap::new();
    for bb in &rpo {
        let term = &f.blocks[bb.index()].term;
        let mut k = 0;
        term.for_each_target(|t| {
            let from = exit_label(f, checks, bb.index());
            let from = if matches!(term, Term::CondBr { .. }) && records::has_copies(lay, f, t) {
                format!("{from}_e{k}")
            } else {
                from
            };
            incoming
                .entry(t.block.index())
                .or_default()
                .push((from, t.args.clone()));
            k += 1;
        });
    }
    let mut cx = Cx {
        m,
        f,
        lay,
        checks,
        sites: *env.sites,
        symbol_of,
        decls: Vec::new(),
        block: 0,
        split: 0,
    };
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        cx.block = bb.index();
        cx.split = 0;
        b.label(&format!("b{}", bb.index()));
        if bb.index() == 0 {
            records::emit_entry(&mut b, lay, std::mem::take(&mut entry));
        } else {
            for (j, p) in bd.params.iter().enumerate() {
                if records::is_mem(lay, f.ty(p.value)) {
                    continue;
                }
                for (k, dst) in vals[&p.value.index()].iter().enumerate() {
                    let edges: Vec<(Val, String)> = incoming
                        .get(&bb.index())
                        .map(Vec::as_slice)
                        .unwrap_or(&[])
                        .iter()
                        .map(|(from, args)| (vals[&args[j].index()][k].clone(), from.clone()))
                        .collect();
                    b.phi(dst, &edges);
                }
            }
        }
        for inst in &bd.insts {
            b.set_dbg(Some(env.at(inst.loc)));
            inst_text(&mut cx, inst, &mut vals, &mut b);
        }
        match &bd.term {
            Term::Br(t) => {
                records::copies(&mut b, lay, f, &vals, t);
                b.br(&block_label(t.block.index(), 0));
            }
            Term::CondBr { cond, then, els } => {
                let c = b.icmp("ne", &vals[&cond.index()][0], &Val::byte(0));
                let from = exit_label(f, checks, bb.index());
                let to = |k: usize, t: &Target| {
                    if records::has_copies(lay, f, t) {
                        format!("{from}_e{k}")
                    } else {
                        block_label(t.block.index(), 0)
                    }
                };
                b.cond_br(&c, &to(0, then), &to(1, els));
                for (k, t) in [then, els].into_iter().enumerate() {
                    if records::has_copies(lay, f, t) {
                        b.label(&to(k, t));
                        records::copies(&mut b, lay, f, &vals, t);
                        b.br(&block_label(t.block.index(), 0));
                    }
                }
            }
            Term::Ret(Some(v)) => {
                let abi = records::abi_leaves(&mut b, lay, f.ty(*v), &vals, *v);
                match abi.as_slice() {
                    [] => b.ret(None),
                    [one] => b.ret(Some(one)),
                    many => {
                        let t = b.tuple(many);
                        b.ret(Some(&t));
                    }
                }
            }
            Term::Ret(None) => b.ret(None),
            _ => b.unreachable(),
        }
    }
    *env.sites = cx.sites;
    Emitted {
        ret: ret_text(lay, f.ret),
        params: params.join(", "),
        body: b.finish(),
        decls: cx.decls,
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
fn inst_text(cx: &mut Cx, inst: &Inst, vals: &mut Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
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
    if matches!(inst.op, Op::ListGet | Op::ListGetNn | Op::ListGetU) {
        list_get(cx, inst, vals, b);
        return;
    }
    if records::handles(inst.op) {
        records::inst(b, cx.lay, cx.f, vals, inst, &out);
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
        Op::Call => {
            let Imm::Func(c) = inst.imm else { return };
            let callee = &m.funcs[c.index()];
            let sym = (cx.symbol_of)(c.index());
            let ret = ret_ty(lay, callee.ret);
            let attr = ret_attr(lay, callee.ret);
            let mut args: Vec<(Val, &str)> = Vec::new();
            // Converting arguments writes instructions that must not take the result's name.
            let pending = b.take_name();
            for (p, a) in callee.params.iter().zip(&inst.args) {
                let abi = records::abi_leaves(b, lay, p.ty, vals, *a);
                for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
                    args.push((v, at));
                }
            }
            b.restore_name(pending);
            let formals: Vec<String> = args
                .iter()
                .map(|(v, a)| format!("{}{a}", Types::default().text(&v.ty)))
                .collect();
            cx.decls.push((
                sym.clone(),
                format!(
                    "declare {attr}{} @\"{sym}\"({})",
                    Types::default().text(&ret),
                    formals.join(", ")
                ),
            ));
            if callee.ret == Ty::PTR || records::is_mem(lay, callee.ret) {
                // The result is a `ptr` or a record in memory: built from the call's result.
                let pending = b.take_name();
                let r = b.call(&ret, attr, &sym, &args).expect("a result");
                b.restore_name(pending);
                let own = records::call_result(b, lay, callee.ret, r, &out);
                vals.insert(inst.res.expect("call result").index(), own);
            } else if out.len() <= 1 {
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

/// A list element read: normalize a negative index (`ListGet`), branch to the fault when it is out
/// of range, then load each leaf of the element at its offset. The element type is an LLVM
/// type, so the address is a typed `getelementptr` and LLVM sees a strided access it can vectorize.
fn list_get(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let l = &vals[&inst.args[0].index()];
    let i = vals[&inst.args[1].index()][0].clone();
    let out = &vals[&inst.res.expect("list read result").index()];
    let elem = cx.m.seq_elem(cx.f.ty(inst.args[0])).expect("a list");
    let tys: Vec<LTy> = cx.lay.leaves(elem).into_iter().map(|x| leaf(x).0).collect();
    let (ptr, len) = (b.int_to_ptr(&l[0]), l[1].clone());
    let idx = if inst.op == Op::ListGet {
        let neg = b.icmp("slt", &i, &Val::int(0));
        let wrapped = b.bin(Bin::Add, &i, &len);
        b.select(&neg, &wrapped, &i)
    } else {
        i.clone()
    };
    if cx.checks && checked(inst.op) {
        let oob = b.icmp("uge", &idx, &len);
        let fault = format!("f{}_{}", cx.block, cx.split);
        cx.split += 1;
        let next = block_label(cx.block, cx.split);
        b.cond_br_likely(&oob, &fault, &next, false);
        b.label(&fault);
        cx.sites += 1;
        b.fault_site(cx.sites);
        b.call(
            &LTy::Void,
            "",
            "msrt_index_fault",
            &[(i.clone(), ""), (len, "")],
        );
        b.unreachable();
        cx.decls.push((
            "msrt_index_fault".into(),
            "declare void @\"msrt_index_fault\"(i64, i64) cold noreturn".into(),
        ));
        b.label(&next);
    }
    let types = Types::default();
    let whole = match tys.as_slice() {
        [one] => one.clone(),
        many => LTy::Tuple(many.to_vec()),
    };
    debug_assert_eq!(
        types.size_align(&whole).0,
        u64::from(mem_layout(&cx.lay.leaves(elem)).size)
    );
    let at = b.elem_ptr(&whole, &ptr, &idx);
    for (k, (t, dst)) in tys.iter().zip(out).enumerate() {
        let from = if tys.len() == 1 {
            at.clone()
        } else {
            b.field_ptr(&whole, &at, k)
        };
        b.name_next(dst);
        b.load(t, &from, types.size_align(t).1);
    }
}

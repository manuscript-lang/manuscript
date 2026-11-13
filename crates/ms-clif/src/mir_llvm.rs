//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

use crate::glue_llvm::{OwnKind, clone_str, own_kind};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use crate::llvm_ir::DirectEnv;
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
    /// Function attributes written after the group reference (empty when none are proven).
    pub attrs: String,
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
    /// Whether bounds checks are emitted.
    pub checks: bool,
    /// `Clone` glue symbol by type, for types cloned by a glue call.
    pub clone: HashMap<Ty, String>,
    /// `Drop` glue symbol by type, for types dropped by a glue call.
    pub drop: HashMap<Ty, String>,
    /// Type descriptor symbol by type.
    pub desc: HashMap<Ty, String>,
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
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::TypeDesc
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
            if !supported_op(i.op) || i.res.is_some_and(|r| !ty_ok(r)) {
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

/// Attributes LLVM cannot always infer, for a function with no memory access or fault: its result
/// depends on its arguments alone. A function across a unit boundary is only a `declare`, so the
/// call site would otherwise know nothing. `willreturn` needs the body and its callees to be
/// loop-free and acyclic; `None` when `f` is not such a scalar function at all.
fn pure_attrs(
    m: &Module,
    lay: &Layouts,
    idx: usize,
    memo: &mut HashMap<usize, Option<bool>>,
) -> Option<&'static str> {
    let terminates = pure_terminates(m, lay, idx, memo)?;
    Some(if terminates {
        " nounwind willreturn nofree nosync norecurse memory(none)"
    } else {
        " nounwind nofree nosync memory(none)"
    })
}

/// `Some(true)` when `idx` is a scalar function that is pure and always returns, `Some(false)`
/// when it is pure but may loop or recurse for ever, `None` when it is not pure.
fn pure_terminates(
    m: &Module,
    lay: &Layouts,
    idx: usize,
    memo: &mut HashMap<usize, Option<bool>>,
) -> Option<bool> {
    if let Some(v) = memo.get(&idx) {
        return *v;
    }
    // A call back into a function being analysed is recursion: pure, but it may not return.
    memo.insert(idx, Some(false));
    let f = &m.funcs[idx];
    let verdict = if supports(m, lay, f) {
        let rpo = f.rpo();
        let mut order = vec![usize::MAX; f.blocks.len()];
        for (k, b) in rpo.iter().enumerate() {
            order[b.index()] = k;
        }
        let mut terminates = true;
        let mut pure = true;
        for b in &rpo {
            let bd = &f.blocks[b.index()];
            bd.term
                .for_each_target(|t| terminates &= order[t.block.index()] > order[b.index()]);
            for i in &bd.insts {
                // Every op `supports` accepts today is register-only; a memory op added later must
                // not inherit `memory(none)`, so the list is explicit.
                pure &= matches!(i.op, Op::Call) || !touches_memory(i.op);
                if i.op != Op::Call {
                    continue;
                }
                let Imm::Func(c) = i.imm else { continue };
                match pure_terminates(m, lay, c.index(), memo) {
                    Some(t) => terminates &= t,
                    None => pure = false,
                }
            }
        }
        pure.then_some(terminates)
    } else {
        None
    };
    memo.insert(idx, verdict);
    verdict
}

/// The ops that read neither memory nor anything a fault could depend on: register arithmetic and
/// the length leaf of a list. Every other supported op (list and string accesses, which load, store
/// and fault) may touch memory, so a function with one is not `memory(none)`.
const PURE_OPS: &[Op] = &[
    Op::IConst,
    Op::FConst,
    Op::BConst,
    Op::UnitConst,
    Op::IAdd,
    Op::ISub,
    Op::IMul,
    Op::INeg,
    Op::And,
    Op::Or,
    Op::Xor,
    Op::Not,
    Op::ICmp,
    Op::UICmp,
    Op::FCmp,
    Op::FAdd,
    Op::FSub,
    Op::FMul,
    Op::FDiv,
    Op::FNeg,
    Op::Select,
    Op::B2I,
    Op::ListLen,
];

/// Whether a supported op may read or write memory.
fn touches_memory(op: Op) -> bool {
    !PURE_OPS.contains(&op)
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
    /// The glue and descriptors the function refers to, declared by the driver.
    plan: &'a Plan,
    /// Whether bounds checks are emitted.
    checks: bool,
    /// Fault call sites numbered so far in the module.
    sites: u32,
    symbol_of: &'a dyn Fn(usize) -> String,
    /// Which callees are pure, and whether they return (see [`pure_attrs`]).
    memo: HashMap<usize, Option<bool>>,
    /// `(symbol, declare line)` of each callee.
    decls: Vec<(String, String)>,
    /// Symbols of the data objects the function addresses.
    data: Vec<String>,
    /// MIR block being written and the splits it has made so far.
    block: usize,
    split: usize,
}

/// Whether `op` ends its block early to branch to a fault when checks are on.
fn checked(op: Op) -> bool {
    matches!(op, Op::ListGet | Op::ListGetNn)
}

/// Whether `inst` branches inside its MIR block, so that what follows is in another LLVM block:
/// a checked list read, a string clone, a drop that frees a string conditionally, and a guarded
/// drop.
fn splits(lay: &Layouts, f: &Func, checks: bool, inst: &Inst) -> bool {
    match inst.op {
        op if checked(op) => checks,
        Op::Clone => own_kind(lay, f.ty(inst.args[0])) == OwnKind::Str,
        Op::Drop => own_kind(lay, f.ty(inst.args[0])) == OwnKind::Str,
        Op::DropIf => own_kind(lay, f.ty(inst.args[1])) != OwnKind::Identity,
        _ => false,
    }
}

/// The label a MIR block ends in: each split moves it on, and a successor's phis name that label.
fn exit_label(lay: &Layouts, f: &Func, checks: bool, bb: usize) -> String {
    let n = f.blocks[bb]
        .insts
        .iter()
        .filter(|i| splits(lay, f, checks, i))
        .count();
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
    idx: usize,
    f: &Func,
    plan: &Plan,
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
    let checks = plan.checks;
    let mut cx = Cx {
        m,
        f,
        lay,
        plan,
        checks,
        sites: *env.sites,
        symbol_of,
        memo: HashMap::new(),
        decls: Vec::new(),
        data: Vec::new(),
        block: 0,
        split: 0,
    };
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        cx.block = bb.index();
        cx.split = 0;
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
                            (
                                vals[&args[j].index()][k].clone(),
                                exit_label(lay, f, checks, *from),
                            )
                        })
                        .collect();
                    b.phi(dst, &edges);
                }
            }
        }
        for inst in &bd.insts {
            b.set_dbg(Some(env.line(inst.loc.line)));
            inst_text(&mut cx, inst, &vals, &mut b);
        }
        debug_assert_eq!(
            block_label(cx.block, cx.split),
            exit_label(lay, f, checks, bb.index())
        );
        match &bd.term {
            Term::Br(t) => b.br(&block_label(t.block.index(), 0)),
            Term::CondBr { cond, then, els } => {
                let c = b.icmp("ne", &vals[&cond.index()][0], &Val::byte(0));
                b.cond_br(
                    &c,
                    &block_label(then.block.index(), 0),
                    &block_label(els.block.index(), 0),
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
    *env.sites = cx.sites;
    Emitted {
        ret: ret_text(lay, f.ret),
        params: params.join(", "),
        attrs: pure_attrs(m, lay, idx, &mut cx.memo)
            .unwrap_or("")
            .to_string(),
        body: b.finish(),
        decls: cx.decls,
        data: cx.data,
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
fn inst_text(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay, f) = (cx.m, cx.lay, cx.f);
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
    if matches!(inst.op, Op::ListGet | Op::ListGetNn | Op::ListGetU) {
        list_get(cx, inst, vals, b);
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
            let sym = &cx.plan.desc[&t];
            cx.data.push(sym.clone());
            let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
            drop(b.ptrtoint(&addr));
        }
        Op::Clone => {
            let ty = f.ty(inst.args[0]);
            let args = &vals[&inst.args[0].index()];
            match own_kind(lay, ty) {
                OwnKind::Identity => {}
                OwnKind::Str => {
                    b.take_name();
                    let pre = block_label(cx.block, cx.split);
                    let dup = format!("b{}.d{}", cx.block, cx.split);
                    cx.split += 1;
                    let join = block_label(cx.block, cx.split);
                    clone_str(b, &mut cx.decls, (&pre, &dup, &join), args, Some(&out));
                }
                OwnKind::Obj => {
                    cx.decls.push((
                        "msrt_obj_clone".into(),
                        "declare i64 @\"msrt_obj_clone\"(i64)".into(),
                    ));
                    b.call(&LTy::I64, "", "msrt_obj_clone", &[(args[0].clone(), "")]);
                }
                OwnKind::Glue => {
                    let sym = &cx.plan.clone[&ty];
                    crate::glue_llvm::call_clone(b, &mut cx.decls, lay, sym, ty, args, Some(&out));
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
            let (block, at) = (cx.block, cx.split);
            cx.split += 1;
            let join = block_label(block, cx.split);
            let mut n = 0;
            let mut fresh = |what: &str| {
                n += 1;
                format!("b{block}.{what}{at}.{n}")
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
                    cx.decls.push(rt_decl("msrt_str_free"));
                    b.call(&LTy::Void, "", "msrt_str_free", &[(args[0].clone(), "")]);
                    b.br(&cont);
                    b.label(&cont);
                }
                OwnKind::Obj => {
                    cx.decls.push(rt_decl("msrt_obj_drop"));
                    b.call(&LTy::Void, "", "msrt_obj_drop", &[(args[0].clone(), "")]);
                }
                _ => {
                    let sym = &cx.plan.drop[&ty];
                    crate::glue_llvm::call_drop(b, &mut cx.decls, lay, sym, ty, args);
                }
            }
            if guarded {
                b.br(&join);
                b.label(&join);
            }
        }
        Op::Call => {
            let Imm::Func(c) = inst.imm else { return };
            let callee = &m.funcs[c.index()];
            let sym = (cx.symbol_of)(c.index());
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
            cx.decls.push((
                sym.clone(),
                format!(
                    "declare {attr}{} @\"{sym}\"({}){}",
                    Types::default().text(&ret),
                    formals.join(", "),
                    pure_attrs(m, lay, c.index(), &mut cx.memo).unwrap_or("")
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

//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

mod arith;
mod attrs;
mod calls;
mod closures;
mod depth;
mod enums;
mod glue;
mod lists;
mod maps;
mod records;

use crate::abi_llvm::{Pass, Ret, Signature};
use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use crate::llvm_ir::DirectEnv;
use attrs::pure_attrs;
use ms_mir::ir::{Func, Imm, Inst, Mode, Module, Op, Target, Term};
use ms_mir::types::{Ty, TyKind};
use std::collections::{HashMap, HashSet};

/// Where the function sits in the module: its index, its grow shim when it has a stack-depth
/// check, and the set of functions in the native calling convention.
pub struct Place<'a> {
    pub idx: usize,
    pub grow_shim: Option<String>,
    pub native: &'a HashSet<usize>,
}

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

/// `Bool` is zero or one.
const BOOL_ATTR: &str = " zeroext range(i8 0, 2)";
/// A list length counts elements of a buffer, so it is not negative (the range wraps: it is
/// `[0, 2^63)`).
const LEN_ATTR: &str = " range(i64 0, -9223372036854775808)";

/// The leaves of a value of type `ty`, in calling-convention order, each with its attributes. The
/// attributes are facts about the value, not the register: `Bool` is 0 or 1 and a list's length
/// is not negative, which lets LLVM drop checks and fold comparisons. A string's words are a tagged
/// encoding, so only lists and bytes carry a length range. Callers and callees both follow the
/// MIR types, so the facts hold across the Cranelift path too.
fn leaves(lay: &Layouts, ty: Ty) -> Vec<(LTy, &'static str)> {
    let mut ls: Vec<_> = lay.leaves(ty).into_iter().map(leaf).collect();
    match lay.m.types.kind(ty) {
        TyKind::Bool => ls[0].1 = BOOL_ATTR,
        TyKind::Bytes | TyKind::List(_) => ls[1].1 = LEN_ATTR,
        _ => {}
    }
    ls
}

/// Whether this stage handles values of `ty`: some area accepts its kind.
fn supported_ty(lay: &Layouts, ty: Ty) -> bool {
    let kind = lay.m.types.kind(ty);
    records::ty_ok(lay, ty) || AREAS.iter().any(|a| (a.ty_ok)(kind))
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
        [(_, a)] if *a == BOOL_ATTR => "zeroext range(i8 0, 2) ",
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

/// One area of the emitter: the ops, types and checks it owns. Each area lives in its own module
/// and is listed once in [`AREAS`]; unused hooks stay at [`Area::NONE`]. A thread adds support
/// for its ops by editing its own module only.
struct Area {
    /// Whether this area emits `op`.
    handles: fn(Op) -> bool,
    /// Whether this area can hold values of this kind in registers.
    ty_ok: fn(&TyKind) -> bool,
    /// Extra conditions on one instruction of an op this area handles.
    inst_ok: fn(&Module, &Layouts, &Func, &Inst) -> bool,
    /// How many blocks the op splits off (its checks only when checks are on).
    splits: fn(Op, bool) -> usize,
    /// Whether the op touches neither memory nor anything a fault could depend on.
    pure_op: fn(Op) -> bool,
    /// The value an instruction is without any code (a constant, a leaf of its operand).
    pre: fn(&Layouts, &Func, &Inst, &Vals) -> Option<Vec<Val>>,
    /// Writes one instruction of a handled op; each result leaf takes its reserved name.
    emit: fn(&mut Cx, &Inst, &Vals, &mut FnBuilder),
}

impl Area {
    /// An area that handles nothing.
    const NONE: Area = Area {
        handles: |_| false,
        ty_ok: |_| false,
        inst_ok: |_, _, _, _| true,
        splits: |_, _| 0,
        pure_op: |_| false,
        pre: |_, _, _, _| None,
        emit: |_, _, _, _| unreachable!("an area emits only the ops it handles"),
    };
}

/// Every area, one line each.
const AREAS: &[Area] = &[
    arith::AREA,
    lists::AREA,
    calls::AREA,
    records::AREA,
    depth::AREA,
    glue::AREA,
    enums::AREA,
    maps::AREA,
    closures::AREA,
];

fn area_of(op: Op) -> Option<&'static Area> {
    AREAS.iter().find(|a| (a.handles)(op))
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
            if !area_of(i.op).is_some_and(|a| (a.inst_ok)(m, lay, f, i))
                || i.res.is_some_and(|r| !ty_ok(r))
                || i.args.iter().any(|a| !ty_ok(*a))
                || (i.op == Op::Select && i.res.is_some_and(|r| records::is_mem(lay, f.ty(r))))
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
    /// Which callees are pure, and whether they return (see [`pure_attrs`]).
    memo: HashMap<usize, Option<bool>>,
    /// `(symbol, declare line)` of each callee.
    decls: Vec<(String, String)>,
    /// MIR block being written and the checks it has split off so far.
    block: usize,
    split: usize,
    /// The entry parameters as they arrive, one per leaf, and the result leaves: what the
    /// stack-depth check passes to a new stack segment and returns.
    entry_abi: Vec<Val>,
    ret_abi: Vec<LTy>,
    /// Symbol of the function's grow shim, when it has a stack-depth check.
    grow_shim: Option<String>,
    /// The functions in the native calling convention (`abi_llvm`); every other function takes
    /// and returns leaves.
    native: &'a HashSet<usize>,
}

/// The label a MIR block ends in: each check splits it, and a successor's phis name that label.
fn exit_label(f: &Func, checks: bool, bb: usize) -> String {
    let n = f.blocks[bb]
        .insts
        .iter()
        .map(|i| area_of(i.op).map_or(0, |a| (a.splits)(i.op, checks)))
        .sum();
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

/// Emits `f`, which `supports` accepted. The function has MIR index `idx` and, when it is
/// recursive, the grow shim `grow_shim`. `symbol_of` names the function with MIR index `i`;
/// `loc` is the `DILocation` node every instruction carries.
pub fn emit(
    m: &Module,
    lay: &Layouts,
    Place {
        idx,
        grow_shim,
        native,
    }: Place,
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
    let mut entry_abi = Vec::new();
    let sig = native
        .contains(&idx)
        .then(|| Signature::of(lay, &f.params, f.ret));
    let sret = sig
        .as_ref()
        .is_some_and(|s| matches!(s.result, Ret::Sret(_)))
        .then(|| Val::new("%sret", LTy::Ptr));
    entry_abi.extend(sret.iter().cloned());
    for (i, p) in f.params.iter().enumerate() {
        if let Some(Pass::Indirect(..)) = sig.as_ref().map(|s| &s.passes[i]) {
            let ptr = Val::new(format!("%a{i}"), LTy::Ptr);
            entry_abi.push(ptr.clone());
            let own = records::bind_indirect(&mut b, lay, p.ty, ptr, &mut entry);
            vals.insert(f.blocks[0].params[i].value.index(), own);
            continue;
        }
        let mut abi = Vec::new();
        for (j, (t, attr)) in leaves(lay, p.ty).into_iter().enumerate() {
            params.push(format!("{}{attr} %a{i}_{j}", types.text(&t)));
            abi.push(Val::new(format!("%a{i}_{j}"), t));
        }
        entry_abi.extend(abi.iter().cloned());
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
            let pre = area_of(inst.op).and_then(|a| (a.pre)(lay, f, inst, &vals));
            let own = match pre.or_else(|| records::bind_early(&mut b, lay, f, &vals, inst)) {
                Some(own) => own,
                None => records::reserve(&mut b, lay, f.ty(res)),
            };
            vals.insert(res.index(), own);
        }
    }
    // Incoming edges of every block, for the phis. Copies into a record's slot run only on their
    // own edge, so a conditional edge that has some is a block of its own, named after the block
    // it leaves.
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
        memo: HashMap::new(),
        decls: Vec::new(),
        block: 0,
        split: 0,
        entry_abi,
        ret_abi: if sret.is_some() {
            Vec::new()
        } else {
            depth::ret_abi(lay, f.ret)
        },
        grow_shim,
        native,
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
            inst_text(&mut cx, inst, &vals, &mut b);
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
            Term::Ret(Some(v)) if sret.is_some() => {
                let to = sret.as_ref().expect("checked");
                records::store_result(&mut b, lay, f.ty(*v), &vals, *v, to);
                b.ret(None);
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
        ret: sig
            .as_ref()
            .map_or_else(|| ret_text(lay, f.ret), |s| s.ret.clone()),
        params: sig
            .as_ref()
            .map_or_else(|| params.join(", "), Signature::define_params),
        attrs: pure_attrs(m, lay, native, idx, &mut cx.memo)
            .unwrap_or("")
            .to_string(),
        body: b.finish(),
        decls: cx.decls,
    }
}

/// Writes one instruction with the area that owns its op.
fn inst_text(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let area = area_of(inst.op).expect("supports rejects other ops");
    (area.emit)(cx, inst, vals, b);
}

/// The grow shim of the native function `f` called `sym` (see [`depth::shim`]).
pub fn grow_shim(lay: &Layouts, f: &Func, sym: &str, dbg: usize) -> Emitted {
    depth::shim(lay, f, sym, dbg)
}

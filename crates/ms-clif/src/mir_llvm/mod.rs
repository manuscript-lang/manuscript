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
mod faults;
mod globals;
mod glue;
mod lists;
mod maps;
mod records;
pub(crate) mod rt;
mod strings;

use crate::abi_llvm::{Pass, Reg, Ret, Signature};
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

/// The glue a closure object points to.
pub struct ClosureSyms {
    pub clone: String,
    pub drop: String,
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
    /// Symbols of the data objects the function addresses.
    pub data: Vec<String>,
    /// `(symbol, definition)` of the private constants the function addresses (string
    /// literals). Each unit that names one defines it.
    pub consts: Vec<(String, String)>,
}

/// What a function needs from the module before it is emitted: whether checks are on, and the
/// symbols of the glue, descriptors and vtables its instructions name. The driver declares them
/// (glue is queued for generation).
#[derive(Default)]
pub struct Plan {
    /// Whether bounds checks are emitted.
    pub checks: bool,
    /// Symbol to call for the `Clone` glue of a type (see `glue_llvm::target`).
    pub clone: HashMap<Ty, String>,
    /// Symbol to call for the `Drop` glue of a type.
    pub drop: HashMap<Ty, String>,
    /// Type descriptor symbol by type.
    pub desc: HashMap<Ty, String>,
    /// Symbol of the cleanup thunk by the MIR index of the closer.
    pub cleanup: HashMap<usize, String>,
    /// `closure.new` results that live in a stack slot.
    pub framed_closures: HashSet<usize>,
    /// `iface.borrow` results that keep their leaves in a stack slot.
    pub framed_ifaces: HashSet<usize>,
    /// The glue of each closure function, by `(function, framed)`.
    pub closures: HashMap<(usize, bool), ClosureSyms>,
    /// The data symbol of each vtable an instruction names.
    pub vtables: HashMap<usize, String>,
    /// The data symbol of each global an instruction names.
    pub globals: HashMap<usize, String>,
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

/// `range` of the case index of an enum with `n` cases: `[0, n)`. Enums have few cases, so the
/// text is static; a larger enum carries no range.
pub(crate) fn tag_attr(n: usize) -> &'static str {
    const RANGES: [&str; 16] = [
        " range(i64 0, 1)",
        " range(i64 0, 2)",
        " range(i64 0, 3)",
        " range(i64 0, 4)",
        " range(i64 0, 5)",
        " range(i64 0, 6)",
        " range(i64 0, 7)",
        " range(i64 0, 8)",
        " range(i64 0, 9)",
        " range(i64 0, 10)",
        " range(i64 0, 11)",
        " range(i64 0, 12)",
        " range(i64 0, 13)",
        " range(i64 0, 14)",
        " range(i64 0, 15)",
        " range(i64 0, 16)",
    ];
    n.checked_sub(1)
        .and_then(|i| RANGES.get(i))
        .copied()
        .unwrap_or("")
}

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
        // An enum held as leaves starts with its case index.
        TyKind::Alt(a) if !lay.is_boxed(*a) => {
            ls[0].1 = tag_attr(lay.m.alts[a.index()].cases.len())
        }
        _ => {}
    }
    ls
}

/// The types a value of type `ty` is held as inside a function: its leaves, with the pointer
/// ones as `ptr` (`Layouts::pointer_leaves`) and the boolean ones as `i1` (`Layouts::bool_leaves`).
/// A function gets and returns a boolean as `i8`, and in the leaf convention a pointer as `i64`,
/// and converts at its entry and returns; memory holds the `mem_leaves`.
fn held_leaves(lay: &Layouts, ty: Ty) -> Vec<LTy> {
    let (ptrs, bools) = (lay.pointer_leaves(ty), lay.bool_leaves(ty));
    let mut tys: Vec<LTy> = lay.leaves(ty).into_iter().map(|l| leaf(l).0).collect();
    for (k, t) in tys.iter_mut().enumerate() {
        if ptrs[k] {
            *t = LTy::Ptr;
        } else if bools[k] {
            *t = LTy::I1;
        }
    }
    tys
}

/// The types a value of type `ty` has in memory: its leaves, with the pointer ones as `ptr`, a
/// boolean as the `i8` it is stored as, and a narrow integer as the 1, 2 or 4 byte integer it
/// occupies (`mem_leaf`).
fn mem_leaves(lay: &Layouts, ty: Ty) -> Vec<LTy> {
    let mut tys: Vec<LTy> = lay.leaves(ty).into_iter().map(mem_leaf).collect();
    for (t, ptr) in tys.iter_mut().zip(lay.pointer_leaves(ty)) {
        if ptr {
            *t = LTy::Ptr;
        }
    }
    tys
}

/// The memory type of one leaf: a narrow integer is held in an `i64` register and stored in its
/// own width.
fn mem_leaf(l: Leaf) -> LTy {
    match l {
        Leaf::N8 | Leaf::U8 => LTy::I8,
        Leaf::N16 | Leaf::U16 => LTy::I16,
        Leaf::N32 | Leaf::U32 => LTy::I32,
        l => leaf(l).0,
    }
}

/// Per leaf of `ty`: whether loading it from memory sign-extends (`Int8` to `Int32`). Other
/// narrow leaves zero-extend; wider ones are not extended.
fn signed_leaves(lay: &Layouts, ty: Ty) -> Vec<bool> {
    lay.leaves(ty)
        .into_iter()
        .map(|l| matches!(l, Leaf::N8 | Leaf::N16 | Leaf::N32))
        .collect()
}

/// The struct a value of type `ty` has in memory: named for strings, lists and records, so the
/// module defines each once, else a literal struct of its held leaves.
pub(crate) fn aggregate(types: &Types, lay: &Layouts, ty: Ty) -> LTy {
    let fields = mem_leaves(lay, ty);
    let name = match lay.m.types.kind(ty) {
        TyKind::Str => "ms.str".to_string(),
        TyKind::Bytes => "ms.bytes".to_string(),
        TyKind::List(_) => "ms.list".to_string(),
        TyKind::Rec(r) => format!("ms.rec.{}", lay.m.records[r.index()].name),
        TyKind::Alt(a) if !lay.is_boxed(*a) => format!("ms.enum.{}", lay.m.alts[a.index()].name),
        TyKind::Opt(_) => format!("ms.opt.{}", ty.index()),
        _ => return LTy::Tuple(fields),
    };
    types.named(&name, fields)
}

/// The LLVM type of a register of the native convention.
fn reg_ty(r: Reg) -> LTy {
    match r {
        Reg::I64 => LTy::I64,
        Reg::F64 => LTy::F64,
        Reg::I8 => LTy::I8,
        Reg::Ptr => LTy::Ptr,
    }
}

/// The result as it crosses a call: the `void`, the register or a tuple of them, in the native
/// convention when `native` and as leaves otherwise.
fn call_ret_ty(lay: &Layouts, ty: Ty, native: bool) -> LTy {
    if !native {
        return ret_ty(lay, ty);
    }
    let mut tys: Vec<LTy> = crate::abi_llvm::regs_of(lay, ty)
        .into_iter()
        .map(reg_ty)
        .collect();
    match tys.len() {
        0 => LTy::Void,
        1 => tys.remove(0),
        _ => LTy::Tuple(tys),
    }
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

/// An area's `pre` hook: the values an instruction is without any code, naming (not defining)
/// any it leaves for `emit`.
type Pre = fn(&Module, &Layouts, &Func, &Inst, &Vals, &mut FnBuilder) -> Option<Vec<Val>>;

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
    splits: fn(&Layouts, &Func, &Inst, bool) -> usize,
    /// Whether the op touches neither memory nor anything a fault could depend on.
    pure_op: fn(Op) -> bool,
    /// The value an instruction is without any code (a constant, a leaf of its operand).
    pre: Pre,
    /// Writes one instruction of a handled op; each result leaf takes its reserved name.
    emit: fn(&mut Cx, &Inst, &Vals, &mut FnBuilder),
}

impl Area {
    /// An area that handles nothing.
    const NONE: Area = Area {
        handles: |_| false,
        ty_ok: |_| false,
        inst_ok: |_, _, _, _| true,
        splits: |_, _, _, _| 0,
        pure_op: |_| false,
        pre: |_, _, _, _, _, _| None,
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
    globals::AREA,
    strings::AREA,
    enums::AREA,
    maps::AREA,
    closures::AREA,
];

fn area_of(op: Op) -> Option<&'static Area> {
    AREAS.iter().find(|a| (a.handles)(op))
}

/// Why `f` cannot be emitted directly, or `None` when it can.
pub fn unsupported(m: &Module, lay: &Layouts, f: &Func) -> Option<String> {
    let ty_name = |t: Ty| {
        let kind = format!("{:?}", m.types.kind(t));
        let end = kind.find(['(', ' ', '{']).unwrap_or(kind.len());
        format!("type {}", &kind[..end])
    };
    if !signature_ok(lay, &f.params, f.ret) {
        return Some("signature".into());
    }
    let ty_ok = |v| supported_ty(lay, f.ty(v));
    let rpo = f.rpo();
    // The entry block must have no predecessors (LLVM forbids a branch to it).
    let mut entry_target = false;
    for b in &rpo {
        let bd = &f.blocks[b.index()];
        if let Some(p) = bd.params.iter().find(|p| !ty_ok(p.value)) {
            return Some(format!("block parameter of {}", ty_name(f.ty(p.value))));
        }
        for i in &bd.insts {
            let Some(area) = area_of(i.op) else {
                return Some(format!("op {:?} has no lowering", i.op));
            };
            if !(area.inst_ok)(m, lay, f, i) {
                return Some(format!("op {:?} in a shape it does not lower", i.op));
            }
            if let Some(v) = i
                .res
                .into_iter()
                .chain(i.args.iter().copied())
                .find(|v| !ty_ok(*v))
            {
                return Some(format!("op {:?} on {}", i.op, ty_name(f.ty(v))));
            }
            if i.op == Op::Select && i.res.is_some_and(|r| records::is_mem(lay, f.ty(r))) {
                return Some("select of a record".into());
            }
            if i.op == Op::Call {
                let Imm::Func(c) = i.imm else {
                    return Some("call without a callee".into());
                };
                let callee = &m.funcs[c.index()];
                if !signature_ok(lay, &callee.params, callee.ret) {
                    return Some(format!(
                        "call to {} with an unsupported signature",
                        callee.name
                    ));
                }
            }
        }
        let ok = match &bd.term {
            Term::Br(t) => !is_entry(t),
            Term::CondBr { then, els, .. } => !is_entry(then) && !is_entry(els),
            Term::Ret(_) | Term::Unreachable => true,
            Term::Switch { cases, default, .. } => {
                !cases.iter().map(|c| &c.1).chain([default]).any(is_entry)
            }
            Term::Fault(k) => faults::terminator_ok(*k),
        };
        if !ok {
            return Some("terminator".into());
        }
        bd.term.for_each_target(|t| entry_target |= is_entry(t));
    }
    entry_target.then(|| "branch to the entry block".into())
}

/// Whether the emitter can emit `f`.
pub fn supports(m: &Module, lay: &Layouts, f: &Func) -> bool {
    unsupported(m, lay, f).is_none()
}

/// Whether the edge of a conditional terminator to `t` is a block of its own, named after the block
/// it leaves: it copies into a record's slot, which only its own edge may do, or its target is also
/// reached by another edge of the same terminator, whose phi entries need distinct predecessors.
fn split_edge(lay: &Layouts, f: &Func, term: &Term, t: &Target) -> bool {
    let mut reached = 0;
    term.for_each_target(|u| reached += usize::from(u.block == t.block));
    !matches!(term, Term::Br(_)) && (reached > 1 || records::has_copies(lay, f, t))
}

/// The labels the edges of `term` branch to, in target order: the target itself, or the edge's own
/// block `{from}_e{k}` (see [`split_edge`]).
fn edge_labels(lay: &Layouts, f: &Func, term: &Term, from: &str) -> Vec<String> {
    let mut labels = Vec::new();
    term.for_each_target(|t| {
        labels.push(if split_edge(lay, f, term, t) {
            format!("{from}_e{}", labels.len())
        } else {
            block_label(t.block.index(), 0)
        });
    });
    labels
}

/// Writes the blocks of the split edges named by `labels`.
fn edge_blocks(
    b: &mut FnBuilder,
    lay: &Layouts,
    f: &Func,
    vals: &Vals,
    term: &Term,
    labels: &[String],
) {
    let mut k = 0;
    term.for_each_target(|t| {
        if split_edge(lay, f, term, t) {
            b.label(&labels[k]);
            records::copies(b, lay, f, vals, t);
            b.br(&block_label(t.block.index(), 0));
        }
        k += 1;
    });
}

fn is_entry(t: &Target) -> bool {
    t.block.index() == 0
}

/// What emitting one function needs besides the builder.
struct Cx<'a> {
    m: &'a Module,
    f: &'a Func,
    lay: &'a Layouts<'a>,
    /// The glue and descriptors the function refers to.
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
fn exit_label(lay: &Layouts, f: &Func, checks: bool, bb: usize) -> String {
    let n = f.blocks[bb]
        .insts
        .iter()
        .map(|i| area_of(i.op).map_or(0, |a| (a.splits)(lay, f, i, checks)))
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
    plan: &Plan,
    env: &mut DirectEnv,
    symbol_of: &dyn Fn(usize) -> String,
) -> Emitted {
    let checks = plan.checks;
    let types = env.types;
    let mut b = FnBuilder::new(types, Some(env.loc));
    let rpo = f.rpo();
    // Name every value before emitting anything: a phi names values a later block defines (the
    // back edge of a loop), and a constant is its own text.
    let mut vals: Vals = HashMap::new();
    let mut params = Vec::new();
    let mut entry = Vec::new();
    let mut entry_abi = Vec::new();
    let sig = native
        .contains(&idx)
        .then(|| Signature::of(types, lay, &f.params, &f.noalias, f.ret));
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
        let regs = match sig.as_ref().map(|s| &s.passes[i]) {
            Some(Pass::Scalars(r)) => Some(r),
            _ => None,
        };
        for (j, (t, attr)) in leaves(lay, p.ty).into_iter().enumerate() {
            params.push(format!("{}{attr} %a{i}_{j}", types.text(&t)));
            let t = regs.map_or(t, |r| reg_ty(r[j]));
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
            let pre = area_of(inst.op).and_then(|a| (a.pre)(m, lay, f, inst, &vals, &mut b));
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
            let from = exit_label(lay, f, checks, bb.index());
            let from = if split_edge(lay, f, term, t) {
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
        plan,
        checks,
        sites: *env.sites,
        symbol_of,
        memo: HashMap::new(),
        decls: Vec::new(),
        data: Vec::new(),
        block: 0,
        split: 0,
        entry_abi,
        ret_abi: if sret.is_some() {
            Vec::new()
        } else {
            depth::ret_abi(lay, f.ret, sig.is_some())
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
        // A fault names the position of its terminator in the trace.
        b.set_dbg(Some(env.at(bd.term_loc)));
        match &bd.term {
            Term::Br(t) => {
                records::copies(&mut b, lay, f, &vals, t);
                b.br(&block_label(t.block.index(), 0));
            }
            Term::CondBr { cond, .. } => {
                let c = vals[&cond.index()][0].clone();
                let from = exit_label(lay, f, checks, bb.index());
                let to = edge_labels(lay, f, &bd.term, &from);
                b.cond_br(&c, &to[0], &to[1]);
                edge_blocks(&mut b, lay, f, &vals, &bd.term, &to);
            }
            Term::Switch { value, cases, .. } => {
                let from = exit_label(lay, f, checks, bb.index());
                let to = edge_labels(lay, f, &bd.term, &from);
                let arms: Vec<(i64, String)> = cases
                    .iter()
                    .zip(&to)
                    .map(|((k, _), l)| (*k, l.clone()))
                    .collect();
                b.switch(&vals[&value.index()][0], &to[cases.len()], &arms);
                edge_blocks(&mut b, lay, f, &vals, &bd.term, &to);
            }
            Term::Ret(Some(v)) if sret.is_some() => {
                let to = sret.as_ref().expect("checked");
                records::store_result(&mut b, lay, f.ty(*v), &vals, *v, to);
                b.ret(None);
            }
            Term::Ret(Some(v)) => {
                let abi = records::abi_leaves(&mut b, lay, f.ty(*v), &vals, *v, sig.is_some());
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
            Term::Fault(k) => faults::terminator(&mut cx, &mut b, *k),
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
        data: cx.data,
        consts: lists::consts(m, lay, f),
    }
}

/// Writes one instruction with the area that owns its op.
fn inst_text(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let area = area_of(inst.op).expect("supports rejects other ops");
    (area.emit)(cx, inst, vals, b);
}

/// The grow shim of the native function `f` called `sym` (see [`depth::shim`]).
pub fn grow_shim(types: &Types, lay: &Layouts, f: &Func, sym: &str, dbg: usize) -> Emitted {
    depth::shim(types, lay, f, sym, dbg)
}

/// The grow shim of the leaf-convention function `f` called `sym`.
pub fn leaf_grow_shim(types: &Types, lay: &Layouts, f: &Func, sym: &str, dbg: usize) -> Emitted {
    depth::leaf_shim(types, lay, f, sym, dbg)
}

#[cfg(test)]
mod coverage {
    use super::*;

    /// The ops no area lowers yet. An op leaves this list when an area handles it; the scope
    /// markers are not here because `elaborate` removes them before code generation.
    const UNLOWERED: &[Op] = &[Op::AltOwn, Op::RecRelease, Op::OptUnwrap, Op::OptAddr];

    const MARKERS: &[Op] = &[
        Op::ScopeBegin,
        Op::ScopeOwn,
        Op::ScopeEnd,
        Op::ScopeDisown,
        Op::ScopeMark,
    ];

    #[test]
    fn every_op_is_lowered_or_listed() {
        for &op in Op::ALL {
            let lowered = area_of(op).is_some();
            let listed = UNLOWERED.contains(&op);
            let marker = MARKERS.contains(&op);
            assert!(
                marker || lowered != listed,
                "{op:?}: {}",
                if lowered {
                    "lowered, so remove it from UNLOWERED"
                } else {
                    "not lowered: implement it or add it to UNLOWERED"
                }
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::tag_attr;

    #[test]
    fn a_case_index_is_below_the_case_count() {
        assert_eq!(tag_attr(3), " range(i64 0, 3)");
        assert_eq!(tag_attr(16), " range(i64 0, 16)");
        // No cases, or more than the table holds: no claim.
        assert_eq!(tag_attr(0), "");
        assert_eq!(tag_attr(17), "");
    }
}

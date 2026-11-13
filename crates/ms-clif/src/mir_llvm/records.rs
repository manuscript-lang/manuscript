//! Records, raw memory and `ptr` values in the direct emitter.
//!
//! A record of at most [`MEM_LEAVES`] leaves is a list of register values like any other value, so
//! `rec.new`, `rec.get` and `rec.set` only move leaves around and cost nothing. A larger record is
//! kept in memory instead: its value is a `ptr` to one immutable `alloca` of a literal struct with
//! the record's leaves as fields (the offsets are those of `layout::mem_layout`, so they match the
//! runtime and the Cranelift object). A copy is one `memcpy`, a field read an offset and one
//! aligned `load`, and LLVM's `sroa` and `memcpyopt` turn that back into registers where it pays
//! and drop the fields nobody reads. The flat leaf list exists only where the shared calling
//! convention asks for it: a call, a return and the entry of a function.
//!
//! A block parameter of such a record has a slot of its own that each incoming edge copies into,
//! so a loop that carries a record does not carry a phi per leaf.
//!
//! Values of type `ptr` are LLVM `ptr` inside a function and `i64` across a call. A record that
//! holds a `ptr` is not handled (its leaf is an integer here); the function falls back.

use super::{Area, Cx, Vals, held_leaves};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Func, Imm, Inst, Op, Target, Value};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    inst_ok: |_, lay, f, i| op_ok(lay, f, i),
    emit,
    ..Area::NONE
};

/// Records with more leaves than this live in memory.
pub(super) const MEM_LEAVES: usize = 8;

/// The memory shape of a type whose leaves are all `i64`, `f64`, `i8` or `ptr`.
pub(super) struct Shape {
    /// The struct of the leaves.
    pub st: LTy,
    /// Memory type of each leaf.
    pub leaves: Vec<LTy>,
    pub size: u32,
    pub align: u32,
}

/// The memory type of the leaves of `ty`: a struct named after a record, string or list, else a
/// literal one; `None` when it has none or a leaf differs in registers and in memory.
fn shape_leaves(lay: &Layouts, ty: Ty) -> Option<(Vec<LTy>, crate::layout::MemLayout)> {
    let raw = lay.leaves(ty);
    if raw.is_empty()
        || raw
            .iter()
            .any(|l| !matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
    {
        return None;
    }
    Some((held_leaves(lay, ty), mem_layout(&raw)))
}

/// Whether `ty` has a memory shape.
pub(super) fn shape_ok(lay: &Layouts, ty: Ty) -> bool {
    shape_leaves(lay, ty).is_some()
}

/// The shape of `ty`, when it has leaves and every leaf has the same size in registers and in memory.
pub(super) fn shape(types: &Types, lay: &Layouts, ty: Ty) -> Option<Shape> {
    let (leaves, mem) = shape_leaves(lay, ty)?;
    Some(Shape {
        st: super::aggregate(types, lay, ty),
        leaves,
        size: mem.size,
        align: mem.align,
    })
}

fn record(lay: &Layouts, ty: Ty) -> Option<ms_mir::types::RecId> {
    match lay.m.types.kind(ty) {
        TyKind::Rec(r) if !lay.m.records[r.index()].indirect => Some(*r),
        _ => None,
    }
}

/// Whether a value of `ty` is held as a pointer to memory.
pub(super) fn is_mem(lay: &Layouts, ty: Ty) -> bool {
    record(lay, ty).is_some() && lay.width(ty) > MEM_LEAVES
}

/// Whether this module handles values of `ty`: `ptr`, and records that are either small or have a
/// memory shape.
pub(super) fn ty_ok(lay: &Layouts, ty: Ty) -> bool {
    ty == Ty::PTR
        || (record(lay, ty).is_some() && (lay.width(ty) <= MEM_LEAVES || shape_ok(lay, ty)))
}

/// The ops this module emits.
pub(super) fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::RecNew
            | Op::RecGet
            | Op::RecSet
            | Op::RecFill
            | Op::Slot
            | Op::Load
            | Op::Take
            | Op::Store
            | Op::Put
            | Op::PtrField
    )
}

/// Whether the operands and immediate of `i` are within what this module emits.
pub(super) fn op_ok(lay: &Layouts, f: &Func, i: &Inst) -> bool {
    let mem_ty = |t: Ty| shape_ok(lay, t);
    match (i.op, i.imm) {
        (Op::Slot, Imm::Ty(t)) => mem_ty(t),
        (Op::Load | Op::Take, Imm::Ty(t)) => mem_ty(t) && i.res.is_some_and(|r| f.ty(r) == t),
        (Op::Store | Op::Put, _) => mem_ty(f.ty(i.args[1])),
        (Op::PtrField | Op::RecGet | Op::RecSet | Op::RecFill, Imm::Field(r, _)) => {
            !lay.m.records[r.index()].indirect
        }
        (Op::RecNew, _) => true,
        (
            Op::Slot | Op::Load | Op::Take | Op::PtrField | Op::RecGet | Op::RecSet | Op::RecFill,
            _,
        ) => false,
        _ => true,
    }
}

/// The values a MIR value of type `ty` is held as: its leaves, with `ptr` as `ptr`; a record in
/// memory is one `ptr`.
pub(super) fn held(lay: &Layouts, ty: Ty) -> Vec<LTy> {
    if is_mem(lay, ty) {
        return vec![LTy::Ptr];
    }
    held_leaves(lay, ty)
}

/// The values of a block parameter: its own reserved names, or for a record in memory a slot that
/// each incoming edge copies into.
pub(super) fn block_param(b: &mut FnBuilder, lay: &Layouts, ty: Ty) -> Vec<Val> {
    if is_mem(lay, ty) {
        let st = shape(b.types(), lay, ty).expect("is_mem checked").st;
        return vec![b.alloca(&st)];
    }
    reserve(b, lay, ty)
}

/// Reserves the names a result of type `ty` is held under; a record in memory is one `ptr`, the
/// address of its slot.
pub(super) fn reserve(b: &mut FnBuilder, lay: &Layouts, ty: Ty) -> Vec<Val> {
    held(lay, ty).into_iter().map(|t| b.reserve(t)).collect()
}

/// Leaf index and count of field `i` of record type `rty`.
fn field_span(lay: &Layouts, rty: Ty, i: usize) -> (usize, usize) {
    let r = record(lay, rty).expect("a record");
    let fields = &lay.m.records[r.index()].fields;
    let at = fields[..i].iter().map(|f| lay.width(f.1)).sum();
    (at, lay.width(fields[i].1))
}

/// The leaves of `v` as they cross a call: a record in memory loaded, and each pointer as itself
/// in the native convention (`native`) or as its address (`i64`) in the leaf convention.
pub(super) fn abi_leaves(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    vals: &Vals,
    v: Value,
    native: bool,
) -> Vec<Val> {
    let own = &vals[&v.index()];
    let leaves = if is_mem(lay, ty) {
        let s = shape(b.types(), lay, ty).expect("is_mem checked");
        load_leaves(b, &s, &own[0], 0, s.leaves.len(), &[])
    } else {
        own.clone()
    };
    if native {
        return leaves;
    }
    leaves
        .into_iter()
        .map(|l| {
            if l.ty == LTy::Ptr {
                b.ptr_to_int(&l)
            } else {
                l
            }
        })
        .collect()
}

/// Loads leaves `at..at + n` of the record at `base`; each takes the matching name of `named`
/// (a result that phis may already use), or a fresh one.
fn load_leaves(
    b: &mut FnBuilder,
    s: &Shape,
    base: &Val,
    at: usize,
    n: usize,
    named: &[Val],
) -> Vec<Val> {
    (at..at + n)
        .map(|k| {
            let p = b.field_ptr(&s.st, base, k);
            if let Some(v) = named.get(k - at) {
                b.name_next(v);
            }
            b.load(&s.leaves[k], &p, align(&s.leaves[k]))
        })
        .collect()
}

fn store_leaves(b: &mut FnBuilder, s: &Shape, base: &Val, at: usize, leaves: &[Val]) {
    for (k, v) in leaves.iter().enumerate() {
        let p = b.field_ptr(&s.st, base, at + k);
        b.store(v, &p, align(&v.ty));
    }
}

/// A leaf's alignment in memory: its size.
fn align(t: &LTy) -> u64 {
    if *t == LTy::I8 { 1 } else { 8 }
}

/// What the entry block must do before anything else: define the values of parameters that do not
/// arrive as they are used.
pub(super) enum Entry {
    /// A pointer leaf arrives as an address.
    Ptr { held: Val, abi: Val },
    /// A record in memory arrives as leaves and is stored into its slot.
    Mem { slot: Val, abi: Vec<Val>, ty: Ty },
    /// A value passed by pointer (see `abi_llvm`) is loaded into its leaves.
    Load { ptr: Val, dsts: Vec<Val>, ty: Ty },
}

/// The held values of an entry parameter of type `ty` that arrives as `abi`, and what the entry
/// must do to define them.
pub(super) fn bind_param(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    abi: Vec<Val>,
    entry: &mut Vec<Entry>,
) -> Vec<Val> {
    if is_mem(lay, ty) {
        let slot = b.alloca(&shape(b.types(), lay, ty).expect("is_mem checked").st);
        entry.push(Entry::Mem {
            slot: slot.clone(),
            abi,
            ty,
        });
        return vec![slot];
    }
    // Pointer leaves that arrive as addresses are converted at the top of the entry block.
    abi.into_iter()
        .zip(held_leaves(lay, ty))
        .map(|(a, t)| {
            if t == LTy::Ptr && a.ty == LTy::I64 {
                let held = b.reserve(LTy::Ptr);
                entry.push(Entry::Ptr {
                    held: held.clone(),
                    abi: a,
                });
                held
            } else {
                a
            }
        })
        .collect()
}

pub(super) fn emit_entry(b: &mut FnBuilder, lay: &Layouts, entry: Vec<Entry>) {
    for e in entry {
        match e {
            Entry::Ptr { held, abi } => {
                b.name_next(&held);
                b.int_to_ptr(&abi);
            }
            Entry::Mem { slot, abi, ty } => {
                let s = shape(b.types(), lay, ty).expect("is_mem checked");
                store_leaves(b, &s, &slot, 0, &abi);
            }
            Entry::Load { ptr, dsts, ty } => {
                let st = super::aggregate(b.types(), lay, ty);
                for (k, dst) in dsts.iter().enumerate() {
                    let p = b.field_ptr(&st, &ptr, k);
                    b.name_next(dst);
                    b.load(&dst.ty, &p, align(&dst.ty));
                }
            }
        }
    }
}

/// Whether following `t` copies a record into the slots of the target's parameters.
pub(super) fn has_copies(lay: &Layouts, f: &Func, t: &Target) -> bool {
    f.blocks[t.block.index()]
        .params
        .iter()
        .any(|p| is_mem(lay, f.ty(p.value)))
}

/// Copies the record arguments of `t` into the slots of the target's parameters. An argument that
/// is itself one of those slots (a swap) is copied aside first.
pub(super) fn copies(b: &mut FnBuilder, lay: &Layouts, f: &Func, vals: &Vals, t: &Target) {
    let params = &f.blocks[t.block.index()].params;
    let mut pairs = Vec::new();
    for (p, a) in params.iter().zip(&t.args) {
        if is_mem(lay, f.ty(p.value)) {
            let s = shape(b.types(), lay, f.ty(p.value)).expect("is_mem checked");
            pairs.push((
                vals[&p.value.index()][0].clone(),
                vals[&a.index()][0].clone(),
                s,
            ));
        }
    }
    let clash = pairs
        .iter()
        .any(|(_, src, _)| pairs.iter().any(|(dst, _, _)| dst.text == src.text));
    for (dst, mut src, s) in pairs {
        if clash {
            let tmp = b.alloca(&s.st);
            b.copy_bytes(&tmp, &src, s.size as u64, s.align as u64);
            src = tmp;
        }
        b.copy_bytes(&dst, &src, s.size as u64, s.align as u64);
    }
}

/// Whether the result of `inst` is bound by [`bind_early`]: a record held as leaves is built, read
/// and replaced by moving leaves around, and a stack slot is an `alloca`.
fn is_early(lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    match inst.op {
        Op::Slot => true,
        Op::RecNew => inst.res.is_some_and(|r| !is_mem(lay, f.ty(r))),
        Op::RecGet | Op::RecSet | Op::RecFill => !is_mem(lay, f.ty(inst.args[0])),
        _ => false,
    }
}

/// Binds the result of a pure record operation at naming time, when no instruction is needed:
/// building, reading and replacing a field of a record held as leaves, and a stack slot (its
/// `alloca` goes to the entry block anyway). `None` for any other instruction.
pub(super) fn bind_early(
    b: &mut FnBuilder,
    lay: &Layouts,
    f: &Func,
    vals: &Vals,
    inst: &Inst,
) -> Option<Vec<Val>> {
    if !is_early(lay, f, inst) {
        return None;
    }
    let arg = |i: usize| &vals[&inst.args[i].index()];
    match inst.op {
        Op::Slot => {
            let Imm::Ty(t) = inst.imm else { return None };
            // The runtime may write a whole word to a slot of a smaller type.
            let st = shape(b.types(), lay, t)?;
            let ty = if st.size < 8 { LTy::I64 } else { st.st };
            Some(vec![b.alloca(&ty)])
        }
        Op::RecNew => Some(
            inst.args
                .iter()
                .flat_map(|a| vals[&a.index()].clone())
                .collect(),
        ),
        Op::RecGet => {
            let Imm::Field(_, i) = inst.imm else {
                return None;
            };
            let (at, n) = field_span(lay, f.ty(inst.args[0]), i as usize);
            Some(arg(0)[at..at + n].to_vec())
        }
        _ => {
            let Imm::Field(_, i) = inst.imm else {
                return None;
            };
            let (at, n) = field_span(lay, f.ty(inst.args[0]), i as usize);
            let mut out = arg(0).clone();
            out.splice(at..at + n, arg(1).iter().cloned());
            Some(out)
        }
    }
}

/// Writes a record or `ptr` operation that `bind_early` left to an instruction; each result takes
/// the names reserved for it.
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (lay, f) = (cx.lay, cx.f);
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    let arg = |i: usize| vals[&inst.args[i].index()].clone();
    match inst.op {
        _ if is_early(lay, f, inst) => {}
        Op::Load | Op::Take => {
            let ty = f.ty(inst.res.expect("load result"));
            let p = arg(0)[0].clone();
            if is_mem(lay, ty) {
                let s = shape(b.types(), lay, ty).expect("is_mem checked");
                b.alloca_as(&out[0], &s.st);
                b.copy_bytes(&out[0], &p, s.size as u64, s.align as u64);
            } else {
                let s = shape(b.types(), lay, ty).expect("op_ok checked");
                load_leaves(b, &s, &p, 0, s.leaves.len(), &out);
            }
        }
        Op::Store | Op::Put => {
            let p = arg(0)[0].clone();
            let ty = f.ty(inst.args[1]);
            let s = shape(b.types(), lay, ty).expect("op_ok checked");
            if is_mem(lay, ty) {
                let src = arg(1)[0].clone();
                b.copy_bytes(&p, &src, s.size as u64, s.align as u64);
            } else {
                store_leaves(b, &s, &p, 0, &vals[&inst.args[1].index()]);
            }
        }
        Op::PtrField => {
            let Imm::Field(r, i) = inst.imm else { return };
            let rty = lay
                .m
                .types
                .find(&TyKind::Rec(r))
                .expect("record type interned");
            let (at, _) = field_span(lay, rty, i as usize);
            b.name_next(&out[0]);
            match shape(b.types(), lay, rty) {
                Some(s) => b.field_ptr(&s.st, &arg(0)[0], at),
                None => {
                    let offsets = mem_layout(&lay.leaves(rty)).offsets;
                    b.byte_ptr(&arg(0)[0], offsets[at] as u64)
                }
            };
        }
        Op::RecNew => {
            // A record in memory: each field is stored into a fresh slot.
            let res = inst.res.expect("rec.new result");
            let s = shape(b.types(), lay, f.ty(res)).expect("is_mem checked");
            b.alloca_as(&out[0], &s.st);
            let mut at = 0;
            for a in &inst.args {
                at += write_field(b, lay, f, vals, &s, &out[0], at, *a);
            }
        }
        Op::RecGet => {
            let Imm::Field(_, i) = inst.imm else { return };
            let res = inst.res.expect("rec.get result");
            let rty = f.ty(inst.args[0]);
            let (at, n) = field_span(lay, rty, i as usize);
            let s = shape(b.types(), lay, rty).expect("is_mem checked");
            let rec = arg(0)[0].clone();
            if is_mem(lay, f.ty(res)) {
                // A nested record is the same bytes at an offset; the parent is never written.
                b.name_next(&out[0]);
                b.field_ptr(&s.st, &rec, at);
            } else {
                load_leaves(b, &s, &rec, at, n, &out);
            }
        }
        Op::RecSet | Op::RecFill => {
            let Imm::Field(_, i) = inst.imm else { return };
            let rty = f.ty(inst.args[0]);
            let (at, _) = field_span(lay, rty, i as usize);
            let s = shape(b.types(), lay, rty).expect("is_mem checked");
            let src = arg(0)[0].clone();
            b.alloca_as(&out[0], &s.st);
            b.copy_bytes(&out[0], &src, s.size as u64, s.align as u64);
            write_field(b, lay, f, vals, &s, &out[0], at, inst.args[1]);
        }
        _ => unreachable!("handles lists the ops"),
    }
}

/// Stores MIR value `v` into the record `slot` at leaf `at`; returns the leaves it spans.
#[allow(clippy::too_many_arguments)]
fn write_field(
    b: &mut FnBuilder,
    lay: &Layouts,
    f: &Func,
    vals: &Vals,
    s: &Shape,
    slot: &Val,
    at: usize,
    v: Value,
) -> usize {
    let ty = f.ty(v);
    let n = lay.width(ty);
    if n == 0 {
        return 0;
    }
    if is_mem(lay, ty) {
        let src = vals[&v.index()][0].clone();
        let p = b.field_ptr(&s.st, slot, at);
        let inner = shape(b.types(), lay, ty).expect("is_mem checked");
        b.copy_bytes(&p, &src, inner.size as u64, inner.align as u64);
    } else {
        store_leaves(b, s, slot, at, &vals[&v.index()]);
    }
    n
}

/// Defines the held value of a call result that is a record in memory from the call's own result
/// `r` (a leaf, or a tuple of several), under the reserved name `out[0]`.
pub(super) fn call_result(b: &mut FnBuilder, lay: &Layouts, ty: Ty, r: Val, out: &[Val]) {
    let s = shape(b.types(), lay, ty).expect("is_mem checked");
    let abi = if s.leaves.len() == 1 {
        vec![r]
    } else {
        (0..s.leaves.len()).map(|k| b.extract(&r, k)).collect()
    };
    b.alloca_as(&out[0], &s.st);
    store_leaves(b, &s, &out[0], 0, &abi);
}

/// Defines the held values `out` of a result that came back in the leaf convention, as the call's
/// own result `r` (one leaf, or a tuple of several): a pointer leaf comes back as an address and
/// is converted, every other leaf is the call's result itself under its reserved name.
pub(super) fn name_leaves(b: &mut FnBuilder, r: Val, out: &[Val]) {
    for (k, dst) in out.iter().enumerate() {
        let word = if out.len() == 1 {
            r.clone()
        } else if dst.ty == LTy::Ptr {
            b.extract(&r, k)
        } else {
            b.name_next(dst);
            b.extract(&r, k);
            continue;
        };
        b.name_next(dst);
        b.int_to_ptr(&word);
    }
}

/// The held values of an entry parameter of type `ty` that arrives as the pointer `ptr`. A record
/// in memory is used where it is (it is never written); anything else is loaded into its leaves
/// at the top of the entry block.
pub(super) fn bind_indirect(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    ptr: Val,
    entry: &mut Vec<Entry>,
) -> Vec<Val> {
    if is_mem(lay, ty) {
        return vec![ptr];
    }
    let dsts: Vec<Val> = held_leaves(lay, ty)
        .into_iter()
        .map(|t| b.reserve(t))
        .collect();
    entry.push(Entry::Load {
        ptr,
        dsts: dsts.clone(),
        ty,
    });
    dsts
}

/// A pointer to value `v` of type `ty` to pass by pointer: the slot of a record in memory, or a
/// fresh stack slot holding its leaves.
pub(super) fn spill(b: &mut FnBuilder, lay: &Layouts, ty: Ty, vals: &Vals, v: Value) -> Val {
    if is_mem(lay, ty) {
        return vals[&v.index()][0].clone();
    }
    let leaves = abi_leaves(b, lay, ty, vals, v, true);
    let st = super::aggregate(b.types(), lay, ty);
    let slot = b.alloca(&st);
    store_regs(b, &st, &slot, &leaves);
    slot
}

fn store_regs(b: &mut FnBuilder, st: &LTy, base: &Val, leaves: &[Val]) {
    for (k, v) in leaves.iter().enumerate() {
        let p = b.field_ptr(st, base, k);
        b.store(v, &p, align(&v.ty));
    }
}

/// Writes the result `v` of type `ty` through the hidden result pointer `sret`.
pub(super) fn store_result(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    vals: &Vals,
    v: Value,
    sret: &Val,
) {
    if is_mem(lay, ty) {
        let s = shape(b.types(), lay, ty).expect("is_mem checked");
        b.copy_bytes(sret, &vals[&v.index()][0], s.size as u64, s.align as u64);
        return;
    }
    let leaves = abi_leaves(b, lay, ty, vals, v, true);
    let st = super::aggregate(b.types(), lay, ty);
    store_regs(b, &st, sret, &leaves);
}

/// The slot a call result of type `ty` is written to: the result's own name for a record in
/// memory, else a scratch slot that [`load_result`] reads back.
pub(super) fn result_slot(b: &mut FnBuilder, lay: &Layouts, ty: Ty, out: &[Val]) -> Val {
    if is_mem(lay, ty) {
        let s = shape(b.types(), lay, ty).expect("is_mem checked");
        b.alloca_as(&out[0], &s.st);
        return out[0].clone();
    }
    let st = super::aggregate(b.types(), lay, ty);
    b.alloca(&st)
}

/// Reads the result of type `ty` back from the slot a call wrote it to, into the names `out`.
pub(super) fn load_result(b: &mut FnBuilder, lay: &Layouts, ty: Ty, slot: &Val, out: &[Val]) {
    if is_mem(lay, ty) {
        return;
    }
    let st = super::aggregate(b.types(), lay, ty);
    for (k, dst) in out.iter().enumerate() {
        let p = b.field_ptr(&st, slot, k);
        b.name_next(dst);
        b.load(&dst.ty, &p, align(&dst.ty));
    }
}

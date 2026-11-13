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

use super::{Area, Cx, Vals, held_leaves, mem_leaves};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Func, Imm, Inst, Op, Target, Value};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    splits,
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
    /// Type each leaf is held as in a register: the memory type, or `i1` for a boolean.
    pub held: Vec<LTy>,
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
    Some((mem_leaves(lay, ty), mem_layout(&raw)))
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
        held: held_leaves(lay, ty),
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

/// The indirect record `ty` (the library's `Error`): its value is one pointer to a heap block.
fn indirect(lay: &Layouts, ty: Ty) -> Option<ms_mir::types::RecId> {
    match lay.m.types.kind(ty) {
        TyKind::Rec(r) if lay.m.records[r.index()].indirect => Some(*r),
        _ => None,
    }
}

/// Whether the block of indirect record `r` is made of plain leaves, none of them a record in
/// memory (whose offsets inside the flat block would differ from its own).
fn block_ok(lay: &Layouts, r: ms_mir::types::RecId) -> bool {
    lay.rec_block(r)
        .iter()
        .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
        && lay.m.records[r.index()]
            .fields
            .iter()
            .all(|f| !is_mem(lay, f.1))
}

/// The memory shape of the block behind indirect record `r`: the leaves of its fields in order,
/// with a map or set field as the one nullable pointer to its header.
fn block_shape(types: &Types, lay: &Layouts, r: ms_mir::types::RecId) -> Shape {
    let (mut leaves, mut held) = (Vec::new(), Vec::new());
    for f in &lay.m.records[r.index()].fields {
        if lay.rec_field_boxed(f.1) {
            leaves.push(LTy::Ptr);
            held.push(LTy::Ptr);
        } else {
            leaves.extend(mem_leaves(lay, f.1));
            held.extend(held_leaves(lay, f.1));
        }
    }
    let mem = mem_layout(&lay.rec_block(r));
    let name = format!("ms.rec.{}.block", lay.m.records[r.index()].name);
    Shape {
        st: types.named(&name, leaves.clone()),
        leaves,
        held,
        size: mem.size,
        align: mem.align,
    }
}

/// Block leaf index, leaf count and whether the field holds a header pointer, per field of `r`.
fn block_spans(lay: &Layouts, r: ms_mir::types::RecId) -> Vec<(usize, usize, bool)> {
    let mut at = 0;
    lay.m.records[r.index()]
        .fields
        .iter()
        .map(|f| {
            let boxed = lay.rec_field_boxed(f.1);
            let n = if boxed { 1 } else { lay.width(f.1) };
            at += n;
            (at - n, n, boxed)
        })
        .collect()
}

/// Whether field `i` of `r` is an indirect record's boxed collection.
fn field_boxed(lay: &Layouts, r: ms_mir::types::RecId, i: u32) -> bool {
    lay.m.records[r.index()].indirect
        && lay.rec_field_boxed(lay.m.records[r.index()].fields[i as usize].1)
}

/// How many times `inst` splits its block: reading, creating or addressing a boxed collection
/// field branches on the null header.
fn splits(lay: &Layouts, f: &Func, i: &Inst, _: bool) -> usize {
    match (i.op, i.imm) {
        (Op::RecNew, _) => i
            .res
            .and_then(|r| indirect(lay, f.ty(r)))
            .map_or(0, |r| block_spans(lay, r).iter().filter(|s| s.2).count()),
        (Op::RecGet | Op::PtrField, Imm::Field(r, k)) => usize::from(field_boxed(lay, r, k)),
        _ => 0,
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
        || indirect(lay, ty).is_some_and(|r| block_ok(lay, r))
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
        (Op::PtrField | Op::RecGet, Imm::Field(..)) => true,
        (Op::RecSet | Op::RecFill, Imm::Field(r, _)) => !lay.m.records[r.index()].indirect,
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

/// The leaves of `v` as they cross a call: a record in memory loaded, a boolean as an `i8`, and
/// each pointer as itself in the native convention (`native`) or as its address (`i64`) in the
/// leaf convention.
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
    leaves
        .into_iter()
        .map(|l| match l.ty {
            LTy::I1 => b.zext(&l, LTy::I8),
            LTy::Ptr if !native => b.ptr_to_int(&l),
            _ => l,
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
            match named.get(k - at) {
                Some(v) => load_into(b, v, &s.leaves[k], &p),
                None if s.held[k] == LTy::I1 => {
                    let w = b.load(&s.leaves[k], &p, 1);
                    b.trunc(&w, LTy::I1)
                }
                None => b.load(&s.leaves[k], &p, align(&s.leaves[k])),
            }
        })
        .collect()
}

fn store_leaves(b: &mut FnBuilder, s: &Shape, base: &Val, at: usize, leaves: &[Val]) {
    for (k, v) in leaves.iter().enumerate() {
        let p = b.field_ptr(&s.st, base, at + k);
        store_leaf(b, v, &p);
    }
}

/// Stores a leaf, a boolean as the byte it is in memory.
fn store_leaf(b: &mut FnBuilder, v: &Val, p: &Val) {
    let v = if v.ty == LTy::I1 {
        b.zext(v, LTy::I8)
    } else {
        v.clone()
    };
    b.store(&v, p, align(&v.ty));
}

/// Loads the leaf of memory type `mem` at `p` as the reserved held value `dst`: a boolean byte is
/// narrowed to the `i1` it is held as.
fn load_into(b: &mut FnBuilder, dst: &Val, mem: &LTy, p: &Val) -> Val {
    if dst.ty == LTy::I1 && *mem == LTy::I8 {
        let w = b.load(mem, p, 1);
        b.name_next(dst);
        b.trunc(&w, LTy::I1)
    } else {
        b.name_next(dst);
        b.load(mem, p, align(mem))
    }
}

/// A leaf's alignment in memory: its size.
fn align(t: &LTy) -> u64 {
    if *t == LTy::I8 { 1 } else { 8 }
}

/// What the entry block must do before anything else: define the values of parameters that do not
/// arrive as they are used.
pub(super) enum Entry {
    /// A leaf that arrives as another type than it is held as (an address for a pointer, a byte
    /// for a boolean) is converted.
    Conv { held: Val, abi: Val },
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
            if (t == LTy::Ptr && a.ty == LTy::I64) || (t == LTy::I1 && a.ty == LTy::I8) {
                let held = b.reserve(t);
                entry.push(Entry::Conv {
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
            Entry::Conv { held, abi } => {
                b.name_next(&held);
                if held.ty == LTy::I1 {
                    b.trunc(&abi, LTy::I1);
                } else {
                    b.int_to_ptr(&abi);
                }
            }
            Entry::Mem { slot, abi, ty } => {
                let s = shape(b.types(), lay, ty).expect("is_mem checked");
                store_leaves(b, &s, &slot, 0, &abi);
            }
            Entry::Load { ptr, dsts, ty } => {
                let st = super::aggregate(b.types(), lay, ty);
                let mem = mem_leaves(lay, ty);
                for (k, dst) in dsts.iter().enumerate() {
                    let p = b.field_ptr(&st, &ptr, k);
                    load_into(b, dst, &mem[k], &p);
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
        Op::RecNew => inst
            .res
            .is_some_and(|r| !is_mem(lay, f.ty(r)) && indirect(lay, f.ty(r)).is_none()),
        Op::RecGet | Op::RecSet | Op::RecFill => {
            let t = f.ty(inst.args[0]);
            !is_mem(lay, t) && indirect(lay, t).is_none()
        }
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
            if let Some(r) = indirect(lay, rty) {
                ptr_field(cx, b, r, i as usize, &arg(0)[0], &out[0]);
                return;
            }
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
        Op::RecNew if indirect(lay, f.ty(inst.res.expect("rec.new result"))).is_some() => {
            let r = indirect(lay, f.ty(inst.res.expect("rec.new result"))).expect("checked");
            rec_new(cx, b, r, inst, vals, &out[0]);
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
        Op::RecGet if indirect(lay, f.ty(inst.args[0])).is_some() => {
            let Imm::Field(r, i) = inst.imm else { return };
            rec_get(cx, b, r, i as usize, &arg(0)[0], &out);
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

const NULL: fn() -> Val = || Val::new("null", LTy::Ptr);

/// Declares the runtime's allocator and `free` for a block.
fn declare_heap(cx: &mut Cx) {
    cx.decls.push((
        "msrt_alloc".into(),
        "declare noalias align 16 ptr @\"msrt_alloc\"(i64)".into(),
    ));
    cx.decls.push((
        "msrt_free".into(),
        "declare void @\"msrt_free\"(i64)".into(),
    ));
}

/// A fresh heap block of `size` bytes, named `dst` when given.
fn alloc(b: &mut FnBuilder, size: u32, dst: Option<&Val>) -> Val {
    if let Some(d) = dst {
        b.name_next(d);
    }
    b.call(
        &LTy::Ptr,
        "noalias align 16 ",
        "msrt_alloc",
        &[(Val::int(i64::from(size.max(1))), "")],
    )
    .expect("a block")
}

/// The label the next join block of the current MIR block gets, and the labels of the code that
/// precedes it; counts the split.
fn next_split(cx: &mut Cx, tag: &str) -> (String, String, String) {
    let (bb, split) = (cx.block, cx.split);
    cx.split += 1;
    (
        super::block_label(bb, split),
        format!("{tag}{bb}_{split}"),
        super::block_label(bb, split + 1),
    )
}

/// `rec.new` of an indirect record: one heap block with the field leaves stored at their offsets;
/// a map or set that is not the all-zero empty value gets a header block of its own, else the
/// field is null.
fn rec_new(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::RecId,
    inst: &Inst,
    vals: &Vals,
    out: &Val,
) {
    declare_heap(cx);
    let lay = cx.lay;
    let s = block_shape(b.types(), lay, r);
    let block = alloc(b, s.size, Some(out));
    let spans = block_spans(lay, r);
    for (a, (at, n, boxed)) in inst.args.iter().zip(spans) {
        let words = &vals[&a.index()];
        if boxed {
            let header = header_store(cx, b, words);
            let p = b.field_ptr(&s.st, &block, at);
            b.store(&header, &p, 8);
        } else {
            store_leaves(b, &s, &block, at, &words[..n]);
        }
    }
}

/// A header block holding `words`, or null when they are the all-zero empty collection (a stamped
/// empty one, with its descriptor word set, keeps its block).
fn header_store(cx: &mut Cx, b: &mut FnBuilder, words: &[Val]) -> Val {
    let as_int = |b: &mut FnBuilder, w: &Val| {
        if w.ty == LTy::Ptr {
            b.ptr_to_int(w)
        } else {
            w.clone()
        }
    };
    let (first, last) = (as_int(b, &words[0]), as_int(b, &words[words.len() - 1]));
    let used = b.bin(Bin::Or, &first, &last);
    let used = b.icmp("ne", &used, &Val::int(0));
    let (head, some, join) = next_split(cx, "h");
    b.cond_br(&used, &some, &join);
    b.label(&some);
    let bp = alloc(b, ms_rt_abi::MAP_SIZE as u32, None);
    for (k, w) in words.iter().enumerate() {
        let at = b.elem_ptr(&LTy::I64, &bp, &Val::int(k as i64));
        b.store(w, &at, 8);
    }
    b.br(&join);
    b.label(&join);
    let out = b.reserve(LTy::Ptr);
    b.phi(&out, &[(NULL(), head), (bp, some)]);
    out
}

/// `rec.get` of an indirect record: the field's leaves loaded from the block; a map or set loads
/// its header through the pointer, or is the all-zero empty value when that is null.
fn rec_get(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::RecId,
    i: usize,
    rec: &Val,
    out: &[Val],
) {
    let lay = cx.lay;
    let s = block_shape(b.types(), lay, r);
    let (at, n, boxed) = block_spans(lay, r)[i];
    if !boxed {
        load_leaves(b, &s, rec, at, n, out);
        return;
    }
    let p = b.field_ptr(&s.st, rec, at);
    let bp = b.load(&LTy::Ptr, &p, 8);
    let some_header = b.icmp("ne", &bp, &NULL());
    let (head, some, join) = next_split(cx, "g");
    b.cond_br(&some_header, &some, &join);
    b.label(&some);
    let loaded: Vec<Val> = out
        .iter()
        .enumerate()
        .map(|(k, dst)| {
            let at = b.elem_ptr(&LTy::I64, &bp, &Val::int(k as i64));
            b.load(&dst.ty, &at, 8)
        })
        .collect();
    b.br(&join);
    b.label(&join);
    for (dst, v) in out.iter().zip(loaded) {
        let zero = if dst.ty == LTy::Ptr {
            NULL()
        } else {
            Val::int(0)
        };
        b.phi(dst, &[(zero, head.clone()), (v, some.clone())]);
    }
}

/// `ptr.field` of an indirect record: the argument addresses the record's pointer; the result is
/// the address of the field in the block, or for a map or set the header block, created empty when
/// the field is null.
fn ptr_field(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::RecId,
    i: usize,
    at: &Val,
    out: &Val,
) {
    let lay = cx.lay;
    let s = block_shape(b.types(), lay, r);
    let (k, _, boxed) = block_spans(lay, r)[i];
    let block = b.load(&LTy::Ptr, at, 8);
    if !boxed {
        b.name_next(out);
        b.field_ptr(&s.st, &block, k);
        return;
    }
    declare_heap(cx);
    let slot = b.field_ptr(&s.st, &block, k);
    let have = b.load(&LTy::Ptr, &slot, 8);
    let present = b.icmp("ne", &have, &NULL());
    let (head, make, join) = next_split(cx, "m");
    b.cond_br(&present, &join, &make);
    b.label(&make);
    let bp = alloc(b, ms_rt_abi::MAP_SIZE as u32, None);
    for w in 0..ms_rt_abi::MAP_SIZE / 8 {
        let p = b.elem_ptr(&LTy::I64, &bp, &Val::int(w as i64));
        b.store(&Val::int(0), &p, 8);
    }
    b.store(&bp, &slot, 8);
    b.br(&join);
    b.label(&join);
    b.phi(out, &[(have, head), (bp, make)]);
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
/// own result `r` (one leaf, or a tuple of several): a boolean comes back as a byte and a pointer
/// (in the leaf convention) as an address, and each is converted; every other leaf is the call's
/// result itself under its reserved name.
pub(super) fn name_leaves(b: &mut FnBuilder, r: Val, out: &[Val]) {
    for (k, dst) in out.iter().enumerate() {
        let converted = matches!(dst.ty, LTy::I1 | LTy::Ptr);
        let word = if out.len() == 1 {
            r.clone()
        } else if converted {
            b.extract(&r, k)
        } else {
            b.name_next(dst);
            b.extract(&r, k);
            continue;
        };
        b.name_next(dst);
        if dst.ty == LTy::I1 {
            b.trunc(&word, LTy::I1);
        } else {
            b.int_to_ptr(&word);
        }
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
        store_leaf(b, v, &p);
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
    let mem = mem_leaves(lay, ty);
    for (k, dst) in out.iter().enumerate() {
        let p = b.field_ptr(&st, slot, k);
        load_into(b, dst, &mem[k], &p);
    }
}

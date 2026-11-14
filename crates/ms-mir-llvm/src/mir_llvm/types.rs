//! Types, raw memory and `ptr` values in the direct emitter.
//!
//! A type of at most [`MEM_LEAVES`] leaves is a list of register values like any other value, so
//! `type.new`, `type.get` and `type.set` only move leaves around and cost nothing. A larger type is
//! kept in memory instead: its value is a `ptr` to one immutable `alloca` of a literal struct with
//! the type's leaves as fields (the offsets are those of `layout::mem_layout`, so they match the
//! runtime and the Cranelift object). A copy is one `memcpy`, a field read an offset and one
//! aligned `load`, and LLVM's `sroa` and `memcpyopt` turn that back into registers where it pays
//! and drop the fields nobody reads. The flat leaf list exists only where the shared calling
//! convention asks for it: a call, a return and the entry of a function.
//!
//! A block parameter of such a type has a slot of its own that each incoming edge copies into,
//! so a loop that carries a type does not carry a phi per leaf.
//!
//! Values of type `ptr` are LLVM `ptr` inside a function and `i64` across a call. A type that
//! holds a `ptr` is not handled (its leaf is an integer here); the function falls back.

use super::{Area, Cx, Vals, held_leaves, mem_leaves, narrow_leaves};
use crate::glue_llvm::{OwnKind, own_kind};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Func, Imm, Inst, Op, Target, Value};
use ms_mir::layout::{Layouts, Leaf, mem_layout};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    splits,
    inst_ok: |_, lay, f, i| op_ok(lay, f, i),
    emit,
    ..Area::NONE
};

/// Types with more leaves than this live in memory.
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

/// The memory type of the leaves of `ty`: a struct named after a type, string or list, else a
/// literal one; `None` when it has none or a leaf differs in registers and in memory.
fn shape_leaves(lay: &Layouts, ty: Ty) -> Option<(Vec<LTy>, ms_mir::layout::MemLayout)> {
    let raw = lay.leaves(ty);
    if raw.is_empty()
        || raw
            .iter()
            .any(|l| !matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8 | Leaf::F32) && !is_narrow(*l))
    {
        return None;
    }
    Some((mem_leaves(lay, ty), mem_layout(&raw)))
}

/// A narrow integer leaf: an `i64` register, 1, 2 or 4 bytes in memory.
pub(super) fn is_narrow(l: Leaf) -> bool {
    matches!(
        l,
        Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32
    )
}

/// Whether `ty` has no leaves (`Unit`): moving it through memory is nothing.
fn empty(lay: &Layouts, ty: Ty) -> bool {
    lay.leaves(ty).is_empty()
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

fn named_type(lay: &Layouts, ty: Ty) -> Option<ms_mir::types::TypeId> {
    match lay.m.types.kind(ty) {
        TyKind::Type(r) if !lay.m.type_defs[r.index()].indirect => Some(*r),
        _ => None,
    }
}

/// The indirect type `ty` (the library's `Error`): its value is one pointer to a heap block.
fn indirect(lay: &Layouts, ty: Ty) -> Option<ms_mir::types::TypeId> {
    match lay.m.types.kind(ty) {
        TyKind::Type(r) if lay.m.type_defs[r.index()].indirect => Some(*r),
        _ => None,
    }
}

/// Whether the block of indirect type `r` is made of plain leaves, none of them a type in
/// memory (whose offsets inside the flat block would differ from its own).
fn block_ok(lay: &Layouts, r: ms_mir::types::TypeId) -> bool {
    lay.type_block(r)
        .iter()
        .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8 | Leaf::F32) || is_narrow(*l))
        && lay.m.type_defs[r.index()]
            .fields
            .iter()
            .all(|f| !is_mem(lay, f.1))
}

/// The memory shape of the block behind indirect type `r`: the leaves of its fields in order,
/// with a map or set field as the one nullable pointer to its header.
fn block_shape(types: &Types, lay: &Layouts, r: ms_mir::types::TypeId) -> Shape {
    let (mut leaves, mut held) = (Vec::new(), Vec::new());
    for f in &lay.m.type_defs[r.index()].fields {
        if lay.type_field_boxed(f.1) {
            leaves.push(LTy::Ptr);
            held.push(LTy::Ptr);
        } else {
            leaves.extend(mem_leaves(lay, f.1));
            held.extend(held_leaves(lay, f.1));
        }
    }
    let mem = mem_layout(&lay.type_block(r));
    let name = format!("ms.type.{}.block", lay.m.type_defs[r.index()].name);
    Shape {
        st: types.named(&name, leaves.clone()),
        leaves,
        held,
        size: mem.size,
        align: mem.align,
    }
}

/// Block leaf index, leaf count and whether the field holds a header pointer, per field of `r`.
fn block_spans(lay: &Layouts, r: ms_mir::types::TypeId) -> Vec<(usize, usize, bool)> {
    let mut at = 0;
    lay.m.type_defs[r.index()]
        .fields
        .iter()
        .map(|f| {
            let boxed = lay.type_field_boxed(f.1);
            let n = if boxed { 1 } else { lay.width(f.1) };
            at += n;
            (at - n, n, boxed)
        })
        .collect()
}

/// Whether field `i` of `r` is an indirect type's boxed collection.
fn field_boxed(lay: &Layouts, r: ms_mir::types::TypeId, i: u32) -> bool {
    lay.m.type_defs[r.index()].indirect
        && lay.type_field_boxed(lay.m.type_defs[r.index()].fields[i as usize].1)
}

/// The fields of the type `ty` that `type.release` drops: those the mask does not move out and
/// that own something, each with its type and leaf index and count.
pub(super) fn released(
    lay: &Layouts,
    ty: Ty,
    mask: u32,
) -> impl Iterator<Item = (Ty, usize, usize)> {
    let r = named_type(lay, ty).expect("a type that is not indirect");
    let mut at = 0;
    lay.m.type_defs[r.index()]
        .fields
        .iter()
        .enumerate()
        .filter_map(move |(k, f)| {
            let w = lay.width(f.1);
            at += w;
            (mask >> k & 1 == 0 && lay.m.needs_drop(f.1)).then_some((f.1, at - w, w))
        })
}

/// The fields of the indirect type `r` that `type.release` visits: a boxed collection always (its
/// header block is freed), any other when the mask does not move it out and it owns something;
/// each with its field index, so that `block_spans` locates it, and whether it is boxed.
fn block_released(lay: &Layouts, r: ms_mir::types::TypeId, mask: u32) -> Vec<(Ty, usize, bool)> {
    let spans = block_spans(lay, r);
    lay.m.type_defs[r.index()]
        .fields
        .iter()
        .enumerate()
        .filter(|(k, f)| spans[*k].2 || (mask >> k & 1 == 0 && lay.m.needs_drop(f.1)))
        .map(|(k, f)| (f.1, k, spans[k].2))
        .collect()
}

/// The types of the fields `type.release` of a type of type `ty` drops through glue.
pub(super) fn release_types(lay: &Layouts, ty: Ty, mask: u32) -> Vec<Ty> {
    match indirect(lay, ty) {
        Some(r) => block_released(lay, r, mask)
            .into_iter()
            .filter(|(fty, k, _)| mask >> k & 1 == 0 && lay.m.needs_drop(*fty))
            .map(|(fty, ..)| fty)
            .collect(),
        None => released(lay, ty, mask).map(|(t, ..)| t).collect(),
    }
}

/// `type.release` of an indirect type: drops the fields the mask keeps, frees the header block of
/// each collection field and then the type's block.
fn release_block(cx: &mut Cx, b: &mut FnBuilder, r: ms_mir::types::TypeId, mask: u32, p: &Val) {
    let lay = cx.lay;
    let s = block_shape(b.types(), lay, r);
    let spans = block_spans(lay, r);
    declare_heap(cx);
    for (fty, k, boxed) in block_released(lay, r, mask) {
        let (at, n, _) = spans[k];
        let kept = mask >> k & 1 == 0 && lay.m.needs_drop(fty);
        if !boxed {
            let leaves = load_leaves(b, &s, p, at, n, &[]);
            super::glue::drop_held(cx, fty, leaves, b);
            continue;
        }
        let slot = b.field_ptr(&s.st, p, at);
        let bp = b.load(&LTy::Ptr, &slot, 8);
        let some = b.icmp("ne", &bp, &NULL());
        let (_, then, join) = next_split(cx, "r");
        b.cond_br(&some, &then, &join);
        b.label(&then);
        if kept {
            let words = (0..lay.width(fty))
                .map(|w| {
                    let at = b.elem_ptr(&LTy::I64, &bp, &Val::int(w as i64));
                    b.load(&LTy::I64, &at, 8)
                })
                .collect();
            super::glue::drop_held(cx, fty, words, b);
        }
        let word = b.ptr_to_int(&bp);
        b.call(&LTy::Void, "", "msrt_free", &[(word, "")]);
        b.br(&join);
        b.label(&join);
    }
    let word = b.ptr_to_int(p);
    b.call(&LTy::Void, "", "msrt_free", &[(word, "")]);
}

/// How many times `inst` splits its block: reading, creating or addressing a boxed collection
/// field branches on the null header.
fn splits(lay: &Layouts, f: &Func, i: &Inst, _: bool) -> usize {
    match (i.op, i.imm) {
        (Op::TypeNew, _) => i
            .res
            .and_then(|r| indirect(lay, f.ty(r)))
            .map_or(0, |r| block_spans(lay, r).iter().filter(|s| s.2).count()),
        (Op::TypeGet | Op::PtrField, Imm::Field(r, k)) => usize::from(field_boxed(lay, r, k)),
        (Op::TypeSet | Op::TypeFill, Imm::Field(r, k))
            if indirect(lay, f.ty(i.args[0])).is_some() =>
        {
            let fty = lay.m.type_defs[r.index()].fields[k as usize].1;
            let drops = i.op == Op::TypeSet && own_kind(lay, fty) == OwnKind::Str;
            if field_boxed(lay, r, k) {
                2
            } else {
                usize::from(drops)
            }
        }
        (Op::TypeRelease, Imm::TypeMask(_, mask)) => match indirect(lay, f.ty(i.args[0])) {
            // Each boxed collection field is tested for its header; a string field is a check.
            Some(r) => block_released(lay, r, mask)
                .iter()
                .map(|(fty, _, boxed)| usize::from(*boxed || own_kind(lay, *fty) == OwnKind::Str))
                .sum(),
            None => released(lay, f.ty(i.args[0]), mask)
                .filter(|(fty, ..)| own_kind(lay, *fty) == OwnKind::Str)
                .count(),
        },
        _ => 0,
    }
}

/// Whether a value of `ty` is held as a pointer to memory.
pub(super) fn is_mem(lay: &Layouts, ty: Ty) -> bool {
    named_type(lay, ty).is_some() && lay.width(ty) > MEM_LEAVES
}

/// Whether this module handles values of `ty`: `ptr`, and types that are either small or have a
/// memory shape.
pub(super) fn ty_ok(lay: &Layouts, ty: Ty) -> bool {
    ty == Ty::PTR
        || indirect(lay, ty).is_some_and(|r| block_ok(lay, r))
        || (named_type(lay, ty).is_some() && (lay.width(ty) <= MEM_LEAVES || shape_ok(lay, ty)))
}

/// The ops this module emits.
pub(super) fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::TypeNew
            | Op::TypeGet
            | Op::TypeSet
            | Op::TypeFill
            | Op::TypeRelease
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
        // A slot is bytes: any type has a size.
        (Op::Slot, Imm::Ty(_)) => true,
        (Op::Load | Op::Take, Imm::Ty(t)) => {
            (mem_ty(t) || empty(lay, t)) && i.res.is_some_and(|r| f.ty(r) == t)
        }
        (Op::Store | Op::Put, _) => mem_ty(f.ty(i.args[1])) || empty(lay, f.ty(i.args[1])),
        (Op::PtrField | Op::TypeGet, Imm::Field(..)) => true,
        (Op::TypeSet | Op::TypeFill, Imm::Field(r, _)) => {
            !lay.m.type_defs[r.index()].indirect || block_ok(lay, r)
        }
        (Op::TypeNew, _) => true,
        (
            Op::Slot
            | Op::Load
            | Op::Take
            | Op::PtrField
            | Op::TypeGet
            | Op::TypeSet
            | Op::TypeFill,
            _,
        ) => false,
        _ => true,
    }
}

/// The values a MIR value of type `ty` is held as: its leaves, with `ptr` as `ptr`; a type in
/// memory is one `ptr`.
pub(super) fn held(lay: &Layouts, ty: Ty) -> Vec<LTy> {
    if is_mem(lay, ty) {
        return vec![LTy::Ptr];
    }
    held_leaves(lay, ty)
}

/// The values of a block parameter: its own reserved names, or for a type in memory a slot that
/// each incoming edge copies into.
pub(super) fn block_param(b: &mut FnBuilder, lay: &Layouts, ty: Ty) -> Vec<Val> {
    if is_mem(lay, ty) {
        let st = shape(b.types(), lay, ty).expect("is_mem checked").st;
        return vec![b.alloca(&st)];
    }
    reserve(b, lay, ty)
}

/// Reserves the names a result of type `ty` is held under; a type in memory is one `ptr`, the
/// address of its slot.
pub(super) fn reserve(b: &mut FnBuilder, lay: &Layouts, ty: Ty) -> Vec<Val> {
    held(lay, ty).into_iter().map(|t| b.reserve(t)).collect()
}

/// Loads the leaves of the type of type `ty` in memory at `base` into the reserved `named`
/// values, one per leaf.
pub(super) fn load_into_leaves(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    base: &Val,
    named: &[Val],
) {
    let s = shape(b.types(), lay, ty).expect("is_mem checked");
    load_leaves(b, &s, base, 0, s.leaves.len(), named);
}

/// Defines the reserved pointer `dst` as a new slot for a type of type `ty` in memory and
/// stores its `leaves` there.
pub(super) fn store_into_slot(b: &mut FnBuilder, lay: &Layouts, ty: Ty, dst: &Val, leaves: &[Val]) {
    let s = shape(b.types(), lay, ty).expect("is_mem checked");
    b.alloca_as(dst, &s.st);
    store_regs(b, lay, ty, &s.st, dst, leaves);
}

/// Leaf index and count of field `i` of type `rty`.
fn field_span(lay: &Layouts, rty: Ty, i: usize) -> (usize, usize) {
    let r = named_type(lay, rty).expect("a type");
    let fields = &lay.m.type_defs[r.index()].fields;
    let at = fields[..i].iter().map(|f| lay.width(f.1)).sum();
    (at, lay.width(fields[i].1))
}

/// The convention the leaves of a call cross in.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum Abi {
    /// The leaf convention Cranelift shares: each pointer an `i64`, each sized integer an `i64`
    /// and each `Float32` a `double`.
    Leaf,
    /// The C convention of a runtime function: pointers stay `ptr`, but sized integers and
    /// `Float32` are still widened.
    Rt,
    /// Directly emitted functions (`abi_llvm::Signature`): every leaf is the type it is held as.
    Native,
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
    abi: Abi,
) -> Vec<Val> {
    abi_leaves_of(b, lay, ty, &vals[&v.index()], abi)
}

/// [`abi_leaves`] of the held values `own` of a `ty`.
pub(super) fn abi_leaves_of(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    own: &[Val],
    abi: Abi,
) -> Vec<Val> {
    let leaves = if is_mem(lay, ty) {
        let s = shape(b.types(), lay, ty).expect("is_mem checked");
        load_leaves(b, &s, &own[0], 0, s.leaves.len(), &[])
    } else {
        own.to_vec()
    };
    let narrow = narrow_leaves(lay, ty);
    leaves
        .into_iter()
        .enumerate()
        .map(|(k, l)| match l.ty {
            LTy::Ptr if abi == Abi::Leaf => b.ptr_to_int(&l),
            LTy::I1 => b.zext(&l, LTy::I8),
            _ if abi == Abi::Native => l,
            _ => to_abi(b, &l, narrow[k]),
        })
        .collect()
}

/// Loads leaves `at..at + n` of the type at `base`; each takes the matching name of `named`
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
            let p = b.leaf_ptr(&s.st, base, k);
            match named.get(k - at) {
                Some(v) => load_into(b, v, &s.leaves[k], &p),
                None => {
                    let w = b.load(&s.leaves[k], &p, align(&s.leaves[k]));
                    widen(b, &w, &s.held[k])
                }
            }
        })
        .collect()
}

fn store_leaves(b: &mut FnBuilder, s: &Shape, base: &Val, at: usize, leaves: &[Val]) {
    for (k, v) in leaves.iter().enumerate() {
        let p = b.leaf_ptr(&s.st, base, at + k);
        store_leaf(b, v, &s.leaves[at + k], &p);
    }
}

/// Stores a leaf in its memory type `mem`: a boolean as the byte it is in memory, a narrow
/// integer truncated to its width.
pub(super) fn store_leaf(b: &mut FnBuilder, v: &Val, mem: &LTy, p: &Val) {
    let v = to_mem(b, v, mem);
    b.store(&v, p, align(mem));
}

/// A value as its memory type `mem`: an `i1` as the byte, an `i64` register of the leaf
/// convention as a narrow integer, a `double` of it as a `float`, and a pointer or word in a slot
/// of the other kind.
pub(super) fn to_mem(b: &mut FnBuilder, v: &Val, mem: &LTy) -> Val {
    match (&v.ty, mem) {
        (LTy::I1, _) => b.zext(v, LTy::I8),
        (LTy::I64, LTy::I8 | LTy::I16 | LTy::I32) => b.trunc(v, mem.clone()),
        (LTy::F64, LTy::F32) => b.fptrunc(v),
        (LTy::I64, LTy::Ptr) => b.inttoptr(v),
        (LTy::Ptr, LTy::I64) => b.ptrtoint(v),
        _ => v.clone(),
    }
}

/// Loads the leaf of memory type `mem` at `p` as the reserved held value `dst`: a boolean byte is
/// narrowed to the `i1` it is held as.
fn load_into(b: &mut FnBuilder, dst: &Val, mem: &LTy, p: &Val) -> Val {
    if dst.ty == *mem {
        b.name_next(dst);
        return b.load(mem, p, align(mem));
    }
    let w = b.load(mem, p, align(mem));
    b.name_next(dst);
    widen(b, &w, &dst.ty)
}

/// A loaded memory value as the type it is held as: `i1` for a boolean byte; anything else is
/// already held as it is stored.
pub(super) fn widen(b: &mut FnBuilder, w: &Val, held: &LTy) -> Val {
    match (&w.ty, held) {
        (LTy::I8, LTy::I1) => b.trunc(w, LTy::I1),
        (LTy::Ptr, LTy::I64) => b.ptrtoint(w),
        (LTy::I64, LTy::Ptr) => b.inttoptr(w),
        _ => w.clone(),
    }
}

/// A held leaf as it crosses a call in the leaf convention: a boolean as a byte and a narrow
/// integer (`narrow` says whether the leaf is one, and signed) extended to the `i64` register.
pub(super) fn to_abi(b: &mut FnBuilder, v: &Val, narrow: Option<bool>) -> Val {
    match (&v.ty, narrow) {
        (LTy::I1, _) => b.zext(v, LTy::I8),
        (LTy::F32, _) => b.fpext(v),
        (LTy::I64, _) => v.clone(),
        (_, Some(true)) => b.sext(v, LTy::I64),
        (_, Some(false)) => b.zext(v, LTy::I64),
        _ => v.clone(),
    }
}

/// Whether a leaf held as `held` arrives in the leaf convention as another type, which the entry
/// block converts: a pointer as an address, a boolean as a byte, a narrow integer as an `i64`.
fn arrives_converted(held: &LTy, abi: &LTy) -> bool {
    matches!(
        (held, abi),
        (LTy::Ptr, LTy::I64)
            | (LTy::I1, LTy::I8)
            | (LTy::I8 | LTy::I16 | LTy::I32, LTy::I64)
            | (LTy::F32, LTy::F64)
    )
}

/// A leaf's alignment in memory: its size.
fn align(t: &LTy) -> u64 {
    match t {
        LTy::I1 | LTy::I8 => 1,
        LTy::I16 => 2,
        LTy::I32 | LTy::F32 => 4,
        _ => 8,
    }
}

/// What the entry block must do before anything else: define the values of parameters that do not
/// arrive as they are used.
pub(super) enum Entry {
    /// A leaf that arrives as another type than it is held as (an address for a pointer, a byte
    /// for a boolean) is converted.
    Conv { held: Val, abi: Val },
    /// A type in memory arrives as leaves and is stored into its slot.
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
            if arrives_converted(&t, &a.ty) {
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
                from_abi(b, &abi, &held.ty);
            }
            Entry::Mem { slot, abi, ty } => {
                let s = shape(b.types(), lay, ty).expect("is_mem checked");
                store_leaves(b, &s, &slot, 0, &abi);
            }
            Entry::Load { ptr, dsts, ty } => {
                let st = super::aggregate(b.types(), lay, ty);
                let mem = mem_leaves(lay, ty);
                for (k, dst) in dsts.iter().enumerate() {
                    let p = b.leaf_ptr(&st, &ptr, k);
                    load_into(b, dst, &mem[k], &p);
                }
            }
        }
    }
}

/// Whether following `t` copies a type into the slots of the target's parameters.
pub(super) fn has_copies(lay: &Layouts, f: &Func, t: &Target) -> bool {
    f.blocks[t.block.index()]
        .params
        .iter()
        .any(|p| is_mem(lay, f.ty(p.value)))
}

/// Copies the type arguments of `t` into the slots of the target's parameters. An argument that
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

/// Whether the result of `inst` is bound by [`bind_early`]: a type held as leaves is built, read
/// and replaced by moving leaves around, and a stack slot is an `alloca`.
fn is_early(lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    match inst.op {
        Op::Slot => true,
        Op::TypeNew => inst
            .res
            .is_some_and(|r| !is_mem(lay, f.ty(r)) && indirect(lay, f.ty(r)).is_none()),
        Op::TypeGet | Op::TypeSet | Op::TypeFill => {
            let t = f.ty(inst.args[0]);
            !is_mem(lay, t) && indirect(lay, t).is_none()
        }
        _ => false,
    }
}

/// Binds the result of a pure type operation at naming time, when no instruction is needed:
/// building, reading and replacing a field of a type held as leaves, and a stack slot (its
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
            let words = lay.mem(t).size.max(8).div_ceil(8);
            Some(vec![
                b.alloca(&LTy::Array(Box::new(LTy::I64), u64::from(words))),
            ])
        }
        Op::TypeNew => Some(
            inst.args
                .iter()
                .flat_map(|a| vals[&a.index()].clone())
                .collect(),
        ),
        Op::TypeGet => {
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

/// Writes a type or `ptr` operation that `bind_early` left to an instruction; each result takes
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
        Op::Load | Op::Take | Op::Store | Op::Put
            if empty(lay, f.ty(inst.res.unwrap_or_else(|| inst.args[1]))) => {}
        Op::Load | Op::Take => {
            let ty = f.ty(inst.res.expect("load result"));
            load_value(b, lay, ty, &arg(0)[0], &out);
        }
        Op::Store | Op::Put => {
            store_value(b, lay, f.ty(inst.args[1]), vals, inst.args[1], &arg(0)[0]);
        }
        Op::PtrField => {
            let Imm::Field(r, i) = inst.imm else { return };
            let rty = lay.m.types.find(&TyKind::Type(r)).expect("type interned");
            if let Some(r) = indirect(lay, rty) {
                ptr_field(cx, b, r, i as usize, &arg(0)[0], &out[0]);
                return;
            }
            let (at, _) = field_span(lay, rty, i as usize);
            b.name_next(&out[0]);
            match shape(b.types(), lay, rty) {
                Some(s) => b.leaf_ptr(&s.st, &arg(0)[0], at),
                None => {
                    let offsets = mem_layout(&lay.leaves(rty)).offsets;
                    b.byte_ptr(&arg(0)[0], offsets[at] as u64)
                }
            };
        }
        Op::TypeNew if indirect(lay, f.ty(inst.res.expect("type.new result"))).is_some() => {
            let r = indirect(lay, f.ty(inst.res.expect("type.new result"))).expect("checked");
            type_new(cx, b, r, inst, vals, &out[0]);
        }
        Op::TypeNew => {
            // A type in memory: each field is stored into a fresh slot.
            let res = inst.res.expect("type.new result");
            let s = shape(b.types(), lay, f.ty(res)).expect("is_mem checked");
            b.alloca_as(&out[0], &s.st);
            let mut at = 0;
            for a in &inst.args {
                at += write_field(b, lay, f, vals, &s, &out[0], at, *a);
            }
        }
        Op::TypeGet if indirect(lay, f.ty(inst.args[0])).is_some() => {
            let Imm::Field(r, i) = inst.imm else { return };
            type_get(cx, b, r, i as usize, &arg(0)[0], &out);
        }
        Op::TypeGet => {
            let Imm::Field(_, i) = inst.imm else { return };
            let res = inst.res.expect("type.get result");
            let rty = f.ty(inst.args[0]);
            let (at, n) = field_span(lay, rty, i as usize);
            let s = shape(b.types(), lay, rty).expect("is_mem checked");
            let tval = arg(0)[0].clone();
            if is_mem(lay, f.ty(res)) {
                // A nested type is the same bytes at an offset; the parent is never written.
                b.name_next(&out[0]);
                b.leaf_ptr(&s.st, &tval, at);
            } else {
                load_leaves(b, &s, &tval, at, n, &out);
            }
        }
        Op::TypeSet | Op::TypeFill if indirect(lay, f.ty(inst.args[0])).is_some() => {
            let Imm::Field(r, i) = inst.imm else { return };
            type_set(cx, b, r, i as usize, inst, vals, &arg(0)[0], &out[0]);
        }
        Op::TypeSet | Op::TypeFill => {
            let Imm::Field(_, i) = inst.imm else { return };
            let rty = f.ty(inst.args[0]);
            let (at, _) = field_span(lay, rty, i as usize);
            let s = shape(b.types(), lay, rty).expect("is_mem checked");
            let src = arg(0)[0].clone();
            b.alloca_as(&out[0], &s.st);
            b.copy_bytes(&out[0], &src, s.size as u64, s.align as u64);
            write_field(b, lay, f, vals, &s, &out[0], at, inst.args[1]);
        }
        Op::TypeRelease => {
            let Imm::TypeMask(_, mask) = inst.imm else {
                return;
            };
            let rty = f.ty(inst.args[0]);
            if let Some(r) = indirect(lay, rty) {
                release_block(cx, b, r, mask, &arg(0)[0]);
                return;
            }
            let own = arg(0).clone();
            let s = is_mem(lay, rty).then(|| shape(b.types(), lay, rty).expect("is_mem checked"));
            for (fty, at, n) in released(lay, rty, mask) {
                let leaves = match &s {
                    // A field that is itself a type in memory is its address in the parent.
                    Some(s) if is_mem(lay, fty) => vec![b.field_ptr(&s.st, &own[0], at)],
                    Some(s) => load_leaves(b, s, &own[0], at, n, &[]),
                    None => own[at..at + n].to_vec(),
                };
                super::glue::drop_held(cx, fty, leaves, b);
            }
        }
        _ => unreachable!("handles lists the ops"),
    }
}

/// Defines the held value `out` of type `ty` from the memory at `p`: a type in memory is copied
/// into a fresh slot, anything else is loaded leaf by leaf.
pub(super) fn load_value(b: &mut FnBuilder, lay: &Layouts, ty: Ty, p: &Val, out: &[Val]) {
    let s = shape(b.types(), lay, ty).expect("the type has a memory shape");
    if is_mem(lay, ty) {
        b.alloca_as(&out[0], &s.st);
        b.copy_bytes(&out[0], p, s.size as u64, s.align as u64);
    } else {
        load_leaves(b, &s, p, 0, s.leaves.len(), out);
    }
}

/// Stores MIR value `v` of type `ty` into the memory at `p`.
pub(super) fn store_value(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    vals: &Vals,
    v: Value,
    p: &Val,
) {
    let s = shape(b.types(), lay, ty).expect("the type has a memory shape");
    if is_mem(lay, ty) {
        b.copy_bytes(p, &vals[&v.index()][0], s.size as u64, s.align as u64);
    } else {
        store_leaves(b, &s, p, 0, &vals[&v.index()]);
    }
}

const NULL: fn() -> Val = || Val::new("null", LTy::Ptr);

/// Declares the runtime's allocator and `free` for a block.
pub(super) fn declare_heap(cx: &mut Cx) {
    super::rt::declare(cx, "msrt_alloc");
    super::rt::declare(cx, "msrt_free");
}

/// A fresh heap block of `size` bytes, named `dst` when given.
pub(super) fn alloc(b: &mut FnBuilder, size: u32, dst: Option<&Val>) -> Val {
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

/// `type.new` of an indirect type: one heap block with the field leaves stored at their offsets;
/// a map or set that is not the all-zero empty value gets a header block of its own, else the
/// field is null.
fn type_new(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::TypeId,
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
            let p = b.leaf_ptr(&s.st, &block, at);
            b.store(&header, &p, 8);
        } else {
            store_leaves(b, &s, &block, at, &words[..n]);
        }
    }
}

/// `type.set` and `type.fill` of an indirect type: the fields move into a fresh block with field
/// `i` replaced, then the old block is freed, so no block is written in place. `type.set` drops
/// the old value first; a boxed collection's old header block is freed either way.
#[allow(clippy::too_many_arguments)]
fn type_set(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::TypeId,
    i: usize,
    inst: &Inst,
    vals: &Vals,
    old: &Val,
    out: &Val,
) {
    declare_heap(cx);
    let lay = cx.lay;
    let s = block_shape(b.types(), lay, r);
    let (at, n, boxed) = block_spans(lay, r)[i];
    let fty = lay.m.type_defs[r.index()].fields[i].1;
    let drop_old = inst.op == Op::TypeSet && lay.m.needs_drop(fty);
    let block = alloc(b, s.size, Some(out));
    b.copy_bytes(&block, old, s.size as u64, s.align as u64);
    let words = &vals[&inst.args[1].index()];
    if boxed {
        let slot = b.leaf_ptr(&s.st, old, at);
        let bp = b.load(&LTy::Ptr, &slot, 8);
        let some = b.icmp("ne", &bp, &NULL());
        let (_, then, join) = next_split(cx, "s");
        b.cond_br(&some, &then, &join);
        b.label(&then);
        if drop_old {
            let held = (0..lay.width(fty))
                .map(|w| {
                    let at = b.elem_ptr(&LTy::I64, &bp, &Val::int(w as i64));
                    b.load(&LTy::I64, &at, 8)
                })
                .collect();
            super::glue::drop_held(cx, fty, held, b);
        }
        let word = b.ptr_to_int(&bp);
        b.call(&LTy::Void, "", "msrt_free", &[(word, "")]);
        b.br(&join);
        b.label(&join);
        let header = header_store(cx, b, words);
        let p = b.leaf_ptr(&s.st, &block, at);
        b.store(&header, &p, 8);
    } else {
        if drop_old {
            let held = load_leaves(b, &s, old, at, n, &[]);
            super::glue::drop_held(cx, fty, held, b);
        }
        store_leaves(b, &s, &block, at, &words[..n]);
    }
    let word = b.ptr_to_int(old);
    b.call(&LTy::Void, "", "msrt_free", &[(word, "")]);
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

/// `type.get` of an indirect type: the field's leaves loaded from the block; a map or set loads
/// its header through the pointer, or is the all-zero empty value when that is null.
fn type_get(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::TypeId,
    i: usize,
    tval: &Val,
    out: &[Val],
) {
    let lay = cx.lay;
    let s = block_shape(b.types(), lay, r);
    let (at, n, boxed) = block_spans(lay, r)[i];
    if !boxed {
        load_leaves(b, &s, tval, at, n, out);
        return;
    }
    let p = b.leaf_ptr(&s.st, tval, at);
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

/// `ptr.field` of an indirect type: the argument addresses the type's pointer; the result is
/// the address of the field in the block, or for a map or set the header block, created empty when
/// the field is null.
fn ptr_field(
    cx: &mut Cx,
    b: &mut FnBuilder,
    r: ms_mir::types::TypeId,
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
        b.leaf_ptr(&s.st, &block, k);
        return;
    }
    declare_heap(cx);
    let slot = b.leaf_ptr(&s.st, &block, k);
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

/// Stores MIR value `v` into the type `slot` at leaf `at`; returns the leaves it spans.
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
        let p = b.leaf_ptr(&s.st, slot, at);
        let inner = shape(b.types(), lay, ty).expect("is_mem checked");
        b.copy_bytes(&p, &src, inner.size as u64, inner.align as u64);
    } else {
        store_leaves(b, s, slot, at, &vals[&v.index()]);
    }
    n
}

/// Defines the held value of a call result that is a type in memory from the call's own result
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
/// (in the leaf convention, not the native one) as an address, and each is converted; every other leaf is the call's
/// result itself under its reserved name.
pub(super) fn name_leaves(b: &mut FnBuilder, r: Val, out: &[Val], _native: bool) {
    let abi = ret_leaf_types(&r.ty, out.len());
    for (k, dst) in out.iter().enumerate() {
        let same = abi[k] == dst.ty;
        let word = if out.len() == 1 {
            r.clone()
        } else if same {
            b.name_next(dst);
            b.extract(&r, k);
            continue;
        } else {
            b.extract(&r, k)
        };
        b.name_next(dst);
        assert!(!same, "a single leaf that matches needs no conversion");
        from_abi(b, &word, &dst.ty);
    }
}

/// A leaf that arrived in the leaf convention as the type it is held as: an address as a `ptr`, a
/// `double` as a `float`, an `i64` or byte as the narrower integer.
fn from_abi(b: &mut FnBuilder, v: &Val, held: &LTy) -> Val {
    match held {
        LTy::Ptr => b.int_to_ptr(v),
        LTy::F32 => b.fptrunc(v),
        _ => b.trunc(v, held.clone()),
    }
}

/// The types of the `n` leaves a call returns as `ret`: the tuple's elements, or the one type.
fn ret_leaf_types(ret: &LTy, n: usize) -> Vec<LTy> {
    match ret {
        LTy::Tuple(ts) => ts.clone(),
        t if n == 1 => vec![t.clone()],
        _ => Vec::new(),
    }
}

/// Whether a leaf of a call result is held as another type than it comes back as: a boolean as a
/// byte, a pointer as an address in the leaf convention, a narrow integer as an `i64`, a
/// `Float32` as a `double`.
pub(super) fn ret_needs_conversion(ret: &LTy, out: &[Val]) -> bool {
    ret_leaf_types(ret, out.len())
        .iter()
        .zip(out)
        .any(|(abi, dst)| *abi != dst.ty)
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

/// A pointer to value `v` of type `ty` to pass by pointer: the slot of a type in memory, or a
/// fresh stack slot holding its leaves.
pub(super) fn spill(b: &mut FnBuilder, lay: &Layouts, ty: Ty, vals: &Vals, v: Value) -> Val {
    spill_of(b, lay, ty, &vals[&v.index()])
}

/// [`spill`] of the held values `own` of a `ty`.
pub(super) fn spill_of(b: &mut FnBuilder, lay: &Layouts, ty: Ty, own: &[Val]) -> Val {
    if is_mem(lay, ty) {
        return own[0].clone();
    }
    let leaves = abi_leaves_of(b, lay, ty, own, Abi::Native);
    let st = super::aggregate(b.types(), lay, ty);
    let slot = b.alloca(&st);
    store_regs(b, lay, ty, &st, &slot, &leaves);
    slot
}

fn store_regs(b: &mut FnBuilder, lay: &Layouts, ty: Ty, st: &LTy, base: &Val, leaves: &[Val]) {
    let mem = mem_leaves(lay, ty);
    for (k, v) in leaves.iter().enumerate() {
        let p = b.leaf_ptr(st, base, k);
        store_leaf(b, v, &mem[k], &p);
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
    let leaves = abi_leaves(b, lay, ty, vals, v, Abi::Native);
    let st = super::aggregate(b.types(), lay, ty);
    store_regs(b, lay, ty, &st, sret, &leaves);
}

/// The slot a call result of type `ty` is written to: the result's own name for a type in
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
        let p = b.leaf_ptr(&st, slot, k);
        load_into(b, dst, &mem[k], &p);
    }
}

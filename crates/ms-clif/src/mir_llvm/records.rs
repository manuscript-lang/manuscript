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

use super::{Vals, leaves};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Op, Target, Value};
use ms_mir::types::{Ty, TyKind};

/// Records with more leaves than this live in memory.
pub(super) const MEM_LEAVES: usize = 8;

/// The memory shape of a type whose leaves are all `i64`, `f64` or `i8`.
pub(super) struct Shape {
    /// The struct of the leaves.
    pub st: LTy,
    /// Memory type of each leaf.
    pub leaves: Vec<LTy>,
    /// Byte offset of each leaf.
    pub offsets: Vec<u32>,
    pub size: u32,
    pub align: u32,
}

/// The shape of `ty`, when it has leaves and every leaf has the same size in registers and in memory.
pub(super) fn shape(lay: &Layouts, ty: Ty) -> Option<Shape> {
    let raw = lay.leaves(ty);
    let leaves: Vec<LTy> = raw
        .iter()
        .map(|l| match l {
            Leaf::I64 => Some(LTy::I64),
            Leaf::F64 => Some(LTy::F64),
            Leaf::I8 => Some(LTy::I8),
            _ => None,
        })
        .collect::<Option<_>>()?;
    if leaves.is_empty() {
        return None;
    }
    let mem = mem_layout(&raw);
    Some(Shape {
        st: LTy::Tuple(leaves.clone()),
        leaves,
        offsets: mem.offsets,
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

/// Whether a record holds a `ptr` field anywhere inside.
fn holds_ptr(lay: &Layouts, ty: Ty) -> bool {
    match record(lay, ty) {
        Some(r) => lay.m.records[r.index()]
            .fields
            .iter()
            .any(|f| f.1 == Ty::PTR || holds_ptr(lay, f.1)),
        None => false,
    }
}

/// Whether this module handles values of `ty`: `ptr`, and records that are either small or have a
/// memory shape.
pub(super) fn ty_ok(lay: &Layouts, ty: Ty) -> bool {
    ty == Ty::PTR
        || (record(lay, ty).is_some()
            && !holds_ptr(lay, ty)
            && (lay.width(ty) <= MEM_LEAVES || shape(lay, ty).is_some()))
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
    let mem_ty = |t: Ty| shape(lay, t).is_some();
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
    if is_mem(lay, ty) || ty == Ty::PTR {
        return vec![LTy::Ptr];
    }
    leaves(lay, ty).into_iter().map(|l| l.0).collect()
}

/// The values of a block parameter: its own reserved names, or for a record in memory a slot that
/// each incoming edge copies into.
pub(super) fn block_param(b: &mut FnBuilder, lay: &Layouts, ty: Ty) -> Vec<Val> {
    if is_mem(lay, ty) {
        let st = shape(lay, ty).expect("is_mem checked").st;
        return vec![b.alloca(&st)];
    }
    reserve(b, lay, ty)
}

/// Reserves the names a result of type `ty` is held under; a record in memory has none until its
/// instruction defines it.
pub(super) fn reserve(b: &mut FnBuilder, lay: &Layouts, ty: Ty) -> Vec<Val> {
    if is_mem(lay, ty) {
        return vec![];
    }
    held(lay, ty).into_iter().map(|t| b.reserve(t)).collect()
}

/// Leaf index and count of field `i` of record type `rty`.
fn field_span(lay: &Layouts, rty: Ty, i: usize) -> (usize, usize) {
    let r = record(lay, rty).expect("a record");
    let fields = &lay.m.records[r.index()].fields;
    let at = fields[..i].iter().map(|f| lay.width(f.1)).sum();
    (at, lay.width(fields[i].1))
}

/// The leaves of `v` as they cross a call: a `ptr` as its address, a record in memory loaded.
pub(super) fn abi_leaves(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    vals: &Vals,
    v: Value,
) -> Vec<Val> {
    let own = &vals[&v.index()];
    if ty == Ty::PTR {
        return vec![b.ptr_to_int(&own[0])];
    }
    if is_mem(lay, ty) {
        let s = shape(lay, ty).expect("is_mem checked");
        return load_leaves(b, &s, &own[0], 0, s.leaves.len(), &[]);
    }
    own.clone()
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
            let p = b.byte_ptr(base, s.offsets[k] as u64);
            if let Some(v) = named.get(k - at) {
                b.name_next(v);
            }
            b.load(&s.leaves[k], &p, align(&s.leaves[k]))
        })
        .collect()
}

fn store_leaves(b: &mut FnBuilder, s: &Shape, base: &Val, at: usize, leaves: &[Val]) {
    for (k, v) in leaves.iter().enumerate() {
        let p = b.byte_ptr(base, s.offsets[at + k] as u64);
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
    /// A `ptr` parameter arrives as an address.
    Ptr { held: Val, abi: Val },
    /// A record in memory arrives as leaves and is stored into its slot.
    Mem { slot: Val, abi: Vec<Val>, ty: Ty },
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
    if ty == Ty::PTR {
        let held = b.reserve(LTy::Ptr);
        entry.push(Entry::Ptr {
            held: held.clone(),
            abi: abi[0].clone(),
        });
        return vec![held];
    }
    if is_mem(lay, ty) {
        let slot = b.alloca(&shape(lay, ty).expect("is_mem checked").st);
        entry.push(Entry::Mem {
            slot: slot.clone(),
            abi,
            ty,
        });
        return vec![slot];
    }
    abi
}

pub(super) fn emit_entry(b: &mut FnBuilder, lay: &Layouts, entry: Vec<Entry>) {
    for e in entry {
        match e {
            Entry::Ptr { held, abi } => {
                b.name_next(&held);
                b.int_to_ptr(&abi);
            }
            Entry::Mem { slot, abi, ty } => {
                let s = shape(lay, ty).expect("is_mem checked");
                store_leaves(b, &s, &slot, 0, &abi);
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
            let s = shape(lay, f.ty(p.value)).expect("is_mem checked");
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
            let st = shape(lay, t)?;
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

/// Writes a record or `ptr` operation that `bind_early` left to an instruction. `out` holds the
/// names reserved for the result.
pub(super) fn inst(
    b: &mut FnBuilder,
    lay: &Layouts,
    f: &Func,
    vals: &mut Vals,
    inst: &Inst,
    out: &[Val],
) {
    let arg = |vals: &Vals, i: usize| vals[&inst.args[i].index()].clone();
    match inst.op {
        _ if is_early(lay, f, inst) => {}
        Op::Load | Op::Take => {
            let res = inst.res.expect("load result");
            let ty = f.ty(res);
            let p = arg(vals, 0)[0].clone();
            let leaves = if is_mem(lay, ty) {
                let s = shape(lay, ty).expect("is_mem checked");
                let slot = b.alloca(&s.st);
                b.copy_bytes(&slot, &p, s.size as u64, s.align as u64);
                vec![slot]
            } else {
                let s = shape(lay, ty).expect("op_ok checked");
                if ty == Ty::PTR {
                    let t = b.load(&LTy::I64, &p, 8);
                    b.name_next(&out[0]);
                    vec![b.int_to_ptr(&t)]
                } else {
                    load_leaves(b, &s, &p, 0, s.leaves.len(), out)
                }
            };
            vals.insert(res.index(), leaves);
        }
        Op::Store | Op::Put => {
            let p = arg(vals, 0)[0].clone();
            let ty = f.ty(inst.args[1]);
            let s = shape(lay, ty).expect("op_ok checked");
            if is_mem(lay, ty) {
                let src = arg(vals, 1)[0].clone();
                b.copy_bytes(&p, &src, s.size as u64, s.align as u64);
            } else {
                let v = abi_leaves(b, lay, ty, vals, inst.args[1]);
                store_leaves(b, &s, &p, 0, &v);
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
            let offsets = mem_layout(&lay.leaves(rty)).offsets;
            let p = arg(vals, 0)[0].clone();
            b.name_next(&out[0]);
            b.byte_ptr(&p, offsets[at] as u64);
        }
        Op::RecNew => {
            // A record in memory: each field is stored into a fresh slot.
            let res = inst.res.expect("rec.new result");
            let s = shape(lay, f.ty(res)).expect("is_mem checked");
            let slot = b.alloca(&s.st);
            let mut at = 0;
            for a in &inst.args {
                at += write_field(b, lay, f, vals, &s, &slot, at, *a);
            }
            vals.insert(res.index(), vec![slot]);
        }
        Op::RecGet => {
            let Imm::Field(_, i) = inst.imm else { return };
            let res = inst.res.expect("rec.get result");
            let rty = f.ty(inst.args[0]);
            let (at, n) = field_span(lay, rty, i as usize);
            let s = shape(lay, rty).expect("is_mem checked");
            let rec = arg(vals, 0)[0].clone();
            let leaves = if is_mem(lay, f.ty(res)) {
                // A nested record is the same bytes at an offset; the parent is never written.
                vec![b.byte_ptr(&rec, s.offsets[at] as u64)]
            } else {
                load_leaves(b, &s, &rec, at, n, out)
            };
            vals.insert(res.index(), leaves);
        }
        Op::RecSet | Op::RecFill => {
            let Imm::Field(_, i) = inst.imm else { return };
            let res = inst.res.expect("rec.set result");
            let rty = f.ty(inst.args[0]);
            let (at, _) = field_span(lay, rty, i as usize);
            let s = shape(lay, rty).expect("is_mem checked");
            let src = arg(vals, 0)[0].clone();
            let slot = b.alloca(&s.st);
            b.copy_bytes(&slot, &src, s.size as u64, s.align as u64);
            write_field(b, lay, f, vals, &s, &slot, at, inst.args[1]);
            vals.insert(res.index(), vec![slot]);
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
        let p = b.byte_ptr(slot, s.offsets[at] as u64);
        let inner = shape(lay, ty).expect("is_mem checked");
        b.copy_bytes(&p, &src, inner.size as u64, inner.align as u64);
    } else {
        store_leaves(b, s, slot, at, &vals[&v.index()]);
    }
    n
}

/// Defines the held values of a call result of type `ty` from the call's own result `r` (a leaf,
/// or a tuple of several). A single named result takes `out[0]`.
pub(super) fn call_result(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    r: Val,
    out: &[Val],
) -> Vec<Val> {
    if ty == Ty::PTR {
        b.name_next(&out[0]);
        return vec![b.int_to_ptr(&r)];
    }
    let s = shape(lay, ty).expect("is_mem checked");
    let abi = if s.leaves.len() == 1 {
        vec![r]
    } else {
        (0..s.leaves.len()).map(|k| b.extract(&r, k)).collect()
    };
    let slot = b.alloca(&s.st);
    store_leaves(b, &s, &slot, 0, &abi);
    vec![slot]
}

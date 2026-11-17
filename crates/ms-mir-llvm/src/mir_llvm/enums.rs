//! Enums and optionals: tags, payloads and construction.
//!
//! An optional or an enum that does not hold itself is its leaves: a tag (or an `i1` presence flag,
//! or a null `ptr`) and payload slots. Construction, tag reads and payload reads mostly choose
//! leaves, so they write no instruction. An enum's payload slots are shared between cases, so a
//! slot is a plain `i64`, `double` or `i8`: a `ptr` or `i1` payload converts at the boundary, one
//! cast each. `opt.is_some` of a niche optional is one comparison. An enum that contains itself
//! is one pointer to a heap block (case index first, then the shared payload slots): building it
//! allocates, reading loads, and taking a payload out frees the block; a case with no payload is
//! a shared static block that is never freed. Payloads that are types in memory stay on the
//! translation. Fields a release leaves behind are dropped through the drop glue.

use super::{Area, Cx, Vals, held_leaves, mem_leaf, mem_leaves, narrow_leaves, types};
use crate::llvm_build::{Bin, FnBuilder, Meta, Range, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op};
use ms_mir::layout::{AltRepr, Layouts, Leaf, mem_layout};
use ms_mir::types::{AltId, Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    splits,
    pure_op: handles,
    pre,
    emit,
};

/// Any optional or enum travels as its leaves, so it is fine as a value; the ops below reject the
/// ones that live behind a pointer.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Opt(_) | TyKind::Alt(_))
}

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::OptSome
            | Op::OptView
            | Op::OptViewAt
            | Op::OptNone
            | Op::OptNoneOwned
            | Op::OptIsSome
            | Op::OptGet
            | Op::OptAddr
            | Op::AltNew
            | Op::AltView
            | Op::AltPlain
            | Op::AltTag
            | Op::AltGet
            | Op::AltTake
    )
}

/// How an optional that is not behind a pointer is laid out (`layout.rs`).
#[derive(Clone, Copy, PartialEq, Eq)]
enum OptRepr {
    /// `present: i1`, then the payload's leaves.
    Tagged,
    /// A nullable pointer or handle: the payload itself, null for none.
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

/// Whether values of `ty` are all register leaves, here: not behind a pointer and holding no
/// type that lives in memory.
fn plain(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Opt(inner) => {
            !lay.opt_is_boxed(*inner) && (leafy(lay, *inner) || mem_opt(lay, ty).is_some())
        }
        TyKind::Alt(a) => !lay.is_boxed(*a) && fields_leafy(lay, ty, *a, None),
        _ => !types::is_mem(lay, ty),
    }
}

/// The type in memory that field `i` of case `c` of `alt` (of type `ty`) is, when its leaves
/// can move between the type's memory and the enum's slots as they are: each slot holds the
/// leaf's memory type, or an `i64` for a narrow integer or a pointer, or an `i1` for a byte.
fn mem_field(lay: &Layouts, ty: Ty, alt: AltId, c: usize, i: usize) -> Option<Ty> {
    let (fty, idx) = lay.alt_fields(alt)[c][i].clone();
    if !types::is_mem(lay, fty) {
        return None;
    }
    let (slots, mem) = (held_leaves(lay, ty), mem_leaves(lay, fty));
    idx.iter()
        .zip(&mem)
        .all(|(k, m)| slot_fits(&slots[*k], m))
        .then_some(fty)
}

/// Whether field `i` of case `c` of the boxed enum `alt` (of type `ty`) is a type in memory whose
/// leaves move to and from the slots of the enum's heap block one by one: a map or set (seven
/// words) or a record that holds one.
fn block_mem_field(lay: &Layouts, ty: Ty, alt: AltId, c: usize, i: usize) -> bool {
    let (fty, idx) = &lay.alt_fields(alt)[c][i];
    if !types::is_mem(lay, *fty) || !types::shape_ok(lay, *fty) {
        return false;
    }
    let block = block_of(lay, ty);
    idx.iter()
        .zip(&mem_leaves(lay, *fty))
        .all(|(k, m)| slot_fits(&slot_ty(block[*k]), m))
}

/// Whether a leaf of memory type `mem` moves to or from a slot held as `slot` by a conversion.
fn slot_fits(slot: &LTy, mem: &LTy) -> bool {
    slot == mem
        || matches!(
            (slot, mem),
            (LTy::I64, LTy::I8 | LTy::I16 | LTy::I32 | LTy::Ptr)
                | (LTy::Ptr, LTy::I64)
                | (LTy::I1, LTy::I8)
        )
}

/// The record in memory that the optional `ty` holds, when it is a tagged optional whose payload
/// leaves follow the presence flag and move to and from the record's memory.
fn mem_opt(lay: &Layouts, ty: Ty) -> Option<Ty> {
    let TyKind::Opt(inner) = lay.m.types.kind(ty) else {
        return None;
    };
    if lay.opt_is_boxed(*inner)
        || !types::is_mem(lay, *inner)
        || opt_repr(lay, ty) != OptRepr::Tagged
    {
        return None;
    }
    let slots = held_leaves(lay, ty);
    mem_leaves(lay, *inner)
        .iter()
        .zip(&slots[1..])
        .all(|(m, s)| slot_fits(s, m))
        .then_some(*inner)
}

/// Whether a value of `ty` is held in registers as leaves, where a pointer to a block counts as
/// one: a payload may be a self-containing enum or optional.
fn leafy(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Opt(inner) => {
            lay.opt_is_boxed(*inner) || leafy(lay, *inner) || mem_opt(lay, ty).is_some()
        }
        TyKind::Alt(a) => lay.is_boxed(*a) || fields_leafy(lay, ty, *a, None),
        _ => !types::is_mem(lay, ty),
    }
}

/// Whether the payload fields of case `case` of `a` (every case when `None`), of the enum `ty`,
/// are leafy, or are types in memory that move to and from the slots of an inline enum.
fn fields_leafy(lay: &Layouts, ty: Ty, a: AltId, case: Option<u32>) -> bool {
    lay.m.alts[a.index()]
        .cases
        .iter()
        .enumerate()
        .filter(|(c, _)| case.is_none_or(|k| k as usize == *c))
        .all(|(c, case)| {
            case.fields.iter().enumerate().all(|(i, f)| {
                leafy(lay, f.1)
                    || if lay.is_boxed(a) {
                        block_mem_field(lay, ty, a, c, i)
                    } else {
                        mem_field(lay, ty, a, c, i).is_some()
                    }
            })
        })
}

/// The self-containing enum `ty`, whose value is a pointer to its block.
fn boxed_alt(lay: &Layouts, ty: Ty) -> Option<AltId> {
    match lay.m.types.kind(ty) {
        TyKind::Alt(a) if lay.is_boxed(*a) => Some(*a),
        _ => None,
    }
}

/// The payload type of the self-containing optional `ty`, whose value is a nullable pointer to a
/// heap block holding the payload's leaves.
fn boxed_opt(lay: &Layouts, ty: Ty) -> Option<Ty> {
    match lay.m.types.kind(ty) {
        TyKind::Opt(inner) if lay.opt_is_boxed(*inner) => Some(*inner),
        _ => None,
    }
}

/// The slot kinds of the heap block of the boxed enum `ty`: the case index, then payload slots.
fn block_of(lay: &Layouts, ty: Ty) -> Vec<Leaf> {
    match &lay.shape(ty).alt {
        Some(AltRepr::Boxed { block, .. }) => block.clone(),
        _ => unreachable!("a boxed enum"),
    }
}

/// Every slot type of a block is one this module reads and writes: a word, double, byte, or a
/// narrow integer or `Float32` at its own width.
fn block_ok(block: &[Leaf]) -> bool {
    block
        .iter()
        .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8 | Leaf::F32) || types::is_narrow(*l))
}

/// The constant zero of a held type.
pub(super) fn zero(t: &LTy) -> Val {
    match t {
        LTy::I1 => Val::bool(false),
        LTy::I8 => Val::byte(0),
        LTy::I16 | LTy::I32 => Val::new("0", t.clone()),
        LTy::F64 => Val::double(0),
        LTy::F32 => Val::new("0.0", LTy::F32),
        LTy::Ptr => Val::new("null", LTy::Ptr),
        _ => Val::int(0),
    }
}

/// `v` as `to`: a payload leaf between the type it is held as and the slot it lives in. A narrow
/// integer fills an `i64` slot extended by its signedness (`signed`) and reads back truncated.
fn convert(b: &mut FnBuilder, v: &Val, to: &LTy, signed: Option<bool>) -> Val {
    match (&v.ty, to) {
        (a, b_) if a == b_ => v.clone(),
        (LTy::I1, LTy::I8) => b.zext(v, LTy::I8),
        (LTy::I8, LTy::I1) => b.icmp("ne", v, &Val::byte(0)),
        (LTy::Ptr, LTy::I64) => b.ptrtoint(v),
        (LTy::I64, LTy::Ptr) => b.inttoptr(v),
        (LTy::I8 | LTy::I16 | LTy::I32, LTy::I64) if signed == Some(true) => b.sext(v, LTy::I64),
        (LTy::I8 | LTy::I16 | LTy::I32, LTy::I64) => b.zext(v, LTy::I64),
        (LTy::I64, LTy::I8 | LTy::I16 | LTy::I32) => b.trunc(v, to.clone()),
        (LTy::F32, LTy::F64) => b.fpext(v),
        (LTy::F64, LTy::F32) => b.fptrunc(v),
        (a, t) => unreachable!("no conversion from {a:?} to {t:?}"),
    }
}

/// The optional or enum operand or result the op works on.
fn subject(f: &Func, inst: &Inst) -> Ty {
    match inst.op {
        Op::OptSome | Op::OptView | Op::OptNone | Op::OptNoneOwned | Op::AltNew | Op::AltView => {
            f.ty(inst.res.expect("a result"))
        }
        _ => f.ty(inst.args[0]),
    }
}

fn inst_ok(_: &Module, lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    // The address of a boxed optional's payload is the optional itself, a nullable pointer.
    if inst.op == Op::OptAddr {
        return opt_repr(lay, f.ty(inst.args[0])) == OptRepr::Nullable;
    }
    if inst.op == Op::OptViewAt {
        return opt_repr(lay, f.ty(inst.res.expect("a result"))) == OptRepr::Nullable;
    }
    let subject = subject(f, inst);
    if let Some(inner) = boxed_opt(lay, subject) {
        return types::shape_ok(lay, inner);
    }
    if let Some(a) = boxed_alt(lay, subject) {
        let case = match inst.imm {
            Imm::Case(_, c) | Imm::AltField(_, c, _) | Imm::AltMask(_, c, _) => Some(c),
            _ => None,
        };
        return block_ok(&block_of(lay, subject)) && fields_leafy(lay, subject, a, case);
    }
    plain(lay, subject)
}

/// No enum or optional op splits its block.
fn splits(_: &Layouts, _: &Func, _: &Inst, _: bool) -> usize {
    0
}

/// The leaves a payload read or write moves between a field and the enum's slots: for each
/// result leaf (a read) or slot (a write), the slot or field leaf it comes from.
fn sources(lay: &Layouts, inst: &Inst, vals: &Vals) -> Vec<(usize, Val, Option<bool>)> {
    let arg = |i: usize| &vals[&inst.args[i].index()];
    match (inst.op, inst.imm) {
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            let mut out = Vec::new();
            for (i, (t, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                // A record in memory is loaded in `emit`, not moved leaf by leaf.
                if !types::is_mem(lay, *t) {
                    let signs = narrow_leaves(lay, *t);
                    out.extend(
                        idx.iter()
                            .copied()
                            .zip(arg(i).iter().cloned())
                            .zip(signs)
                            .map(|((k, v), s)| (k, v, s)),
                    );
                }
            }
            out
        }
        (Op::AltGet | Op::AltTake, Imm::AltField(a, c, i)) => {
            let (t, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            if types::is_mem(lay, *t) {
                return Vec::new();
            }
            let signs = narrow_leaves(lay, *t);
            idx.iter()
                .enumerate()
                .map(|(j, k)| (j, arg(0)[*k].clone(), signs[j]))
                .collect()
        }
        _ => Vec::new(),
    }
}

/// The values of an op that only chooses leaves, converting a payload leaf whose held type is not
/// its slot's: a converted leaf takes a reserved name that `emit` defines.
fn pre(
    _: &Module,
    lay: &Layouts,
    f: &Func,
    inst: &Inst,
    vals: &Vals,
    b: &mut FnBuilder,
) -> Option<Vec<Val>> {
    let arg = |i: usize| &vals[&inst.args[i].index()];
    let res_ty = || f.ty(inst.res.expect("a result"));
    // A boxed enum's ops read or write its block; only the pointer itself is free. A payload that
    // is a type in memory comes out as a new slot, which `emit` fills.
    if (inst.op != Op::AltPlain && boxed_alt(lay, subject(f, inst)).is_some())
        || (matches!(inst.op, Op::AltGet | Op::AltTake)
            && inst.res.is_some_and(|r| types::is_mem(lay, f.ty(r))))
        || (matches!(inst.op, Op::OptGet) && mem_opt(lay, f.ty(inst.args[0])).is_some())
    {
        return None;
    }
    // A boxed optional's payload is in its block; none and the presence test are the pointer.
    if matches!(inst.op, Op::OptSome | Op::OptGet) && boxed_opt(lay, subject(f, inst)).is_some() {
        return None;
    }
    if matches!(inst.op, Op::OptSome | Op::OptView) && mem_opt(lay, res_ty()).is_some() {
        // The payload's leaves are loaded from its memory by `emit`.
        let held = held_leaves(lay, res_ty());
        return Some(
            std::iter::once(Val::bool(true))
                .chain(held[1..].iter().map(|t| b.reserve(t.clone())))
                .collect(),
        );
    }
    let mut out = match (inst.op, inst.imm) {
        (Op::OptSome | Op::OptView, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Tagged => std::iter::once(Val::bool(true))
                .chain(arg(0).iter().cloned())
                .collect(),
            _ => arg(0).clone(),
        },
        (Op::OptNone | Op::OptNoneOwned, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Str => vec![Val::int(0), Val::int(ms_rt_abi::STR_STATIC as i64)],
            _ => held_leaves(lay, res_ty()).iter().map(zero).collect(),
        },
        (Op::OptIsSome, _) if opt_repr(lay, f.ty(inst.args[0])) == OptRepr::Tagged => {
            vec![arg(0)[0].clone()]
        }
        (Op::OptAddr | Op::OptViewAt, _) => arg(0).clone(),
        (Op::OptGet, _) => match opt_repr(lay, f.ty(inst.args[0])) {
            OptRepr::Tagged => arg(0)[1..].to_vec(),
            _ => arg(0).clone(),
        },
        (Op::AltNew | Op::AltView, Imm::Case(_, c)) => {
            let mut out: Vec<Val> = held_leaves(lay, res_ty()).iter().map(zero).collect();
            out[0] = Val::int(c as i64);
            out
        }
        (Op::AltPlain, _) => arg(0).clone(),
        (Op::AltTag, _) => vec![arg(0)[0].clone()],
        (Op::AltGet | Op::AltTake, Imm::AltField(a, c, i)) => {
            let (fty, _) = lay.alt_fields(a)[c as usize][i as usize];
            held_leaves(lay, fty)
                .into_iter()
                .map(|t| zero(&t))
                .collect()
        }
        _ => return None,
    };
    // Payload leaves: the source itself when its type matches, else a name `emit` defines.
    let held = inst.res.map(|r| held_leaves(lay, f.ty(r)));
    for (i, src, _) in sources(lay, inst, vals) {
        let want = match inst.op {
            Op::AltNew | Op::AltView => src.ty.clone(),
            _ => held.as_ref().expect("a result")[i].clone(),
        };
        out[i] = match inst.op {
            Op::AltNew | Op::AltView => {
                let slot = out[i].ty.clone();
                if src.ty == slot { src } else { b.reserve(slot) }
            }
            _ if src.ty == want => src,
            _ => b.reserve(want),
        };
    }
    if let (Op::AltNew | Op::AltView, Imm::Case(a, c)) = (inst.op, inst.imm) {
        for (t, idx) in lay.alt_fields(a)[c as usize].iter() {
            if types::is_mem(lay, *t) {
                for k in idx {
                    out[*k] = b.reserve(out[*k].ty.clone());
                }
            }
        }
    }
    Some(out)
}

/// Defines the reserved leaves `pre` left: a payload leaf converted to or from its slot, and the
/// presence of a niche optional, which is present unless its first leaf is null (a string also
/// has the static tag: an inline string may have a zero first word, but never that tag).
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let Some(res) = inst.res else { return };
    let out = &vals[&res.index()];
    if boxed_alt(cx.lay, subject(cx.f, inst)).is_some() && inst.op != Op::AltPlain {
        boxed(cx, inst, vals, out, b);
        return;
    }
    if matches!(inst.op, Op::OptSome | Op::OptGet)
        && boxed_opt(cx.lay, subject(cx.f, inst)).is_some()
    {
        boxed_optional(cx, inst, vals, out, b);
        return;
    }
    if inst.op == Op::OptIsSome && opt_repr(cx.lay, cx.f.ty(inst.args[0])) != OptRepr::Tagged {
        let ty = cx.f.ty(inst.args[0]);
        let v = &vals[&inst.args[0].index()];
        // The presence test of a niche optional is the instruction itself, named for the result.
        let any = niche_any(b, cx.lay, ty, v);
        b.name_next(&out[0]);
        b.icmp("ne", &any, &zero(&any.ty));
        return;
    }
    for (i, src, signed) in sources(cx.lay, inst, vals) {
        if out[i] != src {
            b.name_next(&out[i]);
            convert(b, &src, &out[i].ty, signed);
        }
    }
    memory_payloads(cx, inst, vals, out, b);
}

/// A payload that is a type in memory: loaded from its address into the enum's slots for a new
/// enum, or stored from the slots into a new slot for a read.
fn memory_payloads(cx: &Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let lay = cx.lay;
    match (inst.op, inst.imm) {
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            for (i, (t, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                if types::is_mem(lay, *t) {
                    let named: Vec<Val> = idx.iter().map(|k| out[*k].clone()).collect();
                    let at = &vals[&inst.args[i].index()][0];
                    types::load_into_leaves(b, lay, *t, at, &named);
                }
            }
        }
        (Op::AltGet | Op::AltTake, Imm::AltField(a, c, i)) => {
            let (t, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            if types::is_mem(lay, *t) {
                let slots = &vals[&inst.args[0].index()];
                let leaves: Vec<Val> = idx.iter().map(|k| slots[*k].clone()).collect();
                types::store_into_slot(b, lay, *t, &out[0], &leaves);
            }
        }
        (Op::OptSome | Op::OptView, _) => {
            if let Some(inner) = mem_opt(lay, cx.f.ty(inst.res.expect("a result"))) {
                let at = &vals[&inst.args[0].index()][0];
                types::load_into_leaves(b, lay, inner, at, &out[1..]);
            }
        }
        (Op::OptGet, _) => {
            if let Some(inner) = mem_opt(lay, cx.f.ty(inst.args[0])) {
                let leaves = &vals[&inst.args[0].index()][1..];
                types::store_into_slot(b, lay, inner, &out[0], leaves);
            }
        }
        _ => {}
    }
}

/// Whether `inst` reads or writes memory: any op on a boxed enum. Every other enum op chooses
/// leaves.
pub(super) fn touches_memory(lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    handles(inst.op)
        && (boxed_alt(lay, subject(f, inst)).is_some()
            || (!matches!(inst.op, Op::OptAddr | Op::OptViewAt)
                && boxed_opt(lay, subject(f, inst)).is_some()))
}

/// The LLVM type of a payload slot: its memory type, an `i64` for a word that may hold a pointer.
fn slot_ty(l: Leaf) -> LTy {
    match l {
        Leaf::F64 => LTy::F64,
        Leaf::I8 | Leaf::F32 => mem_leaf(l),
        l if types::is_narrow(l) => mem_leaf(l),
        _ => LTy::I64,
    }
}

/// The address of slot `k` of the block `p`.
fn slot_ptr(b: &mut FnBuilder, block: &[Leaf], p: &Val, k: usize) -> Val {
    let at = i64::from(mem_layout(block).offsets[k]);
    b.elem_ptr(&LTy::I8, p, &Val::int(at))
}

/// Loads slot `k` as `held`: a word that holds a pointer is loaded as one, a flag is narrowed.
/// `dst` is the reserved name the result takes, when it has one.
fn load_slot(
    b: &mut FnBuilder,
    block: &[Leaf],
    p: &Val,
    k: usize,
    (held, signed): (&LTy, Option<bool>),
    dst: Option<&Val>,
) -> Val {
    let at = slot_ptr(b, block, p, k);
    let slot = slot_ty(block[k]);
    let align = block[k].size() as u64;
    let name = |b: &mut FnBuilder| {
        if let Some(d) = dst {
            b.name_next(d);
        }
        let _ = b;
    };
    if *held == LTy::Ptr || *held == slot {
        name(b);
        return b.load(held, &at, align);
    }
    let raw = b.load(&slot, &at, align);
    name(b);
    convert(b, &raw, held, signed)
}

/// The leaves of field `k` of case `c` of `a`, read from the block `p` of a boxed enum of type
/// `ty`, held as the field's type is.
fn block_field(
    b: &mut FnBuilder,
    lay: &Layouts,
    ty: Ty,
    (a, c, k): (AltId, u32, usize),
    p: &Val,
    dst: Option<&[Val]>,
) -> Vec<Val> {
    let block = block_of(lay, ty);
    let (fty, idx) = &lay.alt_fields(a)[c as usize][k];
    let held = held_leaves(lay, *fty);
    let signs = narrow_leaves(lay, *fty);
    idx.iter()
        .enumerate()
        .map(|(j, slot)| {
            load_slot(
                b,
                &block,
                p,
                *slot,
                (&held[j], signs[j]),
                dst.map(|d| &d[j]),
            )
        })
        .collect()
}

/// Ops on a boxed enum: a build allocates and fills the block, a tag or payload read loads from
/// it, and the block's case index carries its range.
fn boxed(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let lay = cx.lay;
    let ty = subject(cx.f, inst);
    let block = block_of(lay, ty);
    let arg = |i: usize| &vals[&inst.args[i].index()];
    match (inst.op, inst.imm) {
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            let fields = &lay.alt_fields(a)[c as usize];
            if fields.is_empty() {
                // A case with no payload is one shared static block.
                let sym = &cx.plan.units[&(a.index(), c as usize)];
                cx.data.push(sym.clone());
                let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
                b.name_next(&out[0]);
                b.elem_ptr(&LTy::I8, &addr, &Val::int(0));
                return;
            }
            let size = mem_layout(&block).size;
            types::declare_heap(cx);
            let p = types::alloc(b, size, Some(&out[0]));
            let tag = slot_ptr(b, &block, &p, 0);
            b.store(&Val::int(i64::from(c)), &tag, 8);
            for (i, (fty, idx)) in fields.iter().enumerate() {
                let signs = narrow_leaves(lay, *fty);
                // A type in memory is read into its leaves first.
                let leaves = if types::is_mem(lay, *fty) {
                    types::load_leaf_values(b, lay, *fty, &arg(i)[0])
                } else {
                    arg(i).clone()
                };
                for ((slot, v), signed) in idx.iter().zip(&leaves).zip(signs) {
                    let at = slot_ptr(b, &block, &p, *slot);
                    // A narrow integer or `float` fills its whole slot, extended as the value is.
                    let (mem, v) = match v.ty {
                        LTy::I1 => (LTy::I8, v.clone()),
                        LTy::I8 | LTy::I16 | LTy::I32 | LTy::F32 => {
                            let slot = slot_ty(block[*slot]);
                            (slot.clone(), convert(b, v, &slot, signed))
                        }
                        _ => (v.ty.clone(), v.clone()),
                    };
                    types::store_leaf(b, &v, &mem, &at);
                }
            }
        }
        (Op::AltTag, _) => {
            let n = lay.m.alts[boxed_alt(lay, ty).expect("boxed").index()]
                .cases
                .len();
            let meta = Meta {
                range: (1..=crate::llvm_ir::MAX_TAG_RANGE)
                    .contains(&n)
                    .then_some(Range::Tag(n)),
                ..Meta::default()
            };
            b.name_next(&out[0]);
            b.load_with(&LTy::I64, &arg(0)[0], 8, meta);
        }
        (Op::AltGet | Op::AltTake, Imm::AltField(a, c, k)) => {
            let (fty, _) = lay.alt_fields(a)[c as usize][k as usize];
            if types::is_mem(lay, fty) {
                // A type in memory is built from its slots in a fresh slot.
                let leaves = block_field(b, lay, ty, (a, c, k as usize), &arg(0)[0], None);
                types::store_into_slot(b, lay, fty, &out[0], &leaves);
                return;
            }
            block_field(b, lay, ty, (a, c, k as usize), &arg(0)[0], Some(out));
        }
        _ => unreachable!("handles lists the ops"),
    }
}

/// The word of a niche optional that is zero exactly when it is none (a string also has the static
/// tag: an inline string may have a zero first word, but never that tag).
fn niche_any(b: &mut FnBuilder, lay: &Layouts, ty: Ty, v: &[Val]) -> Val {
    match opt_repr(lay, ty) {
        OptRepr::Str => {
            let t = b.bin(Bin::Xor, &v[1], &Val::int(ms_rt_abi::STR_STATIC as i64));
            b.bin(Bin::Or, &v[0], &t)
        }
        OptRepr::Nullable => v[0].clone(),
        OptRepr::Tagged => unreachable!("a tagged optional has a flag"),
    }
}

/// Defines `out` from the payload of type `inner` in the block `p` of a boxed optional: a record
/// in memory is copied into a fresh slot, anything else loaded leaf by leaf.
fn read_payload(b: &mut FnBuilder, lay: &Layouts, inner: Ty, p: &Val, out: &[Val]) {
    types::load_value(b, lay, inner, p, out);
}

/// `opt.some` and `opt.get` of a boxed optional: a build allocates the block and stores the
/// payload, a read loads it.
fn boxed_optional(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let lay = cx.lay;
    let ty = subject(cx.f, inst);
    let inner = boxed_opt(lay, ty).expect("a boxed optional");
    types::declare_heap(cx);
    if inst.op == Op::OptSome {
        let size = types::shape(b.types(), lay, inner)
            .expect("shape_ok checked")
            .size;
        let p = types::alloc(b, size, Some(&out[0]));
        types::store_value(b, lay, inner, vals, inst.args[0], &p);
        return;
    }
    let p = &vals[&inst.args[0].index()][0];
    read_payload(b, lay, inner, p, out);
}

//! Enums and optionals: tags, payloads and construction.
//!
//! An optional or an enum that does not hold itself is its leaves: a tag (or an `i1` presence flag,
//! or a null `ptr`) and payload slots. Construction, tag reads and payload reads mostly choose
//! leaves, so they write no instruction. An enum's payload slots are shared between cases, so a
//! slot is a plain `i64`, `double` or `i8`: a `ptr` or `i1` payload converts at the boundary, one
//! cast each. `opt.is_some` of a niche optional is one comparison. Types behind a pointer
//! (self-containing) and payloads that are records in memory stay on the translation.

use super::{Area, Cx, Vals, held_leaves, mem_leaves, records};
use crate::layout::Layouts;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op};
use ms_mir::types::{AltId, Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    pure_op,
    pre,
    emit,
    splits,
};

/// Any optional or enum travels as its leaves, so it is fine as a value; the ops below reject the
/// ones that live behind a pointer.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Opt(_) | TyKind::Alt(_))
}

/// Releasing a payload may drop it, which runs glue: those ops touch memory.
fn pure_op(op: Op) -> bool {
    handles(op) && !matches!(op, Op::AltRelease | Op::AltUnbox)
}

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::OptSome
            | Op::OptView
            | Op::OptNone
            | Op::OptIsSome
            | Op::OptGet
            | Op::OptUnbox
            | Op::AltNew
            | Op::AltView
            | Op::AltPlain
            | Op::AltTag
            | Op::AltGet
            | Op::AltTake
            | Op::AltRelease
            | Op::AltUnbox
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
/// record that lives in memory.
fn plain(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Opt(inner) => !lay.opt_is_boxed(*inner) && plain(lay, *inner),
        TyKind::Alt(a) => {
            !lay.is_boxed(*a)
                && lay.m.alts[a.index()]
                    .cases
                    .iter()
                    .enumerate()
                    .all(|(c, case)| {
                        case.fields
                            .iter()
                            .enumerate()
                            .all(|(i, f)| plain(lay, f.1) || mem_field(lay, ty, *a, c, i).is_some())
                    })
        }
        _ => !records::is_mem(lay, ty),
    }
}

/// The record in memory that field `i` of case `c` of `alt` (of type `ty`) is, when its leaves
/// can move between the record's memory and the enum's slots as they are: each slot holds the
/// leaf's memory type, or an `i64` for a narrow integer, or an `i1` for a byte.
fn mem_field(lay: &Layouts, ty: Ty, alt: AltId, c: usize, i: usize) -> Option<Ty> {
    let (fty, idx) = lay.alt_fields(alt)[c][i].clone();
    if !records::is_mem(lay, fty) {
        return None;
    }
    let (slots, mem) = (held_leaves(lay, ty), mem_leaves(lay, fty));
    let fits = |slot: &LTy, mem: &LTy| {
        slot == mem
            || matches!(
                (slot, mem),
                (LTy::I64, LTy::I8 | LTy::I16 | LTy::I32) | (LTy::I1, LTy::I8)
            )
    };
    idx.iter()
        .zip(&mem)
        .all(|(k, m)| fits(&slots[*k], m))
        .then_some(fty)
}

/// The constant zero of a held type.
fn zero(t: &LTy) -> Val {
    match t {
        LTy::I1 => Val::bool(false),
        LTy::I8 => Val::byte(0),
        LTy::F64 => Val::double(0),
        LTy::Ptr => Val::new("null", LTy::Ptr),
        _ => Val::int(0),
    }
}

/// `v` as `to`: a payload leaf between the type it is held as and the slot it lives in.
fn convert(b: &mut FnBuilder, v: &Val, to: &LTy) -> Val {
    match (&v.ty, to) {
        (a, b_) if a == b_ => v.clone(),
        (LTy::I1, LTy::I8) => b.zext(v, LTy::I8),
        (LTy::I8, LTy::I1) => b.icmp("ne", v, &Val::byte(0)),
        (LTy::Ptr, LTy::I64) => b.ptrtoint(v),
        (LTy::I64, LTy::Ptr) => b.inttoptr(v),
        (a, t) => unreachable!("no conversion from {a:?} to {t:?}"),
    }
}

/// The optional or enum operand or result the op works on.
fn subject(f: &Func, inst: &Inst) -> Ty {
    match inst.op {
        Op::OptSome | Op::OptView | Op::OptNone | Op::AltNew | Op::AltView => {
            f.ty(inst.res.expect("a result"))
        }
        _ => f.ty(inst.args[0]),
    }
}

fn inst_ok(m: &Module, lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    // Dropping a record in memory would need its address, which no slot holds.
    plain(lay, subject(f, inst))
        && dropped(m, lay, inst)
            .iter()
            .all(|(t, _)| !records::is_mem(lay, *t))
}

/// The leaves a payload read or write moves between a field and the enum's slots: for each
/// result leaf (a read) or slot (a write), the slot or field leaf it comes from.
fn sources(lay: &Layouts, inst: &Inst, vals: &Vals) -> Vec<(usize, Val)> {
    let arg = |i: usize| &vals[&inst.args[i].index()];
    match (inst.op, inst.imm) {
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            let mut out = Vec::new();
            for (i, (t, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                // A record in memory is loaded in `emit`, not moved leaf by leaf.
                if !records::is_mem(lay, *t) {
                    out.extend(idx.iter().copied().zip(arg(i).iter().cloned()));
                }
            }
            out
        }
        (Op::AltGet | Op::AltTake | Op::AltUnbox, Imm::AltField(a, c, i)) => {
            let (t, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            if records::is_mem(lay, *t) {
                return Vec::new();
            }
            idx.iter()
                .enumerate()
                .map(|(j, k)| (j, arg(0)[*k].clone()))
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
    // A payload that is a record in memory comes out as a new slot, which `emit` fills.
    if matches!(inst.op, Op::AltGet | Op::AltTake | Op::AltUnbox)
        && inst.res.is_some_and(|r| records::is_mem(lay, f.ty(r)))
    {
        return None;
    }
    let mut out = match (inst.op, inst.imm) {
        (Op::OptSome | Op::OptView, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Tagged => std::iter::once(Val::bool(true))
                .chain(arg(0).iter().cloned())
                .collect(),
            _ => arg(0).clone(),
        },
        (Op::OptNone, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Str => vec![Val::int(0), Val::int(ms_rt_abi::STR_STATIC as i64)],
            _ => held_leaves(lay, res_ty()).iter().map(zero).collect(),
        },
        (Op::OptIsSome, _) if opt_repr(lay, f.ty(inst.args[0])) == OptRepr::Tagged => {
            vec![arg(0)[0].clone()]
        }
        (Op::OptGet | Op::OptUnbox, _) => match opt_repr(lay, f.ty(inst.args[0])) {
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
        (Op::AltGet | Op::AltTake | Op::AltUnbox, Imm::AltField(a, c, i)) => {
            let (fty, _) = lay.alt_fields(a)[c as usize][i as usize];
            held_leaves(lay, fty)
                .into_iter()
                .map(|t| zero(&t))
                .collect()
        }
        (Op::AltRelease, _) => return Some(vec![]),
        _ => return None,
    };
    // Payload leaves: the source itself when its type matches, else a name `emit` defines.
    let held = inst.res.map(|r| held_leaves(lay, f.ty(r)));
    for (i, src) in sources(lay, inst, vals) {
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
            if records::is_mem(lay, *t) {
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
    release(cx, inst, vals, b);
    let Some(res) = inst.res else { return };
    let out = &vals[&res.index()];
    if inst.op == Op::OptIsSome && opt_repr(cx.lay, cx.f.ty(inst.args[0])) != OptRepr::Tagged {
        let v = &vals[&inst.args[0].index()];
        let any = match opt_repr(cx.lay, cx.f.ty(inst.args[0])) {
            OptRepr::Str => {
                let t = b.bin(Bin::Xor, &v[1], &Val::int(ms_rt_abi::STR_STATIC as i64));
                b.bin(Bin::Or, &v[0], &t)
            }
            OptRepr::Nullable => v[0].clone(),
            OptRepr::Tagged => unreachable!("checked above"),
        };
        b.name_next(&out[0]);
        b.icmp("ne", &any, &zero(&any.ty));
        return;
    }
    for (i, src) in sources(cx.lay, inst, vals) {
        if out[i] != src {
            b.name_next(&out[i]);
            convert(b, &src, &out[i].ty);
        }
    }
    memory_payloads(cx, inst, vals, out, b);
}

/// A payload that is a record in memory: loaded from its address into the enum's slots for a new
/// enum, or stored from the slots into a new slot for a read.
fn memory_payloads(cx: &Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let lay = cx.lay;
    match (inst.op, inst.imm) {
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            for (i, (t, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                if records::is_mem(lay, *t) {
                    let named: Vec<Val> = idx.iter().map(|k| out[*k].clone()).collect();
                    let at = &vals[&inst.args[i].index()][0];
                    records::load_into_leaves(b, lay, *t, at, &named);
                }
            }
        }
        (Op::AltGet | Op::AltTake | Op::AltUnbox, Imm::AltField(a, c, i)) => {
            let (t, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            if records::is_mem(lay, *t) {
                let slots = &vals[&inst.args[0].index()];
                let leaves: Vec<Val> = idx.iter().map(|k| slots[*k].clone()).collect();
                records::store_into_slot(b, lay, *t, &out[0], &leaves);
            }
        }
        _ => {}
    }
}

/// The case, kept field and moved-out mask of an op that drops payload fields.
fn released(inst: &Inst) -> Option<(AltId, u32, Option<u32>, u32)> {
    match (inst.op, inst.imm) {
        (Op::AltRelease, Imm::AltMask(a, c, mask)) => Some((a, c, None, mask)),
        (Op::AltUnbox, Imm::AltField(a, c, i)) => Some((a, c, Some(i), 0)),
        _ => None,
    }
}

/// The payload fields `released` drops: those that need it and were neither moved out nor kept.
fn dropped(m: &Module, lay: &Layouts, inst: &Inst) -> Vec<(Ty, Vec<usize>)> {
    let Some((a, c, keep, mask)) = released(inst) else {
        return Vec::new();
    };
    lay.alt_fields(a)[c as usize]
        .iter()
        .enumerate()
        .filter(|(k, (t, _))| mask >> k & 1 == 0 && keep != Some(*k as u32) && m.needs_drop(*t))
        .map(|(_, (t, idx))| (*t, idx.clone()))
        .collect()
}

/// Each dropped field splits once if it is a string (`glue::drop_splits`).
fn splits(lay: &Layouts, _: &Func, inst: &Inst, _: bool) -> usize {
    dropped(lay.m, lay, inst)
        .iter()
        .map(|(t, _)| super::glue::drop_splits(lay, *t))
        .sum()
}

/// Drops the payload fields an `alt.release` or `alt.unbox` does not keep: each field's slots
/// converted to its held leaves, then the glue drop.
fn release(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    if released(inst).is_none() {
        return;
    }
    let slots = &vals[&inst.args[0].index()];
    for (t, idx) in dropped(cx.m, cx.lay, inst) {
        let held = held_leaves(cx.lay, t);
        let leaves = idx
            .iter()
            .zip(&held)
            .map(|(k, h)| convert(b, &slots[*k], h))
            .collect();
        super::glue::drop_held(cx, t, leaves, b);
    }
}

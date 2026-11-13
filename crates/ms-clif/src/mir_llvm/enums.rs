//! Enums and optionals: tags, payloads and construction.
//!
//! An optional or an enum that does not hold itself is its leaves: a tag (or an `i1` presence flag,
//! or a null `ptr`) and payload slots. Construction, tag reads and payload reads mostly choose
//! leaves, so they write no instruction. An enum's payload slots are shared between cases, so a
//! slot is a plain `i64`, `double` or `i8`: a `ptr` or `i1` payload converts at the boundary, one
//! cast each. `opt.is_some` of a niche optional is one comparison. Types behind a pointer
//! (self-containing) and payloads that are records in memory stay on the translation.

use super::{Area, Cx, Vals, glue, held_leaves, records};
use crate::glue_llvm::{OwnKind, own_kind};
use crate::layout::Layouts;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    splits,
    pure_op: |op| handles(op) && op != Op::OptUnwrap,
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
            | Op::OptNone
            | Op::OptIsSome
            | Op::OptGet
            | Op::OptUnwrap
            | Op::OptAddr
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
                    .all(|c| c.fields.iter().all(|f| plain(lay, f.1)))
        }
        _ => !records::is_mem(lay, ty),
    }
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
    // The address of a boxed optional's payload is the optional itself, a nullable pointer.
    if inst.op == Op::OptAddr {
        return opt_repr(lay, f.ty(inst.args[0])) == OptRepr::Nullable;
    }
    if !plain(lay, subject(f, inst)) {
        return false;
    }
    // Payload fields that are neither moved out nor kept would be dropped, which needs glue.
    let droppable = |a, c, keep: Option<u32>, mask: u32| {
        lay.alt_fields(a)[c as usize]
            .iter()
            .enumerate()
            .all(|(k, (t, _))| mask >> k & 1 == 1 || keep == Some(k as u32) || !m.needs_drop(*t))
    };
    match (inst.op, inst.imm) {
        (Op::AltRelease, Imm::AltMask(a, c, mask)) => droppable(a, c, None, mask),
        (Op::AltUnbox, Imm::AltField(a, c, i)) => droppable(a, c, Some(i), 0),
        _ => true,
    }
}

/// The payload type of the optional `inst` unwraps.
fn payload_ty(lay: &Layouts, f: &Func, inst: &Inst) -> Ty {
    match lay.m.types.kind(f.ty(inst.args[0])) {
        TyKind::Opt(inner) => *inner,
        _ => unreachable!("an optional operand"),
    }
}

/// Whether `inst` writes a check before it, and then the clone of a payload that needs one:
/// each is a block split.
fn splits(lay: &Layouts, f: &Func, inst: &Inst, checks: bool) -> usize {
    if inst.op != Op::OptUnwrap {
        return 0;
    }
    let clone = own_kind(lay, payload_ty(lay, f, inst)) == OwnKind::Str;
    usize::from(checks) + usize::from(clone)
}

/// The leaves a payload read or write moves between a field and the enum's slots: for each
/// result leaf (a read) or slot (a write), the slot or field leaf it comes from.
fn sources(lay: &Layouts, inst: &Inst, vals: &Vals) -> Vec<(usize, Val)> {
    let arg = |i: usize| &vals[&inst.args[i].index()];
    match (inst.op, inst.imm) {
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            let mut out = Vec::new();
            for (i, (_, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                out.extend(idx.iter().copied().zip(arg(i).iter().cloned()));
            }
            out
        }
        (Op::AltGet | Op::AltTake | Op::AltUnbox, Imm::AltField(a, c, i)) => {
            let (_, idx) = &lay.alt_fields(a)[c as usize][i as usize];
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
        (Op::OptAddr, _) => arg(0).clone(),
        (Op::OptUnwrap, _) if own_kind(lay, payload_ty(lay, f, inst)) != OwnKind::Identity => {
            return None;
        }
        (Op::OptGet | Op::OptUnwrap | Op::OptUnbox, _) => match opt_repr(lay, f.ty(inst.args[0])) {
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
    Some(out)
}

/// Defines the reserved leaves `pre` left: a payload leaf converted to or from its slot, and the
/// presence of a niche optional, which is present unless its first leaf is null (a string also
/// has the static tag: an inline string may have a zero first word, but never that tag).
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let Some(res) = inst.res else { return };
    let out = &vals[&res.index()];
    if inst.op == Op::OptUnwrap {
        unwrap(cx, inst, vals, out, b);
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
    for (i, src) in sources(cx.lay, inst, vals) {
        if out[i] != src {
            b.name_next(&out[i]);
            convert(b, &src, &out[i].ty);
        }
    }
}

/// Whether the niche or tagged optional `v` of type `ty` is present, as an `i1`.
fn present(b: &mut FnBuilder, lay: &Layouts, ty: Ty, v: &[Val]) -> Val {
    if opt_repr(lay, ty) == OptRepr::Tagged {
        return v[0].clone();
    }
    let any = niche_any(b, lay, ty, v);
    b.icmp("ne", &any, &zero(&any.ty))
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

/// `opt.unwrap`: faults on none when checks are on, then yields an owned payload: the leaves
/// themselves when they own nothing (`pre` chose them), else a clone.
fn unwrap(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let ty = cx.f.ty(inst.args[0]);
    let v = &vals[&inst.args[0].index()];
    if cx.checks {
        let some = present(b, cx.lay, ty, v);
        let none = b.icmp("eq", &some, &Val::bool(false));
        super::faults::fault_if(cx, b, &none, "msrt_fault_unwrap_none", &[]);
    }
    let inner = payload_ty(cx.lay, cx.f, inst);
    if own_kind(cx.lay, inner) == OwnKind::Identity {
        return;
    }
    let payload = match opt_repr(cx.lay, ty) {
        OptRepr::Tagged => &v[1..],
        _ => &v[..],
    };
    glue::clone_leaves(cx, inner, payload, out, b);
}

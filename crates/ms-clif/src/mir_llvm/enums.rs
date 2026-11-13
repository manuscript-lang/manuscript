//! Enums and optionals: tags, payloads and construction.
//!
//! An optional or an enum that does not hold itself is its leaves: a tag (or presence flag, or
//! null) and payload slots. Construction, tag reads and payload reads only choose leaves, so they
//! write no instruction; `opt.is_some` of a niche optional is one comparison. Types behind a
//! pointer (self-containing) need allocation and stay on the translation.

use super::{Area, Cx, Vals};
use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    pure_op: handles,
    pre,
    emit,
    ..Area::NONE
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
    /// `present: i8`, then the payload's leaves.
    Tagged,
    /// A nullable pointer or handle: the payload itself, zero for none.
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

/// Whether `ty` (an optional or an enum) lives behind a pointer.
fn behind_pointer(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Opt(inner) => lay.opt_is_boxed(*inner),
        TyKind::Alt(a) => lay.is_boxed(*a),
        _ => false,
    }
}

/// The constant zero of a register leaf.
fn zero(l: Leaf) -> Val {
    match super::leaf(l).0 {
        LTy::F64 => Val::double(0),
        LTy::I8 => Val::byte(0),
        _ => Val::int(0),
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
    if behind_pointer(lay, subject(f, inst)) {
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

/// The values of an op that only rearranges or names leaves, so it writes no instruction.
fn rearrange(lay: &Layouts, f: &Func, inst: &Inst, vals: &Vals) -> Option<Vec<Val>> {
    let arg = |i: usize| &vals[&inst.args[i].index()];
    let res_ty = || f.ty(inst.res.expect("a result"));
    Some(match (inst.op, inst.imm) {
        (Op::OptSome | Op::OptView, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Tagged => std::iter::once(Val::byte(1))
                .chain(arg(0).iter().cloned())
                .collect(),
            _ => arg(0).clone(),
        },
        (Op::OptNone, _) => match opt_repr(lay, res_ty()) {
            OptRepr::Str => vec![Val::int(0), Val::int(ms_rt_abi::STR_STATIC as i64)],
            _ => lay.leaves(res_ty()).into_iter().map(zero).collect(),
        },
        (Op::OptIsSome, _) if opt_repr(lay, f.ty(inst.args[0])) == OptRepr::Tagged => {
            vec![arg(0)[0].clone()]
        }
        (Op::OptGet | Op::OptUnbox, _) => match opt_repr(lay, f.ty(inst.args[0])) {
            OptRepr::Tagged => arg(0)[1..].to_vec(),
            _ => arg(0).clone(),
        },
        (Op::AltNew | Op::AltView, Imm::Case(a, c)) => {
            let mut out: Vec<Val> = lay.leaves(res_ty()).into_iter().map(zero).collect();
            out[0] = Val::int(c as i64);
            for (i, (_, idx)) in lay.alt_fields(a)[c as usize].iter().enumerate() {
                for (k, v) in idx.iter().zip(arg(i)) {
                    out[*k] = v.clone();
                }
            }
            out
        }
        (Op::AltPlain, _) => arg(0).clone(),
        (Op::AltTag, _) => vec![arg(0)[0].clone()],
        (Op::AltGet | Op::AltTake | Op::AltUnbox, Imm::AltField(a, c, i)) => {
            let (_, idx) = &lay.alt_fields(a)[c as usize][i as usize];
            idx.iter().map(|k| arg(0)[*k].clone()).collect()
        }
        (Op::AltRelease, _) => vec![],
        _ => return None,
    })
}

fn pre(lay: &Layouts, f: &Func, inst: &Inst, vals: &Vals) -> Option<Vec<Val>> {
    rearrange(lay, f, inst, vals)
}

/// The one op here that needs code: whether a niche optional holds a value. It is present unless
/// its first leaf is null (a string also has the static tag: an inline string may have a zero
/// first word, but never that tag).
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    if rearrange(cx.lay, cx.f, inst, vals).is_some() {
        return;
    }
    let v = &vals[&inst.args[0].index()];
    let out = &vals[&inst.res.expect("a result").index()];
    let any = match opt_repr(cx.lay, cx.f.ty(inst.args[0])) {
        OptRepr::Str => {
            let t = b.bin(Bin::Xor, &v[1], &Val::int(ms_rt_abi::STR_STATIC as i64));
            b.bin(Bin::Or, &v[0], &t)
        }
        _ => v[0].clone(),
    };
    let c = b.icmp("ne", &any, &Val::int(0));
    b.name_next(&out[0]);
    b.zext(&c, LTy::I8);
}

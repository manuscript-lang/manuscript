//! Clone, drop and type descriptors: plain data is the value, strings are cloned and freed
//! inline, objects go through the runtime, and the rest call the type's glue.

use super::{Area, Cx, Vals, block_label};
use crate::glue_llvm::{OwnKind, call_clone, call_drop, clone_str, own_kind};
use crate::layout::Layouts;
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Op};
use ms_mir::types::TyKind;
use ms_rt_abi::STR_INLINE;

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok: |_, _, _, _| true,
    splits,
    pure_op: |_| false,
    pre,
    emit,
};

fn handles(op: Op) -> bool {
    matches!(op, Op::Clone | Op::Drop | Op::DropIf | Op::TypeDesc)
}

/// A type descriptor is a raw address.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Ptr)
}

/// Whether `inst` branches inside its MIR block, so that what follows is in another LLVM block:
/// a string clone, a drop that frees a string conditionally, and a guarded drop.
fn splits(lay: &Layouts, f: &Func, i: &Inst, _: bool) -> usize {
    let split = match i.op {
        Op::Clone | Op::Drop => own_kind(lay, f.ty(i.args[0])) == OwnKind::Str,
        Op::DropIf => own_kind(lay, f.ty(i.args[1])) != OwnKind::Identity,
        _ => false,
    };
    usize::from(split)
}

/// Cloning plain data is the value itself.
fn pre(lay: &Layouts, f: &Func, inst: &Inst, vals: &Vals) -> Option<Vec<Val>> {
    let plain = inst.op == Op::Clone && own_kind(lay, f.ty(inst.args[0])) == OwnKind::Identity;
    plain.then(|| vals[&inst.args[0].index()].clone())
}

/// The declaration of a runtime function that takes one address-sized word and returns nothing.
fn rt_decl(name: &str) -> (String, String) {
    (
        name.into(),
        format!("declare void @\"{name}\"(i64) nounwind"),
    )
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    match inst.op {
        Op::TypeDesc => {
            let Imm::Ty(t) = inst.imm else { return };
            let sym = &cx.plan.desc[&t];
            cx.data.push(sym.clone());
            let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
            b.name_next(&out[0]);
            b.ptrtoint(&addr);
        }
        Op::Clone => clone(cx, inst, vals, &out, b),
        _ => drop_inst(cx, inst, vals, b),
    }
}

fn clone(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let ty = cx.f.ty(inst.args[0]);
    let args = &vals[&inst.args[0].index()];
    match own_kind(cx.lay, ty) {
        // `pre` gave the result the operand's own values.
        OwnKind::Identity => {}
        OwnKind::Str => {
            let pre = block_label(cx.block, cx.split);
            let dup = format!("b{}.d{}", cx.block, cx.split);
            cx.split += 1;
            let join = block_label(cx.block, cx.split);
            clone_str(b, &mut cx.decls, (&pre, &dup, &join), args, Some(out));
        }
        OwnKind::Obj => {
            cx.decls.push((
                "msrt_obj_clone".into(),
                "declare i64 @\"msrt_obj_clone\"(i64) nounwind".into(),
            ));
            b.name_next(&out[0]);
            b.call(&LTy::I64, "", "msrt_obj_clone", &[(args[0].clone(), "")]);
        }
        OwnKind::Glue => {
            let sym = &cx.plan.clone[&ty];
            call_clone(b, &mut cx.decls, cx.lay, sym, ty, args, Some(out));
        }
    }
}

fn drop_inst(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let guarded = inst.op == Op::DropIf;
    let ty = cx.f.ty(inst.args[usize::from(guarded)]);
    let kind = own_kind(cx.lay, ty);
    if kind == OwnKind::Identity {
        return;
    }
    let args = &vals[&inst.args[usize::from(guarded)].index()];
    let (block, at) = (cx.block, cx.split);
    cx.split += 1;
    let join = block_label(block, cx.split);
    let mut n = 0;
    let mut fresh = |what: &str| {
        n += 1;
        format!("b{block}.{what}{at}.{n}")
    };
    if guarded {
        let on = b.icmp("ne", &vals[&inst.args[0].index()][0], &Val::byte(0));
        let then = fresh("t");
        b.cond_br(&on, &then, &join);
        b.label(&then);
    }
    match kind {
        OwnKind::Str => {
            // Only an owned string (tag `00`) frees anything.
            let owned = b.icmp("ult", &args[1], &Val::int(STR_INLINE as i64));
            let (free, cont) = (fresh("f"), if guarded { fresh("c") } else { join.clone() });
            b.cond_br(&owned, &free, &cont);
            b.label(&free);
            cx.decls.push(rt_decl("msrt_str_free"));
            b.call(&LTy::Void, "", "msrt_str_free", &[(args[0].clone(), "")]);
            b.br(&cont);
            b.label(&cont);
        }
        OwnKind::Obj => {
            cx.decls.push(rt_decl("msrt_obj_drop"));
            b.call(&LTy::Void, "", "msrt_obj_drop", &[(args[0].clone(), "")]);
        }
        _ => {
            let sym = &cx.plan.drop[&ty];
            call_drop(b, &mut cx.decls, cx.lay, sym, ty, args);
        }
    }
    if guarded {
        b.br(&join);
        b.label(&join);
    }
}

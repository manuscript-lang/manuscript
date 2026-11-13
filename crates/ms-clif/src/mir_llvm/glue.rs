//! Clone, drop, moves, cleanups and type descriptors: plain data is the value, strings are cloned and freed
//! inline, objects go through the runtime, and the rest call the type's glue.

use super::calls::{Callee, finish_call};
use super::records::{abi_leaves, is_mem, load_result, result_slot, spill};
use super::{Area, Cx, Vals, block_label, call_ret_ty, leaves, ret_attr};
use crate::glue_llvm::{GlueCall, OwnKind, clone_callee, clone_str, drop_callee, own_kind};
use crate::layout::Layouts;
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op, Value};
use ms_mir::types::Ty;
use ms_mir::types::TyKind;
use ms_rt_abi::STR_INLINE;

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    splits,
    pure_op: |_| false,
    pre,
    emit,
};

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::Clone
            | Op::Drop
            | Op::DropIf
            | Op::MoveOut
            | Op::TypeDesc
            | Op::CleanupPush
            | Op::CleanupRun
    )
}

/// A cleanup is registered with a copy of its value, which a record in memory would not be, and
/// only while a guarded task unwinds when it is `unwind_only`; both stay with the translation.
fn inst_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    let (Op::CleanupPush, Imm::Func(c)) = (i.op, i.imm) else {
        return true;
    };
    !m.funcs[c.index()].unwind_only && !is_mem(lay, f.ty(i.args[0]))
}

/// A type descriptor is a raw address.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Ptr)
}

/// Whether `inst` branches inside its MIR block, so that what follows is in another LLVM block:
/// a string clone, and any drop that is not plain data (`drop_inst` takes a split for each).
fn splits(lay: &Layouts, f: &Func, i: &Inst, _: bool) -> usize {
    let split = match i.op {
        Op::Clone => own_kind(lay, f.ty(i.args[0])) == OwnKind::Str,
        Op::Drop => own_kind(lay, f.ty(i.args[0])) != OwnKind::Identity,
        Op::DropIf => own_kind(lay, f.ty(i.args[1])) != OwnKind::Identity,
        _ => false,
    };
    usize::from(split)
}

/// Cloning plain data and moving a value out are the value itself.
fn pre(
    _: &Module,
    lay: &Layouts,
    f: &Func,
    inst: &Inst,
    vals: &Vals,
    _: &mut FnBuilder,
) -> Option<Vec<Val>> {
    let same = match inst.op {
        Op::MoveOut => true,
        Op::Clone => own_kind(lay, f.ty(inst.args[0])) == OwnKind::Identity,
        _ => false,
    };
    same.then(|| vals[&inst.args[0].index()].clone())
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
            b.elem_ptr(&LTy::I8, &addr, &Val::int(0));
        }
        // The moved value is the operand itself: nothing to write.
        Op::MoveOut => {}
        Op::Clone => clone(cx, inst, vals, &out, b),
        Op::CleanupPush => cleanup_push(cx, inst, vals, &out, b),
        Op::CleanupRun => {
            cx.decls.push(rt_decl("msrt_cleanup_run"));
            let h = vals[&inst.args[0].index()][0].clone();
            b.call(&LTy::Void, "", "msrt_cleanup_run", &[(h, "")]);
        }
        _ => drop_inst(cx, inst, vals, b),
    }
}

/// Registers the cleanup `c` for the value: the runtime keeps the address of a copy of its leaves
/// and the address of the glue thunk that closes it, and hands back the handle `CleanupRun` takes.
fn cleanup_push(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let Imm::Func(c) = inst.imm else { return };
    let slot = spill(b, cx.lay, cx.f.ty(inst.args[0]), vals, inst.args[0]);
    let slot = b.ptr_to_int(&slot);
    let thunk = Val::new(format!("@\"{}\"", cx.plan.cleanup[&c.index()]), LTy::Ptr);
    let thunk = b.ptr_to_int(&thunk);
    cx.decls.push((
        "msrt_cleanup_push".into(),
        "declare i64 @\"msrt_cleanup_push\"(i64, i64) nounwind".into(),
    ));
    b.name_next(&out[0]);
    b.call(
        &LTy::I64,
        "",
        "msrt_cleanup_push",
        &[(thunk, ""), (slot, "")],
    );
}

/// A pointer leaf as the address word the runtime takes.
fn word(b: &mut FnBuilder, v: &Val) -> Val {
    if v.ty == LTy::Ptr {
        b.ptr_to_int(v)
    } else {
        v.clone()
    }
}

/// The leaves of `v` in the leaf convention, each with its attributes.
fn leaf_args(
    b: &mut FnBuilder,
    cx: &Cx,
    ty: Ty,
    vals: &Vals,
    v: Value,
) -> Vec<(Val, &'static str)> {
    abi_leaves(b, cx.lay, ty, vals, v, false)
        .into_iter()
        .zip(leaves(cx.lay, ty))
        .map(|(x, (_, a))| (x, a))
        .collect()
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
            let obj = word(b, &args[0]);
            if out[0].ty == LTy::Ptr {
                let r = b.call(&LTy::I64, "", "msrt_obj_clone", &[(obj, "")]);
                b.name_next(&out[0]);
                b.int_to_ptr(&r.expect("result"));
            } else {
                b.name_next(&out[0]);
                b.call(&LTy::I64, "", "msrt_obj_clone", &[(obj, "")]);
            }
        }
        OwnKind::Glue => {
            let v = inst.args[0];
            let target = cx.plan.clone[&ty].clone();
            match clone_callee(cx.lay, ty, &target, &mut cx.decls) {
                GlueCall::Memory(n) => {
                    let src = spill(b, cx.lay, ty, vals, v);
                    let dst = result_slot(b, cx.lay, ty, out);
                    b.call(&LTy::Void, "", &n, &[(dst.clone(), ""), (src, "")]);
                    load_result(b, cx.lay, ty, &dst, out);
                }
                GlueCall::Regs(n) => {
                    let args = leaf_args(b, cx, ty, vals, v);
                    let ret = call_ret_ty(cx.lay, ty, false);
                    let attr = ret_attr(cx.lay, ty);
                    finish_call(
                        b,
                        cx.lay,
                        ty,
                        (&ret, attr, false),
                        Callee::Symbol(&n),
                        &args,
                        out,
                        false,
                    );
                }
            }
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
    let v = inst.args[usize::from(guarded)];
    let args = &vals[&v.index()];
    let (block, at) = (cx.block, cx.split);
    cx.split += 1;
    let join = block_label(block, cx.split);
    let mut n = 0;
    let mut fresh = |what: &str| {
        n += 1;
        format!("b{block}.{what}{at}.{n}")
    };
    if guarded {
        let on = vals[&inst.args[0].index()][0].clone();
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
            let p = word(b, &args[0]);
            b.call(&LTy::Void, "", "msrt_str_free", &[(p, "")]);
            b.br(&cont);
            b.label(&cont);
        }
        OwnKind::Obj => {
            cx.decls.push(rt_decl("msrt_obj_drop"));
            let p = word(b, &args[0]);
            b.call(&LTy::Void, "", "msrt_obj_drop", &[(p, "")]);
        }
        _ => {
            let target = cx.plan.drop[&ty].clone();
            match drop_callee(cx.lay, ty, &target, &mut cx.decls) {
                GlueCall::Memory(n) => {
                    let p = spill(b, cx.lay, ty, vals, v);
                    b.call(&LTy::Void, "", &n, &[(p, "")]);
                }
                GlueCall::Regs(n) => {
                    let args = leaf_args(b, cx, ty, vals, v);
                    b.call(&LTy::Void, "", &n, &args);
                }
            }
        }
    }
    if guarded {
        b.br(&join);
        b.label(&join);
    }
}

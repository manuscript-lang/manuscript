//! Clone, drop, moves, cleanups and type descriptors: plain data is the value, strings are cloned and freed
//! inline, objects go through the runtime, and the rest call the type's glue.

use super::calls::{Callee, finish_call};
use super::types::{Abi, abi_leaves_of, is_mem, load_result, result_slot, spill, spill_of};
use super::{Area, Cx, Vals, block_label, call_ret_ty, leaves, ret_attr};
use crate::glue_llvm::{GlueCall, OwnKind, clone_callee, clone_str, drop_callee, own_kind};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op, Value};
use ms_mir::layout::Layouts;
use ms_mir::types::Ty;
use ms_mir::types::TyKind;
use ms_rt_abi::STR_INLINE;
use ms_rt_abi::symbols::ISOLATE_HDR_GUARDED;

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
            | Op::AltOwn
            | Op::Drop
            | Op::DropIf
            | Op::MoveOut
            | Op::TypeDesc
            | Op::CleanupPush
            | Op::CleanupRun
    )
}

fn inst_ok(_: &Module, _: &Layouts, _: &Func, _: &Inst) -> bool {
    true
}

/// A type descriptor is a raw address.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Ptr)
}

/// Whether `inst` branches inside its MIR block, so that what follows is in another LLVM block:
/// a string clone, a drop of a string, and a guarded drop of anything but plain data. An unguarded
/// drop of an object or glue is one call and splits nothing.
/// A closer that only acts while a guarded task unwinds.
fn unwind_only(m: &Module, i: &Inst) -> bool {
    matches!(i.imm, Imm::Func(c) if m.funcs[c.index()].unwind_only)
}

fn splits(lay: &Layouts, f: &Func, i: &Inst, _: bool) -> usize {
    let split = match i.op {
        Op::CleanupPush => unwind_only(lay.m, i),
        Op::Clone | Op::AltOwn => own_kind(lay, cloned_ty(f, i)) == OwnKind::Str,
        Op::Drop => own_kind(lay, f.ty(i.args[0])) == OwnKind::Str,
        Op::DropIf => own_kind(lay, f.ty(i.args[1])) != OwnKind::Identity,
        _ => false,
    };
    usize::from(split)
}

/// The type a `Clone` or `AltOwn` copies: `alt.own` copies a borrowing alternative as the ordinary
/// one it produces, which has the same leaves.
pub(crate) fn cloned_ty(f: &Func, i: &Inst) -> Ty {
    match i.op {
        Op::AltOwn => f.ty(i.res.expect("alt.own result")),
        _ => f.ty(i.args[0]),
    }
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
        Op::Clone | Op::AltOwn => own_kind(lay, cloned_ty(f, inst)) == OwnKind::Identity,
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
        Op::Clone | Op::AltOwn => {
            let ty = cloned_ty(cx.f, inst);
            clone_leaves(cx, ty, &vals[&inst.args[0].index()], &out, b);
        }
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
/// A closer that only acts while a guarded task unwinds registers nothing, and hands back handle 0
/// (which discarding skips), when no guard is open.
fn cleanup_push(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let Imm::Func(c) = inst.imm else { return };
    let guard = unwind_only(cx.m, inst).then(|| {
        let hdr = super::depth::task_hdr(b);
        let at = b.gep_bytes(&hdr, ISOLATE_HDR_GUARDED as u64);
        let guarded = b.load(&LTy::I8, &at, 1);
        let on = b.icmp("ne", &guarded, &Val::byte(0));
        let (head, then) = (
            block_label(cx.block, cx.split),
            format!("u{}_{}", cx.block, cx.split),
        );
        cx.split += 1;
        let join = block_label(cx.block, cx.split);
        b.cond_br(&on, &then, &join);
        b.label(&then);
        (head, then, join)
    });
    let ty = cx.f.ty(inst.args[0]);
    let slot = if is_mem(cx.lay, ty) {
        // The runtime keeps the address, so it is a copy the type's own slot cannot change.
        let s = super::types::shape(b.types(), cx.lay, ty).expect("a type has a shape");
        let copy = b.alloca(&s.st);
        b.copy_bytes(
            &copy,
            &vals[&inst.args[0].index()][0],
            s.size as u64,
            s.align as u64,
        );
        copy
    } else {
        spill(b, cx.lay, ty, vals, inst.args[0])
    };
    let slot = b.ptr_to_int(&slot);
    let thunk = Val::new(format!("@\"{}\"", cx.plan.cleanup[&c.index()]), LTy::Ptr);
    let thunk = b.ptr_to_int(&thunk);
    super::rt::declare(cx, "msrt_cleanup_push");
    let Some((head, then, join)) = guard else {
        b.name_next(&out[0]);
        b.call(
            &LTy::I64,
            "",
            "msrt_cleanup_push",
            &[(thunk, ""), (slot, "")],
        );
        return;
    };
    let h = b
        .call(
            &LTy::I64,
            "",
            "msrt_cleanup_push",
            &[(thunk, ""), (slot, "")],
        )
        .expect("a handle");
    b.br(&join);
    b.label(&join);
    b.phi(&out[0], &[(Val::int(0), head), (h, then)]);
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
fn leaf_args(b: &mut FnBuilder, cx: &Cx, ty: Ty, own: &[Val]) -> Vec<(Val, &'static str)> {
    abi_leaves_of(b, cx.lay, ty, own, Abi::Leaf)
        .into_iter()
        .zip(leaves(cx.lay, ty))
        .map(|(x, (_, a))| (x, a))
        .collect()
}

/// Writes the clone of the held values `args` of a `ty` into `out`.
pub(super) fn clone_leaves(cx: &mut Cx, ty: Ty, args: &[Val], out: &[Val], b: &mut FnBuilder) {
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
            super::rt::declare(cx, "msrt_obj_clone");
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
            let target = cx.plan.clone[&ty].clone();
            match clone_callee(cx.lay, ty, &target, &mut cx.decls) {
                GlueCall::Memory(n) => {
                    let src = spill_of(b, cx.lay, ty, args);
                    let dst = result_slot(b, cx.lay, ty, out);
                    b.call(&LTy::Void, "", &n, &[(dst.clone(), ""), (src, "")]);
                    load_result(b, cx.lay, ty, &dst, out);
                }
                GlueCall::Regs(n) => {
                    let args = leaf_args(b, cx, ty, args);
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
    let v = inst.args[usize::from(guarded)];
    let ty = cx.f.ty(v);
    let on = guarded.then(|| vals[&inst.args[0].index()][0].clone());
    drop_value(cx, ty, v, on, vals, b);
}

/// Drops the value of type `ty` held as `held` (its leaves), for a payload an alternative releases.
pub(super) fn drop_held(cx: &mut Cx, ty: Ty, held: Vec<Val>, b: &mut FnBuilder) {
    let v = Value(0);
    let vals = Vals::from([(v.index(), held)]);
    drop_value(cx, ty, v, None, &vals, b);
}

/// How many blocks dropping a value of type `ty` splits off when unguarded: a string's check.
pub(super) fn drop_splits(lay: &Layouts, ty: Ty) -> usize {
    usize::from(own_kind(lay, ty) == OwnKind::Str)
}

/// Drops the value `v` of type `ty`, only when `on` is true if it is given. `splits` counts the
/// blocks this starts: one for a guard, one for a string's check.
pub(super) fn drop_value(
    cx: &mut Cx,
    ty: Ty,
    v: Value,
    on: Option<Val>,
    vals: &Vals,
    b: &mut FnBuilder,
) {
    let guarded = on.is_some();
    let kind = own_kind(cx.lay, ty);
    if kind == OwnKind::Identity {
        return;
    }
    let (block, at) = (cx.block, cx.split);
    // Only a drop that branches starts a new block (`splits` counts the same ones).
    cx.split += usize::from(guarded || kind == OwnKind::Str);
    let join = block_label(block, cx.split);
    let mut n = 0;
    let mut fresh = |what: &str| {
        n += 1;
        format!("b{block}.{what}{at}.{n}")
    };
    if let Some(on) = on {
        let then = fresh("t");
        b.cond_br(&on, &then, &join);
        b.label(&then);
    }
    let (free, cont) = (fresh("f"), if guarded { fresh("c") } else { join.clone() });
    drop_core(cx, b, ty, vals, v, &free, &cont);
    if guarded {
        b.br(&join);
        b.label(&join);
    }
}

/// Drops the value `v` of `ty`. A string branches: it frees in block `free` and continues in
/// block `cont`, which this leaves as the current block; any other type is straight-line code.
fn drop_core(
    cx: &mut Cx,
    b: &mut FnBuilder,
    ty: Ty,
    vals: &Vals,
    v: Value,
    free: &str,
    cont: &str,
) {
    let args = &vals[&v.index()];
    match own_kind(cx.lay, ty) {
        OwnKind::Str => {
            // Only an owned string (tag `00`) frees anything.
            let owned = b.icmp("ult", &args[1], &Val::int(STR_INLINE as i64));
            b.cond_br(&owned, free, cont);
            b.label(free);
            cx.decls.push(rt_decl("msrt_str_free"));
            let p = word(b, &args[0]);
            b.call(&LTy::Void, "", "msrt_str_free", &[(p, "")]);
            b.br(cont);
            b.label(cont);
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
                    let args = leaf_args(b, cx, ty, args);
                    b.call(&LTy::Void, "", &n, &args);
                }
            }
        }
    }
}

/// Drops a value of `ty` held as `leaves`, as `drop` does. A string needs two blocks: when it
/// returns `true` the code is in the fresh block `cont` (the caller counts one split), else in the
/// block it started in.
pub(super) fn drop_leaves(
    cx: &mut Cx,
    b: &mut FnBuilder,
    ty: Ty,
    leaves: &[Val],
    (free, cont): (&str, &str),
) -> bool {
    if own_kind(cx.lay, ty) == OwnKind::Identity {
        return false;
    }
    let v = Value(u32::MAX);
    let vals: Vals = [(v.index(), leaves.to_vec())].into();
    drop_core(cx, b, ty, &vals, v, free, cont);
    own_kind(cx.lay, ty) == OwnKind::Str
}

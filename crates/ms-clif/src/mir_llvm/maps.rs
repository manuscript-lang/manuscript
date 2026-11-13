//! Maps, sets and interfaces.
//!
//! An interface is two pointers: the data and the vtable address, whose low two bits tell who
//! frees the box (1 the box, 2 nothing, 0 a static value). `iface.new` and `iface.borrow` store
//! the payload into one typed block (a heap block, or an `alloca` when the value cannot leave the
//! frame) and form the vtable word as a `getelementptr` into the vtable constant, so LLVM still
//! sees which vtable it is. `call.method` clears the tag with `llvm.ptrmask`, loads the slot as an
//! invariant, non-null, 8-aligned pointer and calls through it; when the box is built in the same
//! function, LLVM sees the constant vtable and the stack slot and devirtualizes the call.
//!
//! A `Map` or `Set` is seven words and an empty one is all zero (`ms_rt::map::empty()`, pinned by
//! a runtime test), so `map.new` is seven constants and no call. Every other map operation is a
//! runtime call.

use super::{Area, Cx, Vals, call_ret_ty, leaves, records, ret_attr};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{FnBuilder, Meta, Ty as LTy, Val};
use ms_mir::ir::{ExternRole, Func, Imm, Inst, Module, Op};
use ms_mir::types::TyKind;

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    pre,
    emit,
    ..Area::NONE
};

/// Tag of a box on the heap, freed with the value.
const BOXED: u64 = 1;
/// Tag of a borrowed box whose leaves live in the frame: nothing is freed.
const FRAMED: u64 = 2;
/// Mask that clears the tag bits.
const UNTAG: i64 = !3;

fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Iface(_)) || matches!(k, TyKind::Obj(n, _) if n.is_map_or_set())
}

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::IfaceNew
            | Op::IfaceBorrow
            | Op::IfaceView
            | Op::IfaceData
            | Op::IfaceIs
            | Op::CallMethod
            | Op::PtrIsNull
            | Op::CallRt
    )
}

/// `map_new` (and `set_new`): the only runtime call this area makes.
fn is_map_new(m: &Module, inst: &Inst) -> bool {
    matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].role == ExternRole::MapNew)
}

fn inst_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    match i.op {
        // The block holds the payload as `mem_layout` places it, which the typed struct matches
        // only for the three plain machine types.
        Op::IfaceNew | Op::IfaceBorrow => {
            let ty = f.ty(i.args[0]);
            records::is_mem(lay, ty)
                || lay
                    .leaves(ty)
                    .iter()
                    .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
        }
        Op::CallRt => is_map_new(m, i),
        _ => true,
    }
}

/// An empty map is seven zero words, and the data of an interface is a leaf of it: no code.
fn pre(lay: &Layouts, f: &Func, inst: &Inst, vals: &Vals) -> Option<Vec<Val>> {
    match inst.op {
        Op::IfaceData => Some(vec![vals[&inst.args[0].index()][0].clone()]),
        Op::CallRt => {
            let res = inst.res?;
            Some(vec![Val::int(0); lay.width(f.ty(res))])
        }
        _ => None,
    }
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    let arg = |i: usize| vals[&inst.args[i].index()].clone();
    match inst.op {
        Op::IfaceData | Op::CallRt => {}
        Op::IfaceNew | Op::IfaceBorrow => {
            let framed = inst.op == Op::IfaceBorrow
                && inst.res.is_some_and(|r| {
                    crate::lower::framed_iface_borrows(cx.m, cx.f).contains(&r.index())
                });
            let tag = match (inst.op, framed) {
                (Op::IfaceNew, _) => 0,
                (_, true) => FRAMED,
                (_, false) => BOXED,
            };
            let ty = cx.f.ty(inst.args[0]);
            let types = b.types();
            let (size, st) = if records::is_mem(cx.lay, ty) {
                let s = records::shape(types, cx.lay, ty).expect("is_mem checked");
                (u64::from(s.size), s.st)
            } else {
                let size = mem_layout(&cx.lay.leaves(ty)).size;
                (u64::from(size), super::aggregate(types, cx.lay, ty))
            };
            let block = if framed {
                b.alloca_as(&out[0], &st);
                out[0].clone()
            } else {
                cx.decls.push((
                    "msrt_alloc".into(),
                    "declare noalias align 16 ptr @\"msrt_alloc\"(i64)".into(),
                ));
                b.name_next(&out[0]);
                b.call(
                    &LTy::Ptr,
                    "noalias align 16 ",
                    "msrt_alloc",
                    &[(Val::int(size.max(8) as i64), "")],
                )
                .expect("an allocation returns a pointer")
            };
            records::store_result(b, cx.lay, ty, vals, inst.args[0], &block);
            let vt = vtable(cx, inst);
            b.name_next(&out[1]);
            b.byte_ptr(&vt, tag);
        }
        Op::IfaceView => {
            // The same data, with the vtable retagged as a view: nothing is freed.
            let v = arg(0);
            b.name_next(&out[0]);
            b.byte_ptr(&v[0], 0);
            let bare = b.ptrmask(&v[1], UNTAG);
            b.name_next(&out[1]);
            b.byte_ptr(&bare, FRAMED);
        }
        Op::IfaceIs => {
            let bare = b.ptrmask(&arg(0)[1], UNTAG);
            let want = vtable(cx, inst);
            b.name_next(&out[0]);
            b.icmp("eq", &bare, &want);
        }
        Op::PtrIsNull => {
            b.name_next(&out[0]);
            b.icmp("eq", &arg(0)[0], &Val::new("null", LTy::Ptr));
        }
        Op::CallMethod => call_method(cx, inst, vals, b),
        _ => unreachable!("handles lists the ops of this area"),
    }
}

/// The address of the vtable `inst` names, recorded as a data symbol of the function.
fn vtable(cx: &mut Cx, inst: &Inst) -> Val {
    let Imm::Vtable(vt) = inst.imm else {
        unreachable!("an interface op carries its vtable")
    };
    let sym = cx.vtables[vt.index()].clone();
    let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
    cx.data.push(sym);
    addr
}

/// A method call: the slot of the vtable, called with the data pointer first. The methods in a
/// vtable take their arguments as leaves, like any function the runtime calls, so the receiver
/// goes as the `i64` address and the rest as `abi_leaves` makes them.
fn call_method(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let Imm::Method(iface, k) = inst.imm else {
        unreachable!("a method call carries its method")
    };
    let sig = &m.ifaces[iface.index()].methods[k as usize];
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    let recv = &vals[&inst.args[0].index()];
    let bare = b.ptrmask(&recv[1], UNTAG);
    let slot = b.byte_ptr(&bare, 8 * (1 + u64::from(k)));
    let code = b.load_with(
        &LTy::Ptr,
        &slot,
        8,
        Meta {
            invariant: true,
            nonnull: true,
            align8: true,
            ..Meta::default()
        },
    );
    let data = b.ptr_to_int(&recv[0]);
    let mut args: Vec<(Val, &str)> = vec![(data, "")];
    for (p, a) in sig.params.iter().zip(&inst.args[1..]) {
        let abi = records::abi_leaves(b, lay, *p, vals, *a, false);
        for (v, (_, at)) in abi.into_iter().zip(leaves(lay, *p)) {
            args.push((v, at));
        }
    }
    let ret = call_ret_ty(lay, sig.ret, false);
    let attr = ret_attr(lay, sig.ret);
    if records::is_mem(lay, sig.ret) {
        let r = b.call_ptr(&ret, attr, &code, &args).expect("a result");
        records::call_result(b, lay, sig.ret, r, &out);
    } else if out.iter().any(|d| matches!(d.ty, LTy::I1 | LTy::Ptr)) {
        // Booleans come back as bytes and pointers as addresses.
        let r = b.call_ptr(&ret, attr, &code, &args).expect("a result");
        records::name_leaves(b, r, &out);
    } else if out.len() <= 1 {
        if let [r] = out.as_slice() {
            b.name_next(r);
        }
        b.call_ptr(&ret, attr, &code, &args);
    } else {
        let t = b.call_ptr(&ret, attr, &code, &args).expect("a tuple");
        for (j, dst) in out.iter().enumerate() {
            b.name_next(dst);
            b.extract(&t, j);
        }
    }
}

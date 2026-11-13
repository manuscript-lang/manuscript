//! Closures, function values and interfaces.
//!
//! A closure is one heap or frame object, `%ms.env.<code>` = `{ %ms.closure, capture.. }`: the
//! header (`ms_rt_abi::Closure`: clone, drop and code pointers), then each capture as the struct
//! it has in memory, so the layout is the one the runtime and the Cranelift object read. Its
//! value is the object's address and an indirect call loads the code pointer from the header. The
//! code of a closure and the methods of a vtable keep the leaf convention: the runtime and the
//! translated functions call them through a pointer.
//!
//! An interface value is two words, the data and the vtable address with a tag in its low bits
//! (1 owns a heap box, 2 borrows one, 0 an owned value).

use super::calls::{Callee, declare_leaf, leaf_call};
use super::{Area, Cx, Vals, aggregate, records};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{FnBuilder, Meta, Ty as LTy, Types, Val};
use ms_mir::ir::{Func, FuncKind, Imm, Inst, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok: |k| matches!(k, TyKind::Fn(..) | TyKind::Ptr | TyKind::Iface(_)),
    inst_ok,
    emit,
    ..Area::NONE
};

/// Mask that clears the two tag bits of a vtable word.
const UNTAG: i64 = !3;

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::ClosureNew
            | Op::ClosureCap
            | Op::ClosureCapAddr
            | Op::CallInd
            | Op::FuncAddr
            | Op::IfaceNew
            | Op::IfaceBorrow
            | Op::IfaceView
            | Op::IfaceData
            | Op::IfaceIs
            | Op::CallMethod
    )
}

/// Whether a value of `ty` has a memory shape or no leaves at all.
fn storable(lay: &Layouts, ty: Ty) -> bool {
    lay.width(ty) == 0 || records::shape_ok(lay, ty)
}

fn inst_ok(m: &Module, lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::ClosureNew, Imm::Func(c)) => match &m.funcs[c.index()].kind {
            FuncKind::Closure { captures } => captures.iter().all(|c| storable(lay, *c)),
            _ => false,
        },
        (Op::ClosureCap | Op::ClosureCapAddr, Imm::Idx(i)) => match &f.kind {
            FuncKind::Closure { captures } => captures
                .get(i as usize)
                .is_some_and(|c| storable(lay, *c) && inst.args.len() == 1),
            _ => false,
        },
        (Op::IfaceNew | Op::IfaceBorrow, Imm::Vtable(_)) => storable(lay, f.ty(inst.args[0])),
        (Op::CallMethod, Imm::Method(..)) | (Op::CallInd | Op::FuncAddr, _) => true,
        (Op::IfaceView | Op::IfaceData | Op::IfaceIs, _) => true,
        _ => false,
    }
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let out: Vec<Val> = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    match (inst.op, inst.imm) {
        (Op::ClosureNew, Imm::Func(c)) => closure_new(cx, inst, vals, c.index(), &out, b),
        (Op::ClosureCap | Op::ClosureCapAddr, Imm::Idx(i)) => capture(cx, inst, vals, i, &out, b),
        (Op::FuncAddr, Imm::Func(c)) => {
            let callee = &cx.m.funcs[c.index()];
            let sym = (cx.symbol_of)(c.index());
            let decl = declare_leaf(b.types(), cx.lay, callee, &sym, "");
            cx.decls.push((sym.clone(), decl));
            b.name_next(&out[0]);
            b.byte_ptr(&Val::new(format!("@\"{sym}\""), LTy::Ptr), 0);
        }
        (Op::IfaceData, _) => {
            b.name_next(&out[0]);
            b.byte_ptr(&vals[&inst.args[0].index()][0], 0);
        }
        (Op::CallInd, _) => call_closure(cx, inst, vals, &out, b),
        (Op::IfaceNew | Op::IfaceBorrow, Imm::Vtable(vt)) => {
            iface_new(cx, inst, vals, vt.index(), &out, b)
        }
        (Op::IfaceView, _) => {
            // The same data, with the vtable retagged as a view: nothing is freed.
            let v = &vals[&inst.args[0].index()];
            b.name_next(&out[0]);
            b.byte_ptr(&v[0], 0);
            let bare = b.ptrmask(&v[1], UNTAG);
            b.name_next(&out[1]);
            b.byte_ptr(&bare, 2);
        }
        (Op::IfaceIs, Imm::Vtable(vt)) => {
            let have = b.ptrmask(&vals[&inst.args[0].index()][1], UNTAG);
            let want = vtable(cx, vt.index());
            b.name_next(&out[0]);
            b.icmp("eq", &have, &want);
        }
        (Op::CallMethod, Imm::Method(iface, k)) => {
            let sig = &cx.m.ifaces[iface.index()].methods[k as usize];
            let recv = &vals[&inst.args[0].index()];
            // The table address with the tag cleared; the slot is an invariant, non-null,
            // 8-aligned code pointer, so a vtable LLVM can see devirtualizes the call.
            let table = b.ptrmask(&recv[1], UNTAG);
            let slot = b.byte_ptr(&table, 8 * (1 + u64::from(k)));
            let meta = Meta {
                invariant: true,
                nonnull: true,
                align8: true,
                ..Meta::default()
            };
            let code = b.load_with(&LTy::Ptr, &slot, 8, meta);
            let data = b.ptr_to_int(&recv[0]);
            let ret = sig.ret;
            leaf_call(
                b,
                cx.lay,
                vals,
                Callee::Pointer(&code),
                data,
                (&sig.params, &inst.args[1..]),
                ret,
                &out,
            );
        }
        _ => unreachable!("handles accepts only closure and interface ops"),
    }
}

/// The address of the vtable `vt`, a data object the Cranelift object defines.
fn vtable(cx: &mut Cx, vt: usize) -> Val {
    let sym = &cx.plan.vtables[&vt];
    cx.data.push(sym.clone());
    Val::new(format!("@\"{sym}\""), LTy::Ptr)
}

/// A fresh heap block of `size` bytes.
fn alloc(cx: &mut Cx, size: u64, b: &mut FnBuilder) -> Val {
    super::rt::declare(cx, "msrt_alloc");
    b.call(
        &LTy::Ptr,
        "noalias align 16 ",
        "msrt_alloc",
        &[(Val::int(size.max(1) as i64), "")],
    )
    .expect("a pointer")
}

/// `IfaceNew` boxes the leaves of its operand on the heap; `IfaceBorrow` boxes them as they are,
/// in the frame when nothing outlives it (tag 2, nothing is freed) and on the heap otherwise
/// (tag 1, the box is freed with the value).
fn iface_new(cx: &mut Cx, inst: &Inst, vals: &Vals, vt: usize, out: &[Val], b: &mut FnBuilder) {
    let ty = cx.f.ty(inst.args[0]);
    let size = u64::from(mem_layout(&cx.lay.leaves(ty)).size);
    let framed = inst
        .res
        .is_some_and(|r| cx.plan.framed_ifaces.contains(&r.index()));
    let (block, tag) = if inst.op == Op::IfaceNew {
        (alloc(cx, size, b), 0)
    } else if framed {
        let slot = b.alloca(&aggregate(b.types(), cx.lay, ty));
        (slot, 2)
    } else {
        (alloc(cx, size, b), 1)
    };
    if cx.lay.width(ty) > 0 {
        records::store_value(b, cx.lay, ty, vals, inst.args[0], &block);
    }
    b.name_next(&out[0]);
    b.byte_ptr(&block, 0);
    let table = vtable(cx, vt);
    b.name_next(&out[1]);
    b.byte_ptr(&table, tag);
}

/// The environment of a closure whose captures are `captures`: its type, the field of each
/// capture (none for a capture without leaves), and each capture's byte offset.
struct Env {
    ty: LTy,
    fields: Vec<Option<usize>>,
    offsets: Vec<u64>,
}

fn env(types: &Types, lay: &Layouts, code: &str, captures: &[Ty]) -> Env {
    let header = types.named("ms.closure", vec![LTy::Ptr; 3]);
    let mut fields_of = vec![header];
    let mut fields = Vec::new();
    let mut offsets = Vec::new();
    let mut off = u64::from(crate::cg::CLOSURE_CAPTURES);
    for c in captures {
        let leaves: Vec<Leaf> = lay.leaves(*c);
        let mem = mem_layout(&leaves);
        let align = u64::from(mem.align);
        off = off.div_ceil(align) * align;
        offsets.push(off);
        off += u64::from(mem.size);
        if leaves.is_empty() {
            fields.push(None);
        } else {
            fields.push(Some(fields_of.len()));
            fields_of.push(aggregate(types, lay, *c));
        }
    }
    let ty = types.named(&format!("ms.env.{code}"), fields_of);
    debug_assert_eq!(types.size_align(&ty).0, off.div_ceil(8) * 8);
    debug_assert!(
        fields
            .iter()
            .zip(&offsets)
            .all(|(f, o)| f.is_none_or(|f| types.field_offset(&ty, f) == *o))
    );
    Env {
        ty,
        fields,
        offsets,
    }
}

fn closure_new(cx: &mut Cx, inst: &Inst, vals: &Vals, c: usize, out: &[Val], b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let callee = &m.funcs[c];
    let FuncKind::Closure { captures } = &callee.kind else {
        unreachable!("inst_ok checked the kind")
    };
    let env = env(b.types(), lay, &callee.name, captures);
    let framed = inst
        .res
        .is_some_and(|r| cx.plan.framed_closures.contains(&r.index()));
    let size = b.types().size_align(&env.ty).0;
    // The object takes the closure's own name.
    let obj = if framed {
        b.alloca_as(&out[0], &env.ty);
        out[0].clone()
    } else {
        b.name_next(&out[0]);
        alloc(cx, size, b)
    };
    let glue = &cx.plan.closures[&(c, framed)];
    let code = (cx.symbol_of)(c);
    let decl = declare_leaf(b.types(), lay, callee, &code, "");
    cx.decls.push((code.clone(), decl));
    cx.decls.push((
        glue.clone.clone(),
        format!("declare i64 @\"{}\"(i64)", glue.clone),
    ));
    cx.decls.push((
        glue.drop.clone(),
        format!("declare void @\"{}\"(i64)", glue.drop),
    ));
    let header = b.types().named("ms.closure", vec![LTy::Ptr; 3]);
    let head = b.field_ptr(&env.ty, &obj, 0);
    for (k, sym) in [&glue.clone, &glue.drop, &code].into_iter().enumerate() {
        let p = b.field_ptr(&header, &head, k);
        b.store(&Val::new(format!("@\"{sym}\""), LTy::Ptr), &p, 8);
    }
    for (i, field) in env.fields.iter().enumerate() {
        if let Some(field) = field {
            let p = b.field_ptr(&env.ty, &obj, *field);
            records::store_value(b, lay, captures[i], vals, inst.args[i], &p);
        }
    }
}

/// `ClosureCap` reads capture `i` of the closure being run, `ClosureCapAddr` takes its address.
fn capture(cx: &mut Cx, inst: &Inst, vals: &Vals, i: u32, out: &[Val], b: &mut FnBuilder) {
    let FuncKind::Closure { captures } = &cx.f.kind else {
        unreachable!("inst_ok checked the kind")
    };
    let i = i as usize;
    let env = env(b.types(), cx.lay, &cx.f.name, captures);
    let base = &vals[&inst.args[0].index()][0];
    let at = |b: &mut FnBuilder| match env.fields[i] {
        Some(field) => b.field_ptr(&env.ty, base, field),
        None => b.byte_ptr(base, env.offsets[i]),
    };
    if inst.op == Op::ClosureCapAddr {
        b.name_next(&out[0]);
        at(b);
    } else if cx.lay.width(captures[i]) > 0 {
        let p = at(b);
        records::load_value(b, cx.lay, captures[i], &p, out);
    }
}

fn call_closure(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let TyKind::Fn(params, ret) = cx.m.types.kind(cx.f.ty(inst.args[0])).clone() else {
        unreachable!("call.ind of a non-closure")
    };
    let clo = vals[&inst.args[0].index()][0].clone();
    let header = b.types().named("ms.closure", vec![LTy::Ptr; 3]);
    let slot = b.field_ptr(&header, &clo, 2);
    let code = b.load(&LTy::Ptr, &slot, 8);
    let first = b.ptr_to_int(&clo);
    leaf_call(
        b,
        cx.lay,
        vals,
        Callee::Pointer(&code),
        first,
        (&params, &inst.args[1..]),
        ret,
        out,
    );
}

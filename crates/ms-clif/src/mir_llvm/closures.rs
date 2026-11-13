//! Closures, indirect calls and function values.
//!
//! A closure is one heap or frame object: `{ clone, drop, code, captures.. }` (see
//! `ms_rt_abi::Closure`), with the captures laid out like a record of their leaves. Its value is
//! the object's address, so a closure travels as one `i64` leaf and an indirect call loads the
//! code pointer from the object and passes the object as the first argument.

use super::calls::{
    Callee, call_into, declare_function, declare_text, leaf_args, leaf_list, load_leaves,
    store_leaves,
};
use super::{Area, Cx, Vals};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Imm, Inst, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok: |k| matches!(k, TyKind::Fn(..)),
    emit,
    ..Area::NONE
};

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::ClosureNew | Op::ClosureCap | Op::ClosureCapAddr | Op::CallInd | Op::FuncAddr
    )
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay, f) = (cx.m, cx.lay, cx.f);
    let out: Vec<Val> = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    match (inst.op, inst.imm) {
        (Op::ClosureNew, Imm::Func(c)) => closure_new(cx, inst, vals, c.index(), &out, b),
        (Op::ClosureCap | Op::ClosureCapAddr, Imm::Idx(i)) => {
            let ms_mir::ir::FuncKind::Closure { captures } = &f.kind else {
                unreachable!("closure.cap outside a closure")
            };
            let (off, leaves) = capture_layout(lay, captures, i as usize);
            let env = &vals[&inst.args[0].index()][0];
            if inst.op == Op::ClosureCapAddr {
                b.name_next(&out[0]);
                b.bin(Bin::Add, env, &Val::int(off as i64));
            } else {
                let base = b.inttoptr(env);
                load_leaves(b, &base, off, &leaves, &out);
            }
        }
        (Op::FuncAddr, Imm::Func(c)) => {
            let sym = (cx.symbol_of)(c.index());
            declare_function(cx, &sym, &m.funcs[c.index()]);
            let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
            b.name_next(&out[0]);
            b.ptrtoint(&addr);
        }
        (Op::CallInd, _) => {
            let TyKind::Fn(ps, r) = lay.m.types.kind(f.ty(inst.args[0])).clone() else {
                unreachable!("call.ind of a non-closure")
            };
            let clo = vals[&inst.args[0].index()][0].clone();
            let obj = b.inttoptr(&clo);
            let at = b.gep_bytes(&obj, u64::from(crate::cg::CLOSURE_CODE as u32));
            let code = b.load(&LTy::Ptr, &at, 8);
            let mut args = vec![(clo, "")];
            args.extend(leaf_args(cx, vals, inst, 1, &ps));
            call_into(b, Callee::Pointer(&code), &leaf_list(lay, r), &args, &out);
        }
        _ => unreachable!("handles accepts only closure ops"),
    }
}

/// The byte offset and leaves of capture `i` in a closure with `captures`, and the object size.
fn capture_layout(lay: &Layouts, captures: &[Ty], i: usize) -> (u64, Vec<Leaf>) {
    let mut off = u64::from(crate::cg::CLOSURE_CAPTURES);
    for (k, c) in captures.iter().enumerate() {
        let leaves = lay.leaves(*c);
        let l = mem_layout(&leaves);
        off = off.next_multiple_of(u64::from(l.align));
        if k == i {
            return (off, leaves);
        }
        off += u64::from(l.size);
    }
    unreachable!("capture {i} of {}", captures.len())
}

/// The size of a closure object with `captures`, rounded to a word.
fn object_size(lay: &Layouts, captures: &[Ty]) -> u64 {
    let mut off = u64::from(crate::cg::CLOSURE_CAPTURES);
    for c in captures {
        let l = mem_layout(&lay.leaves(*c));
        off = off.next_multiple_of(u64::from(l.align)) + u64::from(l.size);
    }
    off.next_multiple_of(8)
}

fn closure_new(cx: &mut Cx, inst: &Inst, vals: &Vals, c: usize, out: &[Val], b: &mut FnBuilder) {
    let (m, lay, plan, symbol_of) = (cx.m, cx.lay, cx.plan, cx.symbol_of);
    let callee = &m.funcs[c];
    let captures = match &callee.kind {
        ms_mir::ir::FuncKind::Closure { captures } => captures.clone(),
        _ => Vec::new(),
    };
    let size = object_size(lay, &captures);
    let framed = inst.res.is_some_and(|r| plan.framed.contains(&r.index()));
    // The object is the address of a frame slot, or a fresh heap block.
    let obj = if framed {
        b.alloca(&LTy::Array(Box::new(LTy::I64), size / 8))
    } else {
        cx.decls.push((
            "msrt_alloc".into(),
            "declare noalias align 16 ptr @\"msrt_alloc\"(i64)".into(),
        ));
        b.call(
            &LTy::Ptr,
            "noalias align 16 ",
            "msrt_alloc",
            &[(Val::int(size.max(1) as i64), "")],
        )
        .expect("a pointer")
    };
    let syms = &plan.closures[&(c, framed)];
    cx.decls.push((
        syms.clone.clone(),
        declare_text(&syms.clone, &(LTy::I64, ""), &[(LTy::I64, "")]),
    ));
    cx.decls.push((
        syms.drop.clone(),
        declare_text(&syms.drop, &(LTy::Void, ""), &[(LTy::I64, "")]),
    ));
    let code = symbol_of(c);
    declare_function(cx, &code, callee);
    let header = [
        (0, syms.clone.as_str()),
        (8, syms.drop.as_str()),
        (u64::from(crate::cg::CLOSURE_CODE as u32), code.as_str()),
    ];
    for (at, sym) in header {
        let p = b.gep_bytes(&obj, at);
        b.store(&Val::new(format!("@\"{sym}\""), LTy::Ptr), &p, 8);
    }
    for (i, _) in captures.iter().enumerate() {
        let (off, leaves) = capture_layout(lay, &captures, i);
        store_leaves(b, &obj, off, &leaves, &vals[&inst.args[i].index()]);
    }
    b.name_next(&out[0]);
    b.ptrtoint(&obj);
}

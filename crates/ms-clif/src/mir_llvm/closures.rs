//! Closures, indirect calls and function values.
//!
//! A closure is one heap or frame object: `{ clone, drop, code, captures.. }` (see
//! `ms_rt_abi::Closure`), with the captures laid out like a record of their leaves. Its value is
//! the object's address, so a closure travels as one `i64` leaf and an indirect call loads the
//! code pointer from the object and passes the object as the first argument.

use super::calls::{
    Callee, MemObj, call_into, declare_function, declare_text, leaf_args, leaf_list,
};
use super::{Area, Cx, Vals};
use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
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
            let (obj, parts) = object(lay, captures);
            let i = i as usize;
            let base = b.inttoptr(&vals[&inst.args[0].index()][0]);
            if inst.op == Op::ClosureCapAddr {
                let at = obj.field_of(&mut *b, &base, i);
                b.name_next(&out[0]);
                b.ptrtoint(&at);
            } else {
                obj.load(b, &base, i, &parts[i], &out);
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
            // The code word is the third field of the object header.
            let header = LTy::Tuple(vec![LTy::Ptr; 3]);
            let at = b.field_ptr(&header, &obj, 2);
            let code = b.load(&LTy::Ptr, &at, 8);
            let mut args = vec![(clo, "")];
            args.extend(leaf_args(cx, vals, inst, 1, &ps));
            call_into(b, Callee::Pointer(&code), &leaf_list(lay, r), &args, &out);
        }
        _ => unreachable!("handles accepts only closure ops"),
    }
}

/// The closure object of a function with `captures`: the clone, drop and code words, then each
/// capture's leaves, in a struct that LLVM can address by field.
fn object(lay: &Layouts, captures: &[Ty]) -> (MemObj, Vec<Vec<Leaf>>) {
    let parts: Vec<Vec<Leaf>> = captures.iter().map(|c| lay.leaves(*c)).collect();
    (
        MemObj::new(&[LTy::Ptr, LTy::Ptr, LTy::Ptr], &parts, 8),
        parts,
    )
}

fn closure_new(cx: &mut Cx, inst: &Inst, vals: &Vals, c: usize, out: &[Val], b: &mut FnBuilder) {
    let (m, lay, plan, symbol_of) = (cx.m, cx.lay, cx.plan, cx.symbol_of);
    let callee = &m.funcs[c];
    let captures = match &callee.kind {
        ms_mir::ir::FuncKind::Closure { captures } => captures.clone(),
        _ => Vec::new(),
    };
    let (obj, parts) = object(lay, &captures);
    let framed = inst.res.is_some_and(|r| plan.framed.contains(&r.index()));
    // The object is a frame slot, or a fresh heap block.
    let ptr = if framed {
        b.alloca(&obj.ty)
    } else {
        cx.decls.push((
            "msrt_alloc".into(),
            "declare noalias align 16 ptr @\"msrt_alloc\"(i64)".into(),
        ));
        b.call(
            &LTy::Ptr,
            "noalias align 16 ",
            "msrt_alloc",
            &[(Val::int(obj.size.max(1) as i64), "")],
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
    for (field, sym) in [&syms.clone, &syms.drop, &code].into_iter().enumerate() {
        let p = b.field_ptr(&obj.ty, &ptr, field);
        b.store(&Val::new(format!("@\"{sym}\""), LTy::Ptr), &p, 8);
    }
    for (i, leaves) in parts.iter().enumerate() {
        obj.store(b, &ptr, i, leaves, &vals[&inst.args[i].index()]);
    }
    b.name_next(&out[0]);
    b.ptrtoint(&ptr);
}

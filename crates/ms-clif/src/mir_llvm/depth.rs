//! The stack-depth check of a recursive function (`depth.enter`).
//!
//! The first thing the function does is compare the stack pointer with the task's limit, which sits
//! in the stack region beside the block's address. Below it, the function runs again on a new stack
//! segment: `msrt_task_grow` calls the function's grow shim there with the entry parameters, stored
//! one cell each in a heap block followed by room for the results, and the function returns what
//! that run produced. It is the check `Lower::depth_enter` writes for the Cranelift path.

use super::{Area, Cx, Vals, block_label, leaves};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Inst, Op};
use ms_rt_abi::symbols::{STACK_LIMIT_CELL, STACK_REGION};

pub(super) const AREA: Area = Area {
    handles: |op| matches!(op, Op::DepthEnter | Op::DepthLeave),
    splits: |op, _| usize::from(op == Op::DepthEnter),
    emit,
    ..Area::NONE
};

fn emit(cx: &mut Cx, inst: &Inst, _: &Vals, b: &mut FnBuilder) {
    if inst.op == Op::DepthEnter {
        enter(cx, b);
    }
}

/// Alignment of a leaf in its 8-byte cell.
fn align(t: &LTy) -> u64 {
    if *t == LTy::I8 { 1 } else { 8 }
}

/// Writes the check; `cx.entry_abi` holds the entry parameters as they arrive.
pub(super) fn enter(cx: &mut Cx, b: &mut FnBuilder) {
    let frame = b
        .call(
            &LTy::Ptr,
            "",
            "llvm.frameaddress.p0",
            &[(Val::new("0", LTy::I32), "")],
        )
        .expect("a pointer");
    let sp = b.ptr_to_int(&frame);
    let base = b.bin(Bin::And, &sp, &Val::int(!(STACK_REGION - 1)));
    let cell = b.bin(Bin::Add, &base, &Val::int(STACK_REGION - STACK_LIMIT_CELL));
    let cell = b.int_to_ptr(&cell);
    let limit = b.load(&LTy::I64, &cell, 8);
    let over = b.icmp("ult", &sp, &limit);
    let grow = format!("d{}_{}", cx.block, cx.split);
    cx.split += 1;
    let next = block_label(cx.block, cx.split);
    b.cond_br_likely(&over, &grow, &next, false);
    b.label(&grow);
    let params = cx.entry_abi.clone();
    let rets = cx.ret_abi.clone();
    let block = b
        .call(
            &LTy::Ptr,
            "noalias align 16 ",
            "msrt_alloc",
            &[(Val::int(((params.len() + rets.len()) * 8) as i64), "")],
        )
        .expect("a block");
    for (i, p) in params.iter().enumerate() {
        let at = b.elem_ptr(&LTy::I64, &block, &Val::int(i as i64));
        b.store(p, &at, align(&p.ty));
    }
    let shim = cx
        .grow_shim
        .clone()
        .expect("a function with a depth check has a grow shim");
    let shim_addr = b.ptr_to_int(&Val::new(format!("@\"{shim}\""), LTy::Ptr));
    let block_addr = b.ptr_to_int(&block);
    b.call(
        &LTy::Void,
        "",
        "msrt_task_grow",
        &[(shim_addr, ""), (block_addr.clone(), "")],
    );
    let results: Vec<Val> = rets
        .iter()
        .enumerate()
        .map(|(j, t)| {
            let at = b.elem_ptr(&LTy::I64, &block, &Val::int((params.len() + j) as i64));
            b.load(t, &at, align(t))
        })
        .collect();
    b.call(&LTy::Void, "", "msrt_free", &[(block_addr, "")]);
    match results.as_slice() {
        [] => b.ret(None),
        [one] => b.ret(Some(one)),
        many => {
            let t = b.tuple(many);
            b.ret(Some(&t));
        }
    }
    b.label(&next);
    for (name, decl) in [
        (
            "msrt_alloc",
            "declare noalias align 16 ptr @\"msrt_alloc\"(i64)",
        ),
        ("msrt_free", "declare void @\"msrt_free\"(i64)"),
        (
            "msrt_task_grow",
            "declare void @\"msrt_task_grow\"(i64, i64)",
        ),
        (&shim[..], "declare void @\"SHIM\"(i64)"),
    ] {
        let decl = decl.replace("SHIM", &shim);
        cx.decls.push((name.to_string(), decl));
    }
}

/// The leaf types a function returns, as they cross a call.
pub(super) fn ret_abi(lay: &crate::layout::Layouts, ret: ms_mir::types::Ty) -> Vec<LTy> {
    leaves(lay, ret).into_iter().map(|l| l.0).collect()
}

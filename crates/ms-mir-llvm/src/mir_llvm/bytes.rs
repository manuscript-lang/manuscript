//! Byte builders: `bytes.push`.

use super::{Area, Cx, Vals, block_label};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Inst, Op};
use ms_mir::layout::Layouts;
use ms_rt_abi::{VEC_CAP_OFFSET, VEC_LEN_OFFSET, VEC_PTR_OFFSET};

pub(super) const AREA: Area = Area {
    handles: |op| op == Op::BytesPush,
    splits: |_: &Layouts, _: &Func, _: &Inst, _: bool| 1,
    emit,
    ..Area::NONE
};

/// `bytes.push b, v`: when the builder at `b` has room and `v` is a byte, one store and a length
/// bump and the result is true; otherwise nothing is written and the result is false.
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let out = &vals[&inst.res.expect("a bool result").index()][0];
    let builder = &vals[&inst.args[0].index()][0];
    let value = &vals[&inst.args[1].index()][0];
    let builder = if builder.ty == LTy::Ptr {
        builder.clone()
    } else {
        b.int_to_ptr(builder)
    };
    let len_at = b.byte_ptr(&builder, VEC_LEN_OFFSET as u64);
    let len = b.load(&LTy::I64, &len_at, 8);
    let cap_at = b.byte_ptr(&builder, VEC_CAP_OFFSET as u64);
    let cap = b.load(&LTy::I64, &cap_at, 8);
    let room = b.icmp("ult", &len, &cap);
    // A `UInt8` is already one byte; only an `Int` can be out of range.
    let fast = if value.ty == LTy::I64 {
        let byte = b.icmp("ule", value, &Val::int(255));
        b.bin(Bin::And, &byte, &room)
    } else {
        room
    };
    let before = block_label(cx.block, cx.split);
    let store = format!("c{}_{}", cx.block, cx.split);
    cx.split += 1;
    let join = block_label(cx.block, cx.split);
    b.cond_br_likely(&fast, &store, &join, true);
    b.label(&store);
    let data_at = b.byte_ptr(&builder, VEC_PTR_OFFSET as u64);
    let data = b.load(&LTy::Ptr, &data_at, 8);
    let at = b.elem_ptr(&LTy::I8, &data, &len);
    let narrow = if value.ty == LTy::I8 {
        value.clone()
    } else {
        b.trunc(value, LTy::I8)
    };
    b.store(&narrow, &at, 1);
    let next = b.bin(Bin::Add, &len, &Val::int(1));
    b.store(&next, &len_at, 8);
    b.br(&join);
    b.label(&join);
    b.phi(out, &[(Val::bool(true), store), (Val::bool(false), before)]);
}

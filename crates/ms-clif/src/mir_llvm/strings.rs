//! Strings that are not lists: the shared one-character ASCII strings.

use super::{Area, Cx, Vals, records};
use crate::layout::Layouts;
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Inst, Module, Op};
use ms_rt_abi::{ASCII_CHAR_STRIDE, STR_STATIC};

pub(super) const AREA: Area = Area {
    handles: |op| op == Op::StrAscii,
    pure_op: |op| op == Op::StrAscii,
    pre,
    emit,
    ..Area::NONE
};

/// The second word is a constant: a static string of one byte. The first is written by `emit`.
fn pre(
    _: &Module,
    lay: &Layouts,
    f: &Func,
    inst: &Inst,
    _: &Vals,
    b: &mut FnBuilder,
) -> Option<Vec<Val>> {
    let held = records::held(lay, f.ty(inst.res?));
    Some(vec![
        b.reserve(held[0].clone()),
        Val::int(1 | STR_STATIC as i64),
    ])
}

/// `str.ascii b`: the entry `b` of the runtime's table of one-character strings.
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    const TABLE: &str = "msrt_ascii_chars";
    assert_eq!(ASCII_CHAR_STRIDE, 2, "the table is indexed in 16-bit cells");
    cx.data.push(TABLE.into());
    let out = &vals[&inst.res.expect("a string result").index()];
    let table = Val::new(format!("@\"{TABLE}\""), LTy::Ptr);
    // The address is held as the first leaf of the string, whichever type that is.
    if out[0].ty == LTy::Ptr {
        b.name_next(&out[0]);
        b.elem_ptr(&LTy::I16, &table, &vals[&inst.args[0].index()][0]);
    } else {
        let at = b.elem_ptr(&LTy::I16, &table, &vals[&inst.args[0].index()][0]);
        b.name_next(&out[0]);
        b.ptr_to_int(&at);
    }
}

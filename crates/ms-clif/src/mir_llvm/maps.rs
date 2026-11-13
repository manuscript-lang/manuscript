//! Maps and sets, and pointer tests.
//!
//! An opaque runtime object is one pointer. A `Map` or `Set` is seven words and an empty one is all zero, so `map.new` (handled in
//! `calls.rs` with the other runtime calls) is seven constants. Every other map operation is a
//! runtime call. The interface ops live in `closures.rs`.

use super::{Area, Cx, Vals};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Inst, Op};
use ms_mir::types::TyKind;

pub(super) const AREA: Area = Area {
    handles: |op| op == Op::PtrIsNull,
    ty_ok: |k| matches!(k, TyKind::Obj(..)),
    emit,
    ..Area::NONE
};

fn emit(_: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let out = &vals[&inst.res.expect("ptr.is_null has a result").index()];
    b.name_next(&out[0]);
    b.icmp(
        "eq",
        &vals[&inst.args[0].index()][0],
        &Val::new("null", LTy::Ptr),
    );
}

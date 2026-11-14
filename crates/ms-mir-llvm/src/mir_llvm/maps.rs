//! Maps and sets, and pointer tests.
//!
//! An opaque runtime object is one pointer. A `Map` or `Set` is seven words and an empty one is all zero, so `map.new` (handled in
//! `calls.rs` with the other runtime calls) is seven constants. Every other map operation is a
//! runtime call. The interface ops live in `closures.rs`.

use super::{Area, Cx, Vals};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Imm, Inst, Op};
use ms_mir::types::TyKind;

pub(super) const AREA: Area = Area {
    handles: |op| matches!(op, Op::PtrIsNull | Op::PtrAdd | Op::PtrNull | Op::PtrLoadU),
    ty_ok: |k| matches!(k, TyKind::Obj(..)),
    emit,
    ..Area::NONE
};

fn emit(_: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    if inst.op == Op::PtrLoadU {
        let Imm::Int(w) = inst.imm else { return };
        let out = &vals[&inst.res.expect("ptr.loadu has a result").index()];
        let ty = match w {
            1 => LTy::I8,
            2 => LTy::I16,
            4 => LTy::I32,
            _ => LTy::I64,
        };
        let p = &vals[&inst.args[0].index()][0];
        if w == 8 {
            b.name_next(&out[0]);
            b.load(&ty, p, 1);
        } else {
            let x = b.load(&ty, p, 1);
            b.name_next(&out[0]);
            b.zext(&x, LTy::I64);
        }
        return;
    }
    if inst.op == Op::PtrNull {
        let out = &vals[&inst.res.expect("ptr.null has a result").index()];
        b.name_next(&out[0]);
        b.gep_dyn(&Val::new("null", LTy::Ptr), &Val::int(0));
        return;
    }
    if inst.op == Op::PtrAdd {
        let out = &vals[&inst.res.expect("ptr.add has a result").index()];
        b.name_next(&out[0]);
        b.gep_dyn(
            &vals[&inst.args[0].index()][0],
            &vals[&inst.args[1].index()][0],
        );
        return;
    }
    let out = &vals[&inst.res.expect("ptr.is_null has a result").index()];
    b.name_next(&out[0]);
    b.icmp(
        "eq",
        &vals[&inst.args[0].index()][0],
        &Val::new("null", LTy::Ptr),
    );
}

//! Module globals: a zero-initialised block the Cranelift object defines, read and written as the
//! value's memory shape. Overwriting a global drops the value it held.

use super::glue::drop_value;
use super::types::{load_value, reserve, shape_ok, store_value};
use super::{Area, Cx, Vals};
use crate::glue_llvm::{OwnKind, own_kind};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op, Value};
use ms_mir::layout::Layouts;

pub(super) const AREA: Area = Area {
    handles: |op| matches!(op, Op::GlobalGet | Op::GlobalSet),
    inst_ok,
    splits,
    emit,
    ..Area::NONE
};

/// The global's type has a memory shape (or no leaves at all).
fn inst_ok(m: &Module, lay: &Layouts, _: &Func, inst: &Inst) -> bool {
    let Imm::Global(g) = inst.imm else {
        return false;
    };
    let ty = m.globals[g.index()].ty;
    lay.leaves(ty).is_empty() || shape_ok(lay, ty)
}

/// Overwriting a global that holds a string checks the tag before freeing it.
fn splits(lay: &Layouts, f: &Func, inst: &Inst, _: bool) -> usize {
    let Imm::Global(_) = inst.imm else { return 0 };
    let ty = f.ty(inst.args[0]);
    usize::from(
        inst.op == Op::GlobalSet && !lay.leaves(ty).is_empty() && own_kind(lay, ty) == OwnKind::Str,
    )
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let Imm::Global(g) = inst.imm else {
        unreachable!("a global op names its global")
    };
    let ty = cx.m.globals[g.index()].ty;
    if cx.lay.leaves(ty).is_empty() {
        return;
    }
    let sym = cx.plan.globals[&g.index()].clone();
    cx.data.push(sym.clone());
    let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
    if inst.op == Op::GlobalGet {
        let out = vals[&inst.res.expect("a global read has a result").index()].clone();
        return load_value(b, cx.lay, ty, &addr, &out);
    }
    if cx.m.needs_drop(ty) {
        // The old value is read into a value of its own so the drop sees it like any other.
        let old = Value(u32::MAX);
        let held = reserve(b, cx.lay, ty);
        load_value(b, cx.lay, ty, &addr, &held);
        let mut with = vals.clone();
        with.insert(old.index(), held);
        drop_value(cx, ty, old, None, &with, b);
    }
    store_value(b, cx.lay, ty, vals, inst.args[0], &addr);
}

//! Strings and lists: the length leaf and element reads.

use super::{Area, Cx, Vals, block_label, leaf};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Func, Inst, Module, Op};
use ms_mir::types::TyKind;

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    splits,
    pure_op: |op| op == Op::ListLen,
    pre,
    emit,
};

/// Every list is three leaves, whatever its element.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Str | TyKind::Bytes | TyKind::List(_))
}

fn handles(op: Op) -> bool {
    matches!(op, Op::ListLen | Op::ListGet | Op::ListGetNn | Op::ListGetU)
}

/// Whether `op` ends its block early to branch to a fault when checks are on.
fn splits(op: Op) -> usize {
    usize::from(matches!(op, Op::ListGet | Op::ListGetNn))
}

fn inst_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    !matches!(i.op, Op::ListGet | Op::ListGetNn | Op::ListGetU) || elem_ok(m, lay, f, i)
}

/// The length is a leaf of the list: no instruction.
fn pre(_: &Layouts, _: &Func, inst: &Inst, vals: &Vals) -> Option<Vec<Val>> {
    (inst.op == Op::ListLen).then(|| vec![vals[&inst.args[0].index()][1].clone()])
}

/// Whether the element a list read loads is made of plain `i64`, `double` and `i8` leaves, which
/// sit in memory exactly as in registers.
fn elem_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    let Some(e) = m.seq_elem(f.ty(i.args[0])) else {
        return false;
    };
    i.res.is_some_and(|r| f.ty(r) == e)
        && lay
            .leaves(e)
            .iter()
            .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    if inst.op == Op::ListLen {
        return;
    }
    list_get(cx, inst, vals, b);
}

/// A list element read: normalize a negative index (`ListGet`), branch to the fault when it is out
/// of range, then load each leaf of the element at its offset. The element type is an LLVM
/// type, so the address is a typed `getelementptr` and LLVM sees a strided access it can vectorize.
fn list_get(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let l = &vals[&inst.args[0].index()];
    let i = vals[&inst.args[1].index()][0].clone();
    let out = &vals[&inst.res.expect("list read result").index()];
    let elem = cx.m.seq_elem(cx.f.ty(inst.args[0])).expect("a list");
    let tys: Vec<LTy> = cx.lay.leaves(elem).into_iter().map(|x| leaf(x).0).collect();
    let (ptr, len) = (b.int_to_ptr(&l[0]), l[1].clone());
    let idx = if inst.op == Op::ListGet {
        let neg = b.icmp("slt", &i, &Val::int(0));
        let wrapped = b.bin(Bin::Add, &i, &len);
        b.select(&neg, &wrapped, &i)
    } else {
        i.clone()
    };
    if cx.checks && splits(inst.op) > 0 {
        let oob = b.icmp("uge", &idx, &len);
        let fault = format!("f{}_{}", cx.block, cx.split);
        cx.split += 1;
        let next = block_label(cx.block, cx.split);
        b.cond_br_likely(&oob, &fault, &next, false);
        b.label(&fault);
        cx.sites += 1;
        b.fault_site(cx.sites);
        b.call(
            &LTy::Void,
            "",
            "msrt_index_fault",
            &[(i.clone(), ""), (len, "")],
        );
        b.unreachable();
        cx.decls.push((
            "msrt_index_fault".into(),
            "declare void @\"msrt_index_fault\"(i64, i64) cold noreturn".into(),
        ));
        b.label(&next);
    }
    let types = Types::default();
    let whole = match tys.as_slice() {
        [one] => one.clone(),
        many => LTy::Tuple(many.to_vec()),
    };
    debug_assert_eq!(
        types.size_align(&whole).0,
        u64::from(mem_layout(&cx.lay.leaves(elem)).size)
    );
    let at = b.elem_ptr(&whole, &ptr, &idx);
    for (k, (t, dst)) in tys.iter().zip(out).enumerate() {
        let from = if tys.len() == 1 {
            at.clone()
        } else {
            b.field_ptr(&whole, &at, k)
        };
        b.name_next(dst);
        b.load(t, &from, types.size_align(t).1);
    }
}

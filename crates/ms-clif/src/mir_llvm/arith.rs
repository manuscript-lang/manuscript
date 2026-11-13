//! Scalar values: constants, integer and float arithmetic, comparisons, selects.

use super::{Area, Cx, Vals};
use crate::layout::Layouts;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Cc, Func, Imm, Inst, Op};
use ms_mir::types::TyKind;

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    pure_op: handles,
    pre,
    emit,
    ..Area::NONE
};

fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Unit | TyKind::Int | TyKind::Float | TyKind::Bool)
}

fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::IConst
            | Op::FConst
            | Op::BConst
            | Op::UnitConst
            | Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::INeg
            | Op::And
            | Op::Or
            | Op::Xor
            | Op::Not
            | Op::ICmp
            | Op::UICmp
            | Op::FCmp
            | Op::FAdd
            | Op::FSub
            | Op::FMul
            | Op::FDiv
            | Op::FNeg
            | Op::Select
            | Op::B2I
    )
}

/// A constant is its own text: no register.
fn pre(_: &Layouts, _: &Func, inst: &Inst, _: &Vals) -> Option<Vec<Val>> {
    match (inst.op, inst.imm) {
        (Op::IConst, Imm::Int(v)) => Some(vec![Val::int(v)]),
        (Op::FConst, Imm::Float(bits)) => Some(vec![Val::double(bits)]),
        (Op::BConst, Imm::Bool(v)) => Some(vec![Val::byte(v as u8)]),
        _ => None,
    }
}

fn icc(cc: Cc, unsigned: bool) -> &'static str {
    match (cc, unsigned) {
        (Cc::Eq, _) => "eq",
        (Cc::Ne, _) => "ne",
        (Cc::Lt, false) => "slt",
        (Cc::Le, false) => "sle",
        (Cc::Gt, false) => "sgt",
        (Cc::Ge, false) => "sge",
        (Cc::Lt, true) => "ult",
        (Cc::Le, true) => "ule",
        (Cc::Gt, true) => "ugt",
        (Cc::Ge, true) => "uge",
    }
}

/// Ordered comparison, except `ne`, which holds for NaN (the MIR rule, `Cc`).
fn fcc(cc: Cc) -> &'static str {
    match cc {
        Cc::Eq => "oeq",
        Cc::Ne => "une",
        Cc::Lt => "olt",
        Cc::Le => "ole",
        Cc::Gt => "ogt",
        Cc::Ge => "oge",
    }
}

/// Writes one scalar instruction.
fn emit(_: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let arg = |i: usize| vals[&inst.args[i].index()][0].clone();
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    if matches!(
        inst.op,
        Op::IConst | Op::FConst | Op::BConst | Op::UnitConst
    ) {
        return;
    }
    // A single-leaf result is named in place; `Select` handles several.
    if let [r] = out.as_slice() {
        b.name_next(r);
    }
    match inst.op {
        Op::IAdd => drop(b.bin(Bin::Add, &arg(0), &arg(1))),
        Op::ISub => drop(b.bin(Bin::Sub, &arg(0), &arg(1))),
        Op::IMul => drop(b.bin(Bin::Mul, &arg(0), &arg(1))),
        Op::And => drop(b.bin(Bin::And, &arg(0), &arg(1))),
        Op::Or => drop(b.bin(Bin::Or, &arg(0), &arg(1))),
        Op::Xor => drop(b.bin(Bin::Xor, &arg(0), &arg(1))),
        Op::FAdd => drop(b.bin(Bin::FAdd, &arg(0), &arg(1))),
        Op::FSub => drop(b.bin(Bin::FSub, &arg(0), &arg(1))),
        Op::FMul => drop(b.bin(Bin::FMul, &arg(0), &arg(1))),
        Op::FDiv => drop(b.bin(Bin::FDiv, &arg(0), &arg(1))),
        Op::INeg => drop(b.bin(Bin::Sub, &Val::int(0), &arg(0))),
        Op::FNeg => drop(b.fneg(&arg(0))),
        Op::Not => drop(b.bin(Bin::Xor, &arg(0), &Val::byte(1))),
        Op::ICmp | Op::UICmp | Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            // The comparison is an `i1`; the result is its zero-extension, so name only that.
            let pending = b.take_name();
            let c = if inst.op == Op::FCmp {
                b.fcmp(fcc(cc), &arg(0), &arg(1))
            } else {
                b.icmp(icc(cc, inst.op == Op::UICmp), &arg(0), &arg(1))
            };
            b.restore_name(pending);
            b.zext(&c, LTy::I8);
        }
        Op::Select => {
            b.take_name();
            let c = b.icmp("ne", &arg(0), &Val::byte(0));
            for (k, dst) in out.iter().enumerate() {
                b.name_next(dst);
                b.select(
                    &c,
                    &vals[&inst.args[1].index()][k],
                    &vals[&inst.args[2].index()][k],
                );
            }
        }
        Op::B2I => drop(b.zext(&arg(0), LTy::I64)),
        _ => unreachable!("handles lists these ops only"),
    }
}

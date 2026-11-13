//! Scalar values: constants, integer and float arithmetic, comparisons, selects.

use super::{Area, Cx, Vals, faults};
use crate::layout::Layouts;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Cc, Func, Imm, Inst, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    pure_op,
    splits,
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
            | Op::I2F
            | Op::SDiv
            | Op::SRem
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::INegChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::IntOverflowIf
            | Op::IAddOverflow
            | Op::IMulOverflow
            | Op::Shl
            | Op::Sshr
            | Op::Ushr
            | Op::Rotl
            | Op::Rotr
            | Op::Clz
            | Op::Ctz
            | Op::Popcnt
            | Op::FSqrt
            | Op::FAbs
            | Op::FFloor
            | Op::FCeil
            | Op::FTrunc
            | Op::F2IOpt
            | Op::F32Round
            | Op::Conv
    )
}

/// Whether the op can fault when checks are on.
fn checked(op: Op) -> bool {
    matches!(
        op,
        Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::INegChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::IntOverflowIf
    )
}

/// A checked op is not pure: it may fault.
fn pure_op(op: Op) -> bool {
    handles(op) && !checked(op)
}

/// Each check splits the block: a signed division checks for zero and for overflow.
fn splits(_: &Layouts, _: &Func, inst: &Inst, checks: bool) -> usize {
    match inst.op {
        Op::SDivChk if checks => 2,
        op => usize::from(checks && checked(op)),
    }
}

/// A constant is its own text: no register.
fn pre(
    _: &Module,
    _: &Layouts,
    f: &Func,
    inst: &Inst,
    vals: &Vals,
    _: &mut FnBuilder,
) -> Option<Vec<Val>> {
    match (inst.op, inst.imm) {
        // A conversion to anything but `Float32` keeps the register: integers are `i64` and a
        // `Float32` is already a `double`.
        (Op::Conv, _) if inst.res.is_some_and(|r| f.ty(r) != Ty::FLOAT32) => {
            Some(vals[&inst.args[0].index()].clone())
        }
        (Op::IConst, Imm::Int(v)) => Some(vec![Val::int(v)]),
        (Op::FConst, Imm::Float(bits)) => Some(vec![Val::double(bits)]),
        (Op::BConst, Imm::Bool(v)) => Some(vec![Val::bool(v)]),
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
fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
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
    if checked(inst.op) {
        return checked_op(cx, inst, vals, b, &out);
    }
    if inst.op == Op::Conv && out.len() == 1 && out[0].text == arg(0).text {
        return;
    }
    if let Some(done) = bit_or_float_op(inst, &arg, b, &out) {
        return done;
    }
    // A single-leaf result is named in place; `Select` handles several.
    if let ([r], false) = (out.as_slice(), inst.op == Op::Select) {
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
        Op::Not => drop(b.bin(Bin::Xor, &arg(0), &Val::bool(true))),
        Op::ICmp | Op::UICmp | Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            // The result is the comparison's `i1`.
            if inst.op == Op::FCmp {
                b.fcmp(fcc(cc), &arg(0), &arg(1));
            } else {
                b.icmp(icc(cc, inst.op == Op::UICmp), &arg(0), &arg(1));
            }
        }
        Op::Select => {
            let c = arg(0);
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
        Op::I2F => drop(b.sitofp(&arg(0))),
        Op::SDiv => drop(b.bin(Bin::SDiv, &arg(0), &arg(1))),
        Op::SRem => drop(b.bin(Bin::SRem, &arg(0), &arg(1))),
        _ => unreachable!("handles lists these ops only"),
    }
}

/// The overflow-checked integers, division and `IntOverflowIf`. With checks off they wrap, like
/// the plain operations. The result takes its reserved name on the last instruction written,
/// which is in the block after the checks.
fn checked_op(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder, out: &[Val]) {
    let arg = |i: usize| vals[&inst.args[i].index()][0].clone();
    let name = |b: &mut FnBuilder| {
        if let [r] = out {
            b.name_next(r);
        }
    };
    if inst.op == Op::IntOverflowIf {
        if cx.checks {
            faults::fault_if(cx, b, &arg(0), "msrt_fault_int_overflow", &[]);
        }
        return;
    }
    let x = arg(0);
    let y = if inst.args.len() > 1 {
        arg(1)
    } else {
        x.clone()
    };
    let zero = Val::int(0);
    if !cx.checks {
        match inst.op {
            Op::SRemChk => return rem(b, &x, &y, &name),
            _ => name(b),
        }
        match inst.op {
            Op::IAddChk | Op::UAddChk => drop(b.bin(Bin::Add, &x, &y)),
            Op::ISubChk | Op::USubChk => drop(b.bin(Bin::Sub, &x, &y)),
            Op::IMulChk | Op::UMulChk => drop(b.bin(Bin::Mul, &x, &y)),
            Op::INegChk => drop(b.bin(Bin::Sub, &zero, &x)),
            _ => drop(b.bin(Bin::SDiv, &x, &y)),
        }
        return;
    }
    let (with, fault) = match inst.op {
        Op::IAddChk => ("sadd", "msrt_fault_int_overflow"),
        Op::ISubChk => ("ssub", "msrt_fault_int_overflow"),
        Op::IMulChk => ("smul", "msrt_fault_int_overflow"),
        Op::UAddChk => ("uadd", "msrt_fault_int_range"),
        Op::USubChk => ("usub", "msrt_fault_int_range"),
        Op::UMulChk => ("umul", "msrt_fault_int_range"),
        Op::INegChk => ("ssub", "msrt_fault_int_overflow"),
        Op::SDivChk => {
            let z = b.icmp("eq", &y, &zero);
            faults::fault_if(cx, b, &z, "msrt_fault_div_zero", &[]);
            let m1 = b.icmp("eq", &y, &Val::int(-1));
            let mn = b.icmp("eq", &x, &Val::int(i64::MIN));
            let both = b.bin(Bin::And, &m1, &mn);
            faults::fault_if(
                cx,
                b,
                &both,
                "msrt_fault_div_overflow",
                &[x.clone(), y.clone()],
            );
            name(b);
            b.bin(Bin::SDiv, &x, &y);
            return;
        }
        _ => {
            let z = b.icmp("eq", &y, &zero);
            faults::fault_if(cx, b, &z, "msrt_fault_rem_zero", &[]);
            return rem(b, &x, &y, &name);
        }
    };
    name(b);
    let (_, of) = if inst.op == Op::INegChk {
        b.overflow(with, &zero, &x)
    } else {
        b.overflow(with, &x, &y)
    };
    faults::fault_if(cx, b, &of, fault, &[]);
}

/// `x % y` for any `y` but zero: a divisor of -1 is swapped for 1 and the result zeroed, which
/// avoids the hardware trap on `Int.min % -1`.
fn rem(b: &mut FnBuilder, x: &Val, y: &Val, name: &dyn Fn(&mut FnBuilder)) {
    let m1 = b.icmp("eq", y, &Val::int(-1));
    let safe = b.select(&m1, &Val::int(1), y);
    let r = b.bin(Bin::SRem, x, &safe);
    name(b);
    b.select(&m1, &Val::int(0), &r);
}

/// The result takes its reserved name on the next instruction written.
fn name(b: &mut FnBuilder, out: &[Val], k: usize) {
    b.name_next(&out[k]);
}

/// Shifts, rotates, bit counts, float functions and conversions whose result is more than one
/// instruction. `None` for any other op.
fn bit_or_float_op(
    inst: &Inst,
    arg: &dyn Fn(usize) -> Val,
    b: &mut FnBuilder,
    out: &[Val],
) -> Option<()> {
    let intrinsic = |b: &mut FnBuilder, ty: LTy, name_: &str, args: &[Val]| {
        let args: Vec<(Val, &str)> = args.iter().map(|a| (a.clone(), "")).collect();
        b.call_pure(&ty, "", name_, &args).expect("a value")
    };
    match inst.op {
        Op::Shl | Op::Sshr | Op::Ushr => {
            // The machine takes the amount modulo 64; LLVM leaves a larger one undefined.
            let amount = b.bin(Bin::And, &arg(1), &Val::int(63));
            name(b, out, 0);
            let op = match inst.op {
                Op::Shl => Bin::Shl,
                Op::Sshr => Bin::AShr,
                _ => Bin::LShr,
            };
            b.bin(op, &arg(0), &amount);
        }
        Op::Rotl | Op::Rotr => {
            name(b, out, 0);
            let f = if inst.op == Op::Rotl {
                "llvm.fshl.i64"
            } else {
                "llvm.fshr.i64"
            };
            intrinsic(b, LTy::I64, f, &[arg(0), arg(0), arg(1)]);
        }
        Op::Clz | Op::Ctz => {
            name(b, out, 0);
            let f = if inst.op == Op::Clz {
                "llvm.ctlz.i64"
            } else {
                "llvm.cttz.i64"
            };
            // A zero input gives 64, as the machine instruction does.
            intrinsic(b, LTy::I64, f, &[arg(0), Val::bool(false)]);
        }
        Op::Popcnt => {
            name(b, out, 0);
            intrinsic(b, LTy::I64, "llvm.ctpop.i64", &[arg(0)]);
        }
        Op::FSqrt | Op::FAbs | Op::FFloor | Op::FCeil | Op::FTrunc => {
            name(b, out, 0);
            let f = match inst.op {
                Op::FSqrt => "llvm.sqrt.f64",
                Op::FAbs => "llvm.fabs.f64",
                Op::FFloor => "llvm.floor.f64",
                Op::FCeil => "llvm.ceil.f64",
                _ => "llvm.trunc.f64",
            };
            intrinsic(b, LTy::F64, f, &[arg(0)]);
        }
        Op::F32Round | Op::Conv => {
            let narrow = b.fptrunc(&arg(0));
            name(b, out, 0);
            b.fpext(&narrow);
        }
        Op::F2IOpt => {
            // Some(v) when the float is in range, else none with the saturated value as filler.
            let (lo, hi) = (-9223372036854775808.0_f64, 9223372036854775808.0_f64);
            let ge = b.fcmp("oge", &arg(0), &Val::double(lo.to_bits()));
            let lt = b.fcmp("olt", &arg(0), &Val::double(hi.to_bits()));
            name(b, out, 0);
            b.bin(Bin::And, &ge, &lt);
            name(b, out, 1);
            intrinsic(b, LTy::I64, "llvm.fptosi.sat.i64.f64", &[arg(0)]);
        }
        Op::IAddOverflow | Op::IMulOverflow => {
            let with = if inst.op == Op::IAddOverflow {
                "sadd"
            } else {
                "smul"
            };
            let (_, of) = b.overflow(with, &arg(0), &arg(1));
            // The flag is the result; rename it by copying.
            name(b, out, 0);
            b.bin(Bin::Or, &of, &Val::bool(false));
        }
        _ => return None,
    }
    Some(())
}

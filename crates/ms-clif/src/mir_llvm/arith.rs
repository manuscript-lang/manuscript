//! Scalar values: constants, integer and float arithmetic, comparisons, selects.

use super::{Area, Cx, Vals, faults};
use crate::layout::Layouts;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Cc, Func, Imm, Inst, Module, Op};
use ms_mir::types::TyKind;

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
    matches!(
        k,
        TyKind::Unit
            | TyKind::Int
            | TyKind::Float
            | TyKind::Float32
            | TyKind::Bool
            | TyKind::Int8
            | TyKind::Int16
            | TyKind::Int32
            | TyKind::UInt8
            | TyKind::UInt16
            | TyKind::UInt32
            | TyKind::UInt64
    )
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
            | Op::NarrowChk
            | Op::INarrowOpt
    )
}

/// Whether a `Conv` retypes an integer as another integer (floats are not written here).
fn conv_ints(m: &Module, f: &Func, i: &Inst) -> bool {
    let ty = |v| f.ty(v);
    i.res.is_some_and(|r| m.types.is_int(ty(r))) && m.types.is_int(ty(i.args[0]))
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
            | Op::NarrowChk
    )
}

/// A checked op is not pure: it may fault.
fn pure_op(op: Op) -> bool {
    handles(op) && !checked(op)
}

/// Each check splits the block: a signed division checks for zero and for overflow.
fn splits(lay: &Layouts, f: &Func, inst: &Inst, checks: bool) -> usize {
    match inst.op {
        Op::SDivChk if checks && sized(lay, f, inst).is_some_and(|u| u) => 1,
        Op::SDivChk if checks => 2,
        op => usize::from(checks && checked(op)),
    }
}

/// For a checked op that yields a sized integer (narrower than 64 bits): whether it is unsigned.
fn sized(lay: &Layouts, f: &Func, inst: &Inst) -> Option<bool> {
    let ty = f.ty(inst.res?);
    let types = &lay.m.types;
    types.int_bits(ty).filter(|b| *b < 64)?;
    Some(types.is_unsigned(ty))
}

/// The constant `v` of the integer type `ty`, as its text: the value wrapped to the width.
fn lit(ty: &LTy, v: i64) -> Val {
    let text = match ty {
        LTy::I8 => (v as i8).to_string(),
        LTy::I16 => (v as i16).to_string(),
        LTy::I32 => (v as i32).to_string(),
        _ => v.to_string(),
    };
    Val::new(text, ty.clone())
}

/// The smallest value of the signed integer type `ty`.
fn signed_min(ty: &LTy) -> i64 {
    match ty {
        LTy::I8 => i64::from(i8::MIN),
        LTy::I16 => i64::from(i16::MIN),
        LTy::I32 => i64::from(i32::MIN),
        _ => i64::MIN,
    }
}

/// A constant is its own text: no register.
fn pre(
    m: &Module,
    lay: &Layouts,
    f: &Func,
    inst: &Inst,
    vals: &Vals,
    b: &mut FnBuilder,
) -> Option<Vec<Val>> {
    match (inst.op, inst.imm) {
        // A conversion between floats of one width, or any `Float32` rounding of a `float`, is
        // the register itself; `emit` widens or narrows the others.
        (Op::Conv | Op::F32Round, _)
            if !conv_ints(m, f, inst)
                && super::held_leaves(lay, f.ty(inst.args[0]))
                    == super::held_leaves(lay, f.ty(inst.res?)) =>
        {
            Some(vals[&inst.args[0].index()].clone())
        }
        // Whether the value fits, and the value: the register itself when it is a 64-bit one, else
        // its truncation (`narrow_opt`).
        (Op::INarrowOpt, _) => {
            let held = super::held_leaves(lay, f.ty(inst.res?));
            let value = match held[1] {
                LTy::I64 => vals[&inst.args[0].index()][0].clone(),
                _ => b.reserve(held[1].clone()),
            };
            Some(vec![b.reserve(LTy::I1), value])
        }
        (Op::IConst, Imm::Int(v)) => {
            let held = super::held_leaves(lay, f.ty(inst.res?));
            Some(vec![lit(&held[0], v)])
        }
        // A `Float32` constant is written as a `float`; its `double` text is rounded to binary32
        // first, which LLVM requires of the hex form.
        (Op::FConst, Imm::Float(bits)) => {
            let held = super::held_leaves(lay, f.ty(inst.res?));
            let bits = if held[0] == LTy::F32 {
                f64::from(f64::from_bits(bits) as f32).to_bits()
            } else {
                bits
            };
            Some(vec![Val::new(Val::double(bits).text, held[0].clone())])
        }
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
    if inst.op == Op::NarrowChk {
        return narrow_chk(cx, inst, vals, b);
    }
    if inst.op == Op::INarrowOpt {
        return narrow_opt(cx, inst, vals, b);
    }
    if checked(inst.op) {
        return checked_op(cx, inst, vals, b, &out);
    }
    if matches!(inst.op, Op::Conv | Op::F32Round) && out.len() == 1 && out[0].text == arg(0).text {
        return;
    }
    let int_conv = inst.op == Op::Conv && conv_ints(cx.lay.m, cx.f, inst);
    if let Some(done) = (!int_conv)
        .then(|| bit_or_float_op(inst, &arg, b, &out))
        .flatten()
    {
        return done;
    }
    // A single-leaf result is named in place; `Select` handles several.
    if let ([r], false) = (
        out.as_slice(),
        matches!(inst.op, Op::Select | Op::Conv | Op::I2F),
    ) {
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
        Op::INeg => drop(b.bin(Bin::Sub, &lit(&arg(0).ty, 0), &arg(0))),
        Op::FNeg => drop(b.fneg(&arg(0))),
        Op::Not => drop(b.bin(Bin::Xor, &arg(0), &Val::bool(true))),
        Op::ICmp | Op::UICmp | Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            // The result is the comparison's `i1`.
            if inst.op == Op::FCmp {
                b.fcmp(fcc(cc), &arg(0), &arg(1));
            } else {
                // A sized unsigned integer is compared as the unsigned `iN` it is.
                let unsigned =
                    inst.op == Op::UICmp || cx.lay.m.types.is_unsigned(cx.f.ty(inst.args[0]));
                b.icmp(icc(cc, unsigned), &arg(0), &arg(1));
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
        Op::Conv => {
            // The same number as another integer type: extended by the source's signedness, then
            // cut to the target's width (a range check, when one is wanted, comes first).
            let x = widen_int(cx, b, inst, &arg(0));
            let to = out[0].ty.clone();
            b.name_next(&out[0]);
            if to == LTy::I64 {
                // Only a name to give: the register itself.
                b.bin(Bin::Add, &x, &Val::int(0));
            } else {
                b.trunc(&x, to);
            }
        }
        Op::B2I => drop(b.zext(&arg(0), LTy::I64)),
        Op::I2F => {
            let x = widen_int(cx, b, inst, &arg(0));
            b.name_next(&out[0]);
            drop(b.sitofp(&x, out[0].ty.clone()))
        }
        Op::SDiv => drop(b.bin(Bin::SDiv, &arg(0), &arg(1))),
        Op::SRem => drop(b.bin(Bin::SRem, &arg(0), &arg(1))),
        _ => unreachable!("handles lists these ops only"),
    }
}

/// The overflow-checked integers, division and `IntOverflowIf`. With checks off they wrap, like
/// the plain operations. The result takes its reserved name on the last instruction written,
/// which is in the block after the checks.
fn checked_op(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder, out: &[Val]) {
    if let Some(unsigned) = sized(cx.lay, cx.f, inst) {
        return sized_op(cx, inst, vals, b, out, unsigned);
    }
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
            let (op, w) = match inst.op {
                Op::FSqrt => ("sqrt", &arg(0).ty),
                Op::FAbs => ("fabs", &arg(0).ty),
                Op::FFloor => ("floor", &arg(0).ty),
                Op::FCeil => ("ceil", &arg(0).ty),
                _ => ("trunc", &arg(0).ty),
            };
            let f = format!("llvm.{op}.{}", if *w == LTy::F32 { "f32" } else { "f64" });
            intrinsic(b, w.clone(), &f, &[arg(0)]);
        }
        // A `Float32` is a `float` here, so only a change of width writes anything.
        Op::F32Round | Op::Conv => {
            name(b, out, 0);
            if out[0].ty == LTy::F32 {
                b.fptrunc(&arg(0));
            } else {
                b.fpext(&arg(0));
            }
        }
        Op::F2IOpt => {
            // Some(v) when the float is in range, else none with the saturated value as filler.
            let x = if arg(0).ty == LTy::F32 {
                b.fpext(&arg(0))
            } else {
                arg(0)
            };
            let (lo, hi) = (-9223372036854775808.0_f64, 9223372036854775808.0_f64);
            let ge = b.fcmp("oge", &x, &Val::double(lo.to_bits()));
            let lt = b.fcmp("olt", &x, &Val::double(hi.to_bits()));
            name(b, out, 0);
            b.bin(Bin::And, &ge, &lt);
            name(b, out, 1);
            intrinsic(b, LTy::I64, "llvm.fptosi.sat.i64.f64", &[x]);
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

/// `NarrowChk`: the 64-bit register as a sized integer, faulting when it is outside the range.
fn narrow_chk(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let x = vals[&inst.args[0].index()][0].clone();
    let out = vals[&inst.res.expect("a result").index()][0].clone();
    if cx.checks {
        let (lo, hi) = cx
            .lay
            .m
            .types
            .int_range(cx.f.ty(inst.res.expect("a result")))
            .unwrap_or((i64::MIN.into(), i64::MAX.into()));
        let below = b.icmp("slt", &x, &Val::int(lo as i64));
        let above = b.icmp("sgt", &x, &Val::int(hi as i64));
        let bad = b.bin(Bin::Or, &below, &above);
        faults::fault_if(cx, b, &bad, "msrt_fault_int_range", &[]);
    }
    b.name_next(&out);
    b.trunc(&x, out.ty.clone());
}

/// `INarrowOpt`: `[fits, value]`, where it fits when the integer is inside the range of the
/// optional's integer type; the value is the register truncated to that type.
fn narrow_opt(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let m = cx.lay.m;
    let x = widen_int(cx, b, inst, &vals[&inst.args[0].index()][0]);
    let res = cx.f.ty(inst.res.expect("a result"));
    let (lo, hi) = m.opt_inner(res).map_or((i64::MIN, i64::MAX), |inner| {
        m.types.narrow_range(cx.f.ty(inst.args[0]), inner)
    });
    let out = &vals[&inst.res.expect("a result").index()];
    let ge = b.icmp("sge", &x, &Val::int(lo));
    let le = b.icmp("sle", &x, &Val::int(hi));
    b.name_next(&out[0]);
    b.bin(Bin::And, &ge, &le);
    if out[1].ty != LTy::I64 {
        b.name_next(&out[1]);
        b.trunc(&x, out[1].ty.clone());
    }
}

/// A checked op on a sized integer, computed in its own width: the overflow of `iN` is the range
/// fault of the type, and an unsigned type uses the unsigned operations.
fn sized_op(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder, out: &[Val], unsigned: bool) {
    let x = vals[&inst.args[0].index()][0].clone();
    let y = vals.get(&inst.args.get(1).map_or(usize::MAX, |a| a.index()));
    let y = y.map_or_else(|| x.clone(), |v| v[0].clone());
    let ty = x.ty.clone();
    let zero = lit(&ty, 0);
    let name = |b: &mut FnBuilder| {
        if let [r] = out {
            b.name_next(r);
        }
    };
    let range = "msrt_fault_int_range";
    match inst.op {
        Op::IAddChk | Op::ISubChk | Op::IMulChk | Op::INegChk if !cx.checks => {
            name(b);
            match inst.op {
                Op::IAddChk => drop(b.bin(Bin::Add, &x, &y)),
                Op::ISubChk => drop(b.bin(Bin::Sub, &x, &y)),
                Op::IMulChk => drop(b.bin(Bin::Mul, &x, &y)),
                _ => drop(b.bin(Bin::Sub, &zero, &x)),
            }
        }
        Op::IAddChk | Op::ISubChk | Op::IMulChk | Op::INegChk => {
            let kind = match inst.op {
                Op::IAddChk => "add",
                Op::ISubChk | Op::INegChk => "sub",
                _ => "mul",
            };
            let with = format!("{}{kind}", if unsigned { "u" } else { "s" });
            name(b);
            let (_, of) = if inst.op == Op::INegChk {
                b.overflow(&with, &zero, &x)
            } else {
                b.overflow(&with, &x, &y)
            };
            faults::fault_if(cx, b, &of, range, &[]);
        }
        Op::SDivChk => {
            if cx.checks {
                let z = b.icmp("eq", &y, &zero);
                faults::fault_if(cx, b, &z, "msrt_fault_div_zero", &[]);
                if !unsigned {
                    let m1 = b.icmp("eq", &y, &lit(&ty, -1));
                    let mn = b.icmp("eq", &x, &lit(&ty, signed_min(&ty)));
                    let both = b.bin(Bin::And, &m1, &mn);
                    faults::fault_if(cx, b, &both, range, &[]);
                }
            }
            name(b);
            b.bin(if unsigned { Bin::UDiv } else { Bin::SDiv }, &x, &y);
        }
        _ => {
            if cx.checks {
                let z = b.icmp("eq", &y, &zero);
                faults::fault_if(cx, b, &z, "msrt_fault_rem_zero", &[]);
            }
            if unsigned {
                name(b);
                b.bin(Bin::URem, &x, &y);
            } else {
                // A divisor of -1 is swapped for 1 and the result zeroed, which avoids the trap on
                // the type's minimum.
                let m1 = b.icmp("eq", &y, &lit(&ty, -1));
                let safe = b.select(&m1, &lit(&ty, 1), &y);
                let r = b.bin(Bin::SRem, &x, &safe);
                name(b);
                b.select(&m1, &zero, &r);
            }
        }
    }
}

/// The register `x` of an integer operand as an `i64`, extended by its type's signedness.
fn widen_int(cx: &Cx, b: &mut FnBuilder, inst: &Inst, x: &Val) -> Val {
    if x.ty == LTy::I64 {
        return x.clone();
    }
    if cx.lay.m.types.is_unsigned(cx.f.ty(inst.args[0])) {
        b.zext(x, LTy::I64)
    } else {
        b.sext(x, LTy::I64)
    }
}

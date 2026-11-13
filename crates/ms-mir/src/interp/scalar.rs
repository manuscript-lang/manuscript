//! Interpreter rules for constants, integer, bit, comparison and float instructions.
//!
//! Each function handles one op family; `Interp::step` routes to it.

use super::*;

impl Interp<'_> {
    /// Constants, integer arithmetic and bit operations.
    pub(super) fn constants_and_integers(
        &mut self,
        f: &Func,
        regs: &mut [Val],
        inst: &Inst,
    ) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        let m = self.m;
        // A checked result faults when it overflows or leaves the range of its sized type.
        let sized = |v: Option<i64>| -> R<Val> {
            let v = v.ok_or_else(overflow)?;
            let range = inst
                .res
                .filter(|r| {
                    m.types
                        .int_bits(f.values[r.index()])
                        .is_some_and(|b| b < 64)
                })
                .and_then(|r| m.types.int_range(f.values[r.index()]));
            match range {
                Some((lo, hi)) if !(lo..=hi).contains(&i128::from(v)) => Err(overflow()),
                _ => Ok(Val::Int(v)),
            }
        };
        match inst.op {
            Op::IConst => ops.set(Val::Int(imm_int(inst.imm))),
            Op::FConst => ops.set(Val::Float(inst.imm.float())),
            Op::BConst => ops.set(Val::Bool(matches!(inst.imm, Imm::Bool(true)))),
            Op::UnitConst => ops.set(Val::Unit),
            Op::StrLit => {
                let Imm::Str(s) = inst.imm else {
                    return Err(Raw::internal("str without literal"));
                };
                ops.set(Val::Str(self.strings[s.index()].clone()));
            }
            Op::BytesLit => {
                let data = &self.m.blobs[imm_int(inst.imm) as usize];
                ops.set(Val::List(Rc::new(
                    data.iter().map(|&b| Val::Int(i64::from(b))).collect(),
                )));
            }
            Op::IAdd => ops.set(Val::Int(ops.int(0)?.wrapping_add(ops.int(1)?))),
            Op::ISub => ops.set(Val::Int(ops.int(0)?.wrapping_sub(ops.int(1)?))),
            Op::IMul => ops.set(Val::Int(ops.int(0)?.wrapping_mul(ops.int(1)?))),
            Op::INeg => ops.set(Val::Int(ops.int(0)?.wrapping_neg())),
            Op::IAddOverflow => ops.set(Val::Bool(ops.int(0)?.overflowing_add(ops.int(1)?).1)),
            Op::IMulOverflow => ops.set(Val::Bool(ops.int(0)?.overflowing_mul(ops.int(1)?).1)),
            Op::IntOverflowIf => {
                if ops.boolean(0)? {
                    return Err(overflow());
                }
            }
            Op::NarrowChk => {
                let (lo, hi) = m
                    .types
                    .int_range(inst.res.map_or(Ty::INT, |r| f.values[r.index()]))
                    .unwrap_or((i64::MIN.into(), i64::MAX.into()));
                let v = ops.int(0)?;
                if !(lo..=hi).contains(&i128::from(v)) {
                    return Err(overflow());
                }
                ops.set(Val::Int(v));
            }
            Op::Conv => {
                let to32 = inst.res.is_some_and(|r| f.values[r.index()] == Ty::FLOAT32);
                match &ops.regs[inst.args[0].index()] {
                    Val::Float(x) if to32 => ops.set(Val::Float(*x as f32 as f64)),
                    v => ops.set(v.clone()),
                }
            }
            Op::INarrowOpt => {
                let v = ops.int(0)?;
                let inner = inst.res.and_then(|r| m.opt_inner(f.values[r.index()]));
                let (lo, hi) = inner.map_or((i64::MIN, i64::MAX), |i| {
                    m.types.narrow_range(f.values[inst.args[0].index()], i)
                });
                let fits = (lo..=hi).contains(&v);
                ops.set(Val::Opt(fits.then(|| Rc::new(Val::Int(v)))));
            }
            Op::F32Round => ops.set(Val::Float(ops.float(0)? as f32 as f64)),
            Op::IAddChk => ops.set(sized(ops.int(0)?.checked_add(ops.int(1)?))?),
            Op::ISubChk => ops.set(sized(ops.int(0)?.checked_sub(ops.int(1)?))?),
            Op::IMulChk => ops.set(sized(ops.int(0)?.checked_mul(ops.int(1)?))?),
            Op::UAddChk | Op::USubChk | Op::UMulChk => {
                let (x, y) = (ops.int(0)? as u64, ops.int(1)? as u64);
                let r = match inst.op {
                    Op::UAddChk => x.checked_add(y),
                    Op::USubChk => x.checked_sub(y),
                    _ => x.checked_mul(y),
                };
                ops.set(Val::Int(r.ok_or_else(overflow)? as i64))
            }
            Op::INegChk => ops.set(sized(ops.int(0)?.checked_neg())?),
            Op::SDivChk => {
                let (x, y) = (ops.int(0)?, ops.int(1)?);
                if y == 0 {
                    return Err(div0());
                }
                ops.set(sized(x.checked_div(y))?);
            }
            Op::SRemChk => {
                let (x, y) = (ops.int(0)?, ops.int(1)?);
                if y == 0 {
                    return Err(div0());
                }
                ops.set(Val::Int(x.wrapping_rem(y)));
            }
            Op::SDiv | Op::SRem => {
                let (x, y) = (ops.int(0)?, ops.int(1)?);
                if y == 0 {
                    return Err(div0());
                }
                ops.set(Val::Int(if inst.op == Op::SDiv {
                    x.wrapping_div(y)
                } else {
                    x.wrapping_rem(y)
                }));
            }
            Op::And | Op::Or | Op::Xor => {
                let r = match (
                    &ops.regs[inst.args[0].index()],
                    &ops.regs[inst.args[1].index()],
                ) {
                    (Val::Int(x), Val::Int(y)) => Val::Int(match inst.op {
                        Op::And => x & y,
                        Op::Or => x | y,
                        _ => x ^ y,
                    }),
                    (Val::Bool(x), Val::Bool(y)) => Val::Bool(match inst.op {
                        Op::And => x & y,
                        Op::Or => x | y,
                        _ => x ^ y,
                    }),
                    _ => {
                        return Err(Raw::internal(
                            "bitwise operands must be both int or both bool",
                        ));
                    }
                };
                ops.set(r);
            }
            Op::Shl => ops.set(Val::Int(ops.int(0)?.wrapping_shl(ops.int(1)? as u32))),
            Op::Sshr => ops.set(Val::Int(ops.int(0)?.wrapping_shr(ops.int(1)? as u32))),
            Op::Ushr => ops.set(Val::Int(
                ((ops.int(0)? as u64).wrapping_shr(ops.int(1)? as u32)) as i64,
            )),
            Op::Rotl => ops.set(Val::Int(
                (ops.int(0)? as u64).rotate_left((ops.int(1)? & 63) as u32) as i64,
            )),
            Op::Rotr => ops.set(Val::Int(
                (ops.int(0)? as u64).rotate_right((ops.int(1)? & 63) as u32) as i64,
            )),
            Op::Clz => ops.set(Val::Int(i64::from(ops.int(0)?.leading_zeros()))),
            Op::Ctz => ops.set(Val::Int(i64::from(ops.int(0)?.trailing_zeros()))),
            Op::Popcnt => ops.set(Val::Int(i64::from(ops.int(0)?.count_ones()))),
            Op::Not => ops.set(Val::Bool(!ops.boolean(0)?)),

            _ => unreachable!("constants_and_integers is only called for its own ops"),
        }
        Ok(Flow::Next)
    }

    /// Comparisons, float arithmetic and conversions, and `select`.
    pub(super) fn comparisons_and_floats(
        &mut self,
        f: &Func,
        regs: &mut [Val],
        inst: &Inst,
    ) -> R<Flow> {
        let mut ops = Operands { regs, inst };
        match inst.op {
            Op::UICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Err(Raw::internal("uicmp without condition"));
                };
                ops.set(Val::Bool(cc.eval_uint(ops.int(0)?, ops.int(1)?)));
            }
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Err(Raw::internal("icmp without condition"));
                };
                let word = |v: &Val| match v {
                    Val::Int(i) => Some(*i),
                    Val::Bool(b) => Some(*b as i64),
                    _ => None,
                };
                let (Some(x), Some(y)) = (
                    word(&ops.regs[inst.args[0].index()]),
                    word(&ops.regs[inst.args[1].index()]),
                ) else {
                    return Err(Raw::internal("icmp operands must be int or bool"));
                };
                ops.set(Val::Bool(cc.eval_int(x, y)));
            }
            Op::FCmp => {
                let Imm::Cc(cc) = inst.imm else {
                    return Err(Raw::internal("fcmp without condition"));
                };
                ops.set(Val::Bool(cc.eval_float(ops.float(0)?, ops.float(1)?)));
            }
            Op::FAdd => ops.set(Val::Float(ops.float(0)? + ops.float(1)?)),
            Op::FSub => ops.set(Val::Float(ops.float(0)? - ops.float(1)?)),
            Op::FMul => ops.set(Val::Float(ops.float(0)? * ops.float(1)?)),
            Op::FDiv => ops.set(Val::Float(ops.float(0)? / ops.float(1)?)),
            Op::FNeg => ops.set(Val::Float(-ops.float(0)?)),
            Op::FSqrt => ops.set(Val::Float(ops.float(0)?.sqrt())),
            Op::FFloor => ops.set(Val::Float(ops.float(0)?.floor())),
            Op::FCeil => ops.set(Val::Float(ops.float(0)?.ceil())),
            Op::FTrunc => ops.set(Val::Float(ops.float(0)?.trunc())),
            Op::FAbs => ops.set(Val::Float(ops.float(0)?.abs())),
            Op::I2F => {
                let x = ops.int(0)?;
                let value = if inst.res.is_some_and(|r| f.ty(r) == Ty::FLOAT32) {
                    (x as f32) as f64
                } else {
                    x as f64
                };
                ops.set(Val::Float(value));
            }
            Op::F2IOpt => {
                let x = ops.float(0)?;
                let ok = x.is_finite() && (-I64_RANGE..I64_RANGE).contains(&x);
                ops.set(Val::Opt(ok.then(|| Rc::new(Val::Int(x as i64)))));
            }
            Op::B2I => ops.set(Val::Int(ops.boolean(0)? as i64)),
            Op::Select => {
                let pick = if ops.boolean(0)? { 1 } else { 2 };
                ops.set(ops.regs[inst.args[pick].index()].clone());
            }

            _ => unreachable!("comparisons_and_floats is only called for its own ops"),
        }
        Ok(Flow::Next)
    }
}

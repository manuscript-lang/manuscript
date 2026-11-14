//! Cranelift lowering of constants, integer, bit, comparison and float instructions.
//!
//! Each function handles one op family; [`Lower::lower_inst`] routes to it.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Constants.
    pub(super) fn constants(&mut self, f: &Func, inst: &Inst) -> Vs {
        let res_ty = inst.res.map(|r| f.ty(r));
        match inst.op {
            Op::IConst => {
                let Imm::Int(v) = inst.imm else {
                    unreachable!()
                };
                vec![self.iconst(v)]
            }
            Op::FConst if res_ty == Some(Ty::FLOAT32) => {
                vec![self.b.ins().f32const(inst.imm.float() as f32)]
            }
            Op::FConst => vec![self.b.ins().f64const(inst.imm.float())],
            Op::BConst => {
                let Imm::Bool(v) = inst.imm else {
                    unreachable!()
                };
                vec![self.b.ins().iconst(types::I8, v as i64)]
            }
            Op::UnitConst => vec![],
            Op::StrLit => {
                let Imm::Str(s) = inst.imm else {
                    unreachable!()
                };
                if let Some(r) = inst.res {
                    self.str_lits.insert(r.index(), s.0);
                }
                let bytes = self.g.m.strings[s.0 as usize].as_bytes();
                if bytes.len() <= STR_INLINE_MAX {
                    // A short literal is an inline string: constant words, no data symbol, and
                    // comparisons with other short strings decide from the second word.
                    let bits = bytes
                        .iter()
                        .enumerate()
                        .fold(0u128, |acc, (i, b)| acc | (*b as u128) << (8 * i));
                    let lo = bits as u64 as i64;
                    let hi = ((bits >> 64) as u64 as usize
                        | STR_INLINE
                        | (bytes.len() << STR_INLINE_LEN_SHIFT))
                        as i64;
                    return vec![self.iconst(lo), self.iconst(hi)];
                }
                let d = self.g.str_lit(s.0);
                let base = self.data_addr(d);
                let ptr = base;
                let len = self.g.m.strings[s.0 as usize].len() as i64;
                let tagged = self.iconst(len | STR_STATIC as i64);
                vec![ptr, tagged]
            }
            Op::BytesLit => {
                let Imm::Int(i) = inst.imm else {
                    unreachable!()
                };
                let n = self.g.m.blobs[i as usize].len() as i64;
                if n == 0 {
                    let z = self.iconst(0);
                    vec![z, z, z]
                } else {
                    let data = self.g.blob(i as usize);
                    let ptr = self.data_addr(data);
                    // Capacity zero marks the bytes as borrowed: nothing frees them.
                    let (len, cap) = (self.iconst(n), self.iconst(0));
                    vec![ptr, len, cap]
                }
            }
            _ => unreachable!("constants is only called for its own ops"),
        }
    }

    /// Wrapping integer arithmetic and unchecked division.
    pub(super) fn integer_ops(
        &mut self,
        inst: &Inst,
        previous_overflow: Option<(Op, Value, Value, Value)>,
    ) -> Vs {
        match inst.op {
            Op::IAdd => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if let Some((Op::IAdd, _, _, v)) =
                    previous_overflow.filter(|p| p.1 == x && p.2 == y)
                {
                    v
                } else {
                    self.b.ins().iadd(x, y)
                }
            }],
            Op::ISub => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().isub(x, y)
            }],
            Op::IMul => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if let Some((Op::IMul, _, _, v)) =
                    previous_overflow.filter(|p| p.1 == x && p.2 == y)
                {
                    v
                } else {
                    self.mul(x, y)
                }
            }],
            Op::INeg => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().ineg(x)
            }],
            Op::F32Round => vec![{
                let x = self.a(inst, 0)[0];
                self.float_as(x, types::F32)
            }],
            Op::SDiv => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.divide(x, y)
            }],
            Op::SRem => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.remainder(x, y)
            }],
            _ => unreachable!("integer_ops is only called for its own ops"),
        }
    }

    /// Faults with `msrt_fault_int_range` when the register `x` is outside the range of the
    /// sized integer type `ty`.
    fn fault_out_of_range(&mut self, x: Value, ty: Ty) {
        let (lo, hi) = self
            .g
            .lay
            .m
            .types
            .int_range(ty)
            .unwrap_or((i64::MIN.into(), i64::MAX.into()));
        let (lo_k, hi_k) = (
            self.b.ins().iconst(types::I64, lo as i64),
            self.b.ins().iconst(types::I64, hi as i64),
        );
        let lo = self.b.ins().icmp(IntCC::SignedLessThan, x, lo_k);
        let hi = self.b.ins().icmp(IntCC::SignedGreaterThan, x, hi_k);
        let bad = self.b.ins().bor(lo, hi);
        self.fault_if(bad, "msrt_fault_int_range", vec![]);
    }

    /// A checked integer result of a sized type is also checked against the type's range.
    pub(super) fn range_check_sized(&mut self, f: &Func, inst: &Inst, vs: Vs) -> Vs {
        let sized = inst.res.map(|r| f.ty(r)).filter(|t| {
            self.g.lay.m.types.int_bits(*t).is_some_and(|b| b < 64)
                && !matches!(inst.op, Op::NarrowChk | Op::INarrowOpt | Op::Conv)
        });
        if let (Some(t), true, Some(x)) = (sized, self.g.opts.checks, vs.first().copied()) {
            self.fault_out_of_range(x, t);
        }
        vs
    }

    /// Overflow-checked integer arithmetic, narrowing and conversions.
    pub(super) fn checked_integer_ops(&mut self, f: &Func, inst: &Inst) -> Vs {
        let checks = self.g.opts.checks;
        let res_ty = inst.res.map(|r| f.ty(r));
        match inst.op {
            Op::IAddOverflow | Op::IMulOverflow => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                let (v, of) = if inst.op == Op::IAddOverflow {
                    self.b.ins().sadd_overflow(x, y)
                } else {
                    self.mul_overflow(x, y)
                };
                self.overflow_result = Some((
                    if inst.op == Op::IAddOverflow {
                        Op::IAdd
                    } else {
                        Op::IMul
                    },
                    x,
                    y,
                    v,
                ));
                vec![of]
            }
            Op::IntOverflowIf => {
                if checks {
                    self.fault_if(self.a(inst, 0)[0], "msrt_fault_int_overflow", vec![]);
                }
                vec![]
            }
            Op::NarrowChk => {
                let x = self.a(inst, 0)[0];
                if checks {
                    self.fault_out_of_range(x, res_ty.unwrap_or(Ty::INT));
                }
                vec![x]
            }
            Op::Conv => {
                let x = self.a(inst, 0)[0];
                let to = if res_ty == Some(Ty::FLOAT32) {
                    types::F32
                } else {
                    types::F64
                };
                vec![self.float_as(x, to)]
            }
            Op::INarrowOpt => {
                let x = self.a(inst, 0)[0];
                let inner = res_ty.and_then(|r| self.g.lay.m.opt_inner(r));
                let from = f.ty(inst.args[0]);
                let (lo, hi) = inner.map_or((i64::MIN, i64::MAX), |i| {
                    self.g.lay.m.types.narrow_range(from, i)
                });
                let (lo_k, hi_k) = (
                    self.b.ins().iconst(types::I64, lo),
                    self.b.ins().iconst(types::I64, hi),
                );
                let ge = self.b.ins().icmp(IntCC::SignedGreaterThanOrEqual, x, lo_k);
                let le = self.b.ins().icmp(IntCC::SignedLessThanOrEqual, x, hi_k);
                let ok = self.b.ins().band(ge, le);
                vec![ok, x]
            }
            Op::IAddChk | Op::ISubChk | Op::IMulChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if !checks {
                    vec![match inst.op {
                        Op::IAddChk => self.b.ins().iadd(x, y),
                        Op::ISubChk => self.b.ins().isub(x, y),
                        _ => self.mul(x, y),
                    }]
                } else {
                    let (v, of) = match inst.op {
                        Op::IAddChk => self.b.ins().sadd_overflow(x, y),
                        Op::ISubChk => self.b.ins().ssub_overflow(x, y),
                        _ => self.mul_overflow(x, y),
                    };
                    self.fault_if(of, "msrt_fault_int_overflow", vec![]);
                    vec![v]
                }
            }
            Op::UAddChk | Op::USubChk | Op::UMulChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if !checks {
                    vec![match inst.op {
                        Op::UAddChk => self.b.ins().iadd(x, y),
                        Op::USubChk => self.b.ins().isub(x, y),
                        _ => self.mul(x, y),
                    }]
                } else {
                    let (v, of) = match inst.op {
                        Op::UAddChk => self.b.ins().uadd_overflow(x, y),
                        Op::USubChk => self.b.ins().usub_overflow(x, y),
                        _ => self.b.ins().umul_overflow(x, y),
                    };
                    self.fault_if(of, "msrt_fault_int_range", vec![]);
                    vec![v]
                }
            }
            Op::INegChk => {
                let x = self.a(inst, 0)[0];
                if checks {
                    let z = self.iconst(0);
                    let (v, of) = self.b.ins().ssub_overflow(z, x);
                    self.fault_if(of, "msrt_fault_int_overflow", vec![]);
                    vec![v]
                } else {
                    vec![self.b.ins().ineg(x)]
                }
            }
            Op::SDivChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if checks {
                    let z = self.b.ins().icmp_imm_s(IntCC::Equal, y, 0);
                    self.fault_if(z, "msrt_fault_div_zero", vec![]);
                    let m1 = self.b.ins().icmp_imm_s(IntCC::Equal, y, -1);
                    let mn = self.b.ins().icmp_imm_s(IntCC::Equal, x, i64::MIN);
                    let both = self.b.ins().band(m1, mn);
                    self.fault_if(both, "msrt_fault_div_overflow", vec![x, y]);
                }
                vec![self.divide(x, y)]
            }
            Op::SRemChk => {
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                if checks {
                    let z = self.b.ins().icmp_imm_s(IntCC::Equal, y, 0);
                    self.fault_if(z, "msrt_fault_rem_zero", vec![]);
                }
                vec![self.remainder(x, y)]
            }
            _ => unreachable!("checked_integer_ops is only called for its own ops"),
        }
    }

    /// `x / y` for a divisor known to be nonzero and, with `x` the minimum, not -1. A remainder
    /// of the same operands earlier in the block has divided already: reuse its quotient.
    fn divide(&mut self, x: Value, y: Value) -> Value {
        if let Some(&q) = self.safe_quotients.get(&(x, y)) {
            // That quotient divided by 1 when `y` is -1, where the true one is `-x`.
            let m1 = self.b.ins().icmp_imm_s(IntCC::Equal, y, -1);
            let neg = self.b.ins().ineg(x);
            return self.b.ins().select(m1, neg, q);
        }
        let q = self.b.ins().sdiv(x, y);
        self.quotients.insert((x, y), q);
        q
    }

    /// `x % y` for a nonzero divisor (a divisor of -1 gives 0). One plain divide whose quotient a
    /// later `x / y` in the block reuses, or the quotient an earlier one left: x86 divides once
    /// for both, and Cranelift would divide twice.
    fn remainder(&mut self, x: Value, y: Value) -> Value {
        let (q, d) = if let Some(&q) = self.quotients.get(&(x, y)) {
            (q, y)
        } else {
            let m1 = self.b.ins().icmp_imm_s(IntCC::Equal, y, -1);
            let one = self.iconst(1);
            let safe = self.b.ins().select(m1, one, y);
            let q = self.b.ins().sdiv(x, safe);
            self.safe_quotients.insert((x, y), q);
            (q, safe)
        };
        let p = self.b.ins().imul(q, d);
        self.b.ins().isub(x, p)
    }

    /// Bit operations and booleans.
    pub(super) fn bit_ops(&mut self, inst: &Inst) -> Vs {
        match inst.op {
            Op::And => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().band(x, y)
            }],
            Op::Or => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().bor(x, y)
            }],
            Op::Xor => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().bxor(x, y)
            }],
            Op::Shl => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().ishl(x, y)
            }],
            Op::Sshr => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().sshr(x, y)
            }],
            Op::Ushr => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().ushr(x, y)
            }],
            Op::Rotl => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().rotl(x, y)
            }],
            Op::UMulHi => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().umulhi(x, y)
            }],
            Op::Rotr => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().rotr(x, y)
            }],
            Op::Clz => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().clz(x)
            }],
            Op::Ctz => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().ctz(x)
            }],
            Op::Popcnt => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().popcnt(x)
            }],
            Op::Not => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().bxor_imm_s(x, 1)
            }],
            _ => unreachable!("bit_ops is only called for its own ops"),
        }
    }

    /// Comparisons and `select`.
    pub(super) fn comparisons(&mut self, inst: &Inst) -> Vs {
        match inst.op {
            Op::UICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    unreachable!()
                };
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                let cc = match cc {
                    Cc::Eq => IntCC::Equal,
                    Cc::Ne => IntCC::NotEqual,
                    Cc::Lt => IntCC::UnsignedLessThan,
                    Cc::Le => IntCC::UnsignedLessThanOrEqual,
                    Cc::Gt => IntCC::UnsignedGreaterThan,
                    Cc::Ge => IntCC::UnsignedGreaterThanOrEqual,
                };
                vec![self.b.ins().icmp(cc, x, y)]
            }
            Op::ICmp => {
                let Imm::Cc(cc) = inst.imm else {
                    unreachable!()
                };
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                vec![self.b.ins().icmp(Self::icc(cc), x, y)]
            }
            Op::FCmp => {
                let Imm::Cc(cc) = inst.imm else {
                    unreachable!()
                };
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                vec![self.b.ins().fcmp(Self::fcc(cc), x, y)]
            }
            Op::Select => {
                let c = self.a(inst, 0)[0];
                let (t, e) = (self.a(inst, 1), self.a(inst, 2));
                t.iter()
                    .zip(&e)
                    .map(|(x, y)| self.b.ins().select(c, *x, *y))
                    .collect()
            }
            _ => unreachable!("comparisons is only called for its own ops"),
        }
    }

    /// Float arithmetic and numeric conversions.
    pub(super) fn float_ops(&mut self, f: &Func, inst: &Inst) -> Vs {
        let res_ty = inst.res.map(|r| f.ty(r));
        match inst.op {
            Op::FAdd => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fadd(x, y)
            }],
            Op::FSub => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fsub(x, y)
            }],
            Op::FMul => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fmul(x, y)
            }],
            Op::FDiv => vec![{
                let (x, y) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
                self.b.ins().fdiv(x, y)
            }],
            Op::FNeg => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().fneg(x)
            }],
            Op::FSqrt => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().sqrt(x)
            }],
            Op::FFloor => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().floor(x)
            }],
            Op::FCeil => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().ceil(x)
            }],
            Op::FTrunc => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().trunc(x)
            }],
            Op::FAbs => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().fabs(x)
            }],
            Op::I2F => vec![{
                let x = self.a(inst, 0)[0];
                if res_ty == Some(Ty::FLOAT32) {
                    self.b.ins().fcvt_from_sint(types::F32, x)
                } else {
                    self.b.ins().fcvt_from_sint(types::F64, x)
                }
            }],
            Op::F2IOpt => {
                let v = self.a(inst, 0)[0];
                let v = self.float_as(v, types::F64);
                let lo = self.b.ins().f64const(-9223372036854775808.0);
                let hi = self.b.ins().f64const(9223372036854775808.0);
                let ge = self.b.ins().fcmp(FloatCC::GreaterThanOrEqual, v, lo);
                let lt = self.b.ins().fcmp(FloatCC::LessThan, v, hi);
                let ok = self.b.ins().band(ge, lt);
                vec![ok, self.b.ins().fcvt_to_sint_sat(types::I64, v)]
            }
            Op::B2I => vec![{
                let x = self.a(inst, 0)[0];
                self.b.ins().uextend(types::I64, x)
            }],
            _ => unreachable!("float_ops is only called for its own ops"),
        }
    }
}

//! C ABI shims for `@std/decimal.ms`. A `Decimal` crosses as a pointer to [`Dec`] and results come
//! back through a trailing `out` pointer.

use crate::{Dec, Mode, Overflow, RoundFail, overflow_message};
use alloc::string::String;
use ms_rt::ffi::{
    Out, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE, Status, abi_record, fault, native,
};

abi_record! {
    /// The record layout of [`Dec`] across the ABI.
    pub struct DecRec {
        pub lo: u64,
        pub hi: i64,
        pub exp: i64,
    }
}

impl From<&DecRec> for Dec {
    fn from(r: &DecRec) -> Dec {
        Dec {
            lo: r.lo,
            hi: r.hi,
            exp: r.exp,
        }
    }
}

impl From<Dec> for DecRec {
    fn from(d: Dec) -> DecRec {
        DecRec {
            lo: d.lo,
            hi: d.hi,
            exp: d.exp,
        }
    }
}

fn checked(r: Result<Dec, Overflow>, operation: &str, left: Dec, right: Dec) -> Dec {
    match r {
        Ok(v) => v,
        Err(Overflow::Magnitude) => fault(&overflow_message(operation, &left, &right)),
    }
}

impl Status for RoundFail {
    fn status(self) -> u8 {
        match self {
            RoundFail::InvalidInput => STATUS_INVALID_INPUT,
            RoundFail::OutOfRange => STATUS_OUT_OF_RANGE,
        }
    }
}

fn mode_of(has: bool, index: i64) -> Result<Mode, RoundFail> {
    if !has {
        return Ok(Mode::HalfEven);
    }
    Mode::from_index(index).ok_or(RoundFail::InvalidInput)
}

macro_rules! binary {
    ($name:ident, $method:ident, $op:literal) => {
        native! {
            fn $name(a: &DecRec, b: &DecRec) -> out DecRec {
                let (a, b) = (Dec::from(a), Dec::from(b));
                checked(a.$method(&b), $op, a, b).into()
            }
        }
    };
}

binary!(msstd_decimal_add, add, "+");
binary!(msstd_decimal_subtract, subtract, "-");
binary!(msstd_decimal_multiply, multiply, "*");

native! {
    fn msstd_decimal_literal(text: &str) -> out DecRec {
        Dec::parse(text)
            .unwrap_or_else(|| fault("invalid or inexact Decimal literal"))
            .into()
    }

    /// The Decimal of runtime text, or `InvalidInput` when it is malformed or not exactly representable.
    fn msstd_decimal_parse(text: &str) -> Result<DecRec, RoundFail> {
        Dec::parse(text)
            .map(DecRec::from)
            .ok_or(RoundFail::InvalidInput)
    }

    fn msstd_decimal_from_int(n: i64) -> out DecRec {
        Dec::from_int(n).into()
    }

    fn msstd_decimal_from_uint(n: i64) -> out DecRec {
        Dec::from_uint(n as u64).into()
    }

    fn msstd_decimal_divide(a: &DecRec, b: &DecRec) -> out DecRec {
        let (a, b) = (Dec::from(a), Dec::from(b));
        if b.is_zero() {
            fault("Decimal./: division by zero; right must be nonzero, found 0");
        }
        checked(a.divide(&b), "/", a, b).into()
    }

    fn msstd_decimal_negate(a: &DecRec) -> out DecRec {
        Dec::from(a).negate().into()
    }

    fn msstd_decimal_compare(a: &DecRec, b: &DecRec) -> i64 {
        Dec::from(a).compare(&Dec::from(b))
    }

    fn msstd_decimal_to_string(a: &DecRec) -> String {
        Dec::from(a).render()
    }

    fn msstd_decimal_to_float(a: &DecRec) -> f64 {
        Dec::from(a).to_float()
    }

    /// `true` and `out` written when the truncated value fits an `Int`.
    fn msstd_decimal_truncate_to_int(a: &DecRec, out: Out<i64>) -> bool {
        match Dec::from(a).truncate_to_int() {
            Some(n) => {
                out.write(n);
                true
            }
            None => false,
        }
    }

    fn msstd_decimal_round(
        value: &DecRec,
        places: i64,
        has_mode: bool,
        mode: i64,
    ) -> Result<DecRec, RoundFail> {
        Dec::from(value)
            .round(places, mode_of(has_mode, mode)?)
            .map(DecRec::from)
    }

    fn msstd_decimal_to_fixed(
        value: &DecRec,
        digits: i64,
        has_mode: bool,
        mode: i64,
    ) -> Result<String, RoundFail> {
        Dec::from(value).to_fixed(digits, mode_of(has_mode, mode)?)
    }
}

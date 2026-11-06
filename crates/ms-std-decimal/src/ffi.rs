//! C ABI shims for `@std/math/decimal.ms`. A `Decimal` crosses as a pointer to [`Dec`] and results come
//! back through a trailing `out` pointer.

use alloc::string::String;
use ms_decimal::{Dec, Mode, Overflow, RoundFail, overflow_message};
use ms_rt::ffi::{
    Has, Out, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE, Status, abi_record, fault_kind, native,
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
        Err(Overflow::Magnitude) => fault_kind(
            ms_rt::glue::FaultKind::Overflow,
            &overflow_message(operation, &left, &right),
        ),
    }
}

/// A rounding or parsing failure, reported to Manuscript as a status byte.
pub struct Failure(RoundFail);

impl Status for Failure {
    fn status(self) -> u8 {
        match self.0 {
            RoundFail::InvalidInput => STATUS_INVALID_INPUT,
            RoundFail::OutOfRange => STATUS_OUT_OF_RANGE,
        }
    }
}

fn mode_of(has: bool, index: i64) -> Result<Mode, Failure> {
    if !has {
        return Ok(Mode::HalfEven);
    }
    Mode::from_index(index).ok_or(Failure(RoundFail::InvalidInput))
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

// ms: leaf
binary!(msstd_decimal_add, add, "+");
// ms: leaf
binary!(msstd_decimal_subtract, subtract, "-");
// ms: leaf
binary!(msstd_decimal_multiply, multiply, "*");

native! {

    /// The Decimal of runtime text, or `InvalidInput` when it is malformed or not exactly representable.
    // ms: leaf
    fn msstd_decimal_parse(text: &str) -> Result<DecRec, Failure> {
        Dec::parse(text)
            .map(DecRec::from)
            .ok_or(Failure(RoundFail::InvalidInput))
    }

    // ms: leaf
    fn msstd_decimal_from_int(n: i64) -> out DecRec {
        Dec::from_int(n).into()
    }

    // ms: leaf
    fn msstd_decimal_from_uint(n: i64) -> out DecRec {
        Dec::from_uint(n as u64).into()
    }

    // ms: leaf
    fn msstd_decimal_divide(a: &DecRec, b: &DecRec) -> out DecRec {
        let (a, b) = (Dec::from(a), Dec::from(b));
        if b.is_zero() {
            fault_kind(
                ms_rt::glue::FaultKind::DivisionByZero,
                "Decimal./: division by zero; right must be nonzero, found 0",
            );
        }
        checked(a.divide(&b), "/", a, b).into()
    }

    // ms: leaf
    fn msstd_decimal_negate(a: &DecRec) -> out DecRec {
        Dec::from(a).negate().into()
    }

    // ms: leaf
    fn msstd_decimal_compare(a: &DecRec, b: &DecRec) -> i64 {
        Dec::from(a).compare(&Dec::from(b))
    }

    // ms: leaf
    fn msstd_decimal_to_string(a: &DecRec) -> String {
        Dec::from(a).render()
    }

    // ms: leaf
    fn msstd_decimal_to_float(a: &DecRec) -> f64 {
        Dec::from(a).to_float()
    }

    /// `true` and `out` written when the truncated value fits an `Int`.
    // ms: leaf
    fn msstd_decimal_truncate_to_int(a: &DecRec, out: Out<i64>) -> bool {
        match Dec::from(a).truncate_to_int() {
            Some(n) => {
                out.write(n);
                true
            }
            None => false,
        }
    }

    // ms: leaf
    fn msstd_decimal_round(
        value: &DecRec,
        places: i64,
        has_mode: Has,
        mode: i64,
    ) -> Result<DecRec, Failure> {
        Dec::from(value)
            .round(places, mode_of(*has_mode, mode)?)
            .map(DecRec::from)
            .map_err(Failure)
    }

    // ms: leaf
    fn msstd_decimal_to_fixed(
        value: &DecRec,
        digits: i64,
        has_mode: Has,
        mode: i64,
    ) -> Result<String, Failure> {
        Dec::from(value)
            .to_fixed(digits, mode_of(*has_mode, mode)?)
            .map_err(Failure)
    }
}

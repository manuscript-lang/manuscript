//! C ABI shims for `@std/math/decimal.ms`. A `Decimal` crosses as a pointer to [`Dec`] and results come
//! back through a trailing `out` pointer.
//! ms: domain number

use alloc::string::String;
use ms_decimal::{Dec, Mode, Overflow, RoundFail, overflow_message};
use ms_rt::ffi::{
    Has, Out, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE, Status, abi_type, fault_kind, native,
};

abi_type! {
    /// The record layout of [`Dec`] across the ABI.
    pub struct DecType {
        pub lo: u64,
        pub hi: i64,
        pub exp: i64,
    }
}

impl From<&DecType> for Dec {
    fn from(r: &DecType) -> Dec {
        Dec {
            lo: r.lo,
            hi: r.hi,
            exp: r.exp,
        }
    }
}

impl From<Dec> for DecType {
    fn from(d: Dec) -> DecType {
        DecType {
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
            fn $name(a: &DecType, b: &DecType) -> out DecType {
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
    fn msstd_decimal_parse(text: &str) -> Result<DecType, Failure> {
        Dec::parse(text)
            .map(DecType::from)
            .ok_or(Failure(RoundFail::InvalidInput))
    }

    // ms: leaf
    fn msstd_decimal_from_int(n: i64) -> out DecType {
        Dec::from_int(n).into()
    }

    // ms: leaf
    fn msstd_decimal_from_uint(n: i64) -> out DecType {
        Dec::from_uint(n as u64).into()
    }

    // ms: leaf
    fn msstd_decimal_divide(a: &DecType, b: &DecType) -> out DecType {
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
    fn msstd_decimal_negate(a: &DecType) -> out DecType {
        Dec::from(a).negate().into()
    }

    // ms: leaf
    fn msstd_decimal_compare(a: &DecType, b: &DecType) -> i64 {
        Dec::from(a).compare(&Dec::from(b))
    }

    // ms: leaf
    fn msstd_decimal_to_string(a: &DecType) -> String {
        Dec::from(a).render()
    }

    // ms: leaf
    fn msstd_decimal_to_float(a: &DecType) -> f64 {
        Dec::from(a).to_float()
    }

    /// `true` and `out` written when the truncated value fits an `Int`.
    // ms: leaf
    fn msstd_decimal_truncate_to_int(a: &DecType, out: Out<i64>) -> bool {
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
        value: &DecType,
        places: i64,
        has_mode: Has,
        mode: i64,
    ) -> Result<DecType, Failure> {
        Dec::from(value)
            .round(places, mode_of(*has_mode, mode)?)
            .map(DecType::from)
            .map_err(Failure)
    }

    // ms: leaf
    fn msstd_decimal_to_fixed(
        value: &DecType,
        digits: i64,
        has_mode: Has,
        mode: i64,
    ) -> Result<String, Failure> {
        Dec::from(value)
            .to_fixed(digits, mode_of(*has_mode, mode)?)
            .map_err(Failure)
    }
}

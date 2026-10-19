//! C ABI shims for `@std/decimal.ms`. A `Decimal` crosses as a pointer to [`Dec`] and results come
//! back through a trailing `out` pointer.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::{Dec, Mode, Overflow, RoundFail, overflow_message};
use ms_std_core::{
    STATUS_INVALID_INPUT, STATUS_OK, STATUS_OUT_OF_RANGE, StrObj, fault, new_string, str_ref,
};

fn checked(r: Result<Dec, Overflow>, operation: &str, left: Dec, right: Dec) -> Dec {
    match r {
        Ok(v) => v,
        Err(Overflow::Magnitude) => fault(&overflow_message(operation, &left, &right)),
    }
}

/// # Safety
/// `text` is a live string and `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_literal(text: *const StrObj, out: *mut Dec) {
    // SAFETY: caller contract.
    let text = unsafe { str_ref(text) };
    match Dec::parse(text) {
        // SAFETY: `out` is writable.
        Some(d) => unsafe { out.write(d) },
        None => fault("invalid or inexact Decimal literal"),
    }
}

/// # Safety
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_from_int(n: i64, out: *mut Dec) {
    // SAFETY: `out` is writable.
    unsafe { out.write(Dec::from_int(n)) }
}

macro_rules! binary {
    ($name:ident, $method:ident, $op:literal) => {
        /// # Safety
        /// The operands are valid and `out` is writable.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(a: *const Dec, b: *const Dec, out: *mut Dec) {
            // SAFETY: caller contract.
            let (a, b) = unsafe { (*a, *b) };
            let r = checked(a.$method(&b), $op, a, b);
            // SAFETY: `out` is writable.
            unsafe { out.write(r) }
        }
    };
}

binary!(msstd_decimal_add, add, "+");
binary!(msstd_decimal_subtract, subtract, "-");
binary!(msstd_decimal_multiply, multiply, "*");

/// # Safety
/// The operands are valid and `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_divide(a: *const Dec, b: *const Dec, out: *mut Dec) {
    // SAFETY: caller contract.
    let (a, b) = unsafe { (*a, *b) };
    if b.is_zero() {
        fault("Decimal./: division by zero; right must be nonzero, found 0");
    }
    let r = checked(a.divide(&b), "/", a, b);
    // SAFETY: `out` is writable.
    unsafe { out.write(r) }
}

/// # Safety
/// The operand is valid and `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_negate(a: *const Dec, out: *mut Dec) {
    // SAFETY: caller contract.
    unsafe { out.write((*a).negate()) }
}

/// # Safety
/// The operands are valid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_compare(a: *const Dec, b: *const Dec) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*a).compare(&*b) }
}

/// # Safety
/// The operand is valid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_to_string(a: *const Dec) -> *mut StrObj {
    // SAFETY: caller contract.
    new_string(&unsafe { *a }.render())
}

/// # Safety
/// The operand is valid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_to_float(a: *const Dec) -> f64 {
    // SAFETY: caller contract.
    unsafe { (*a).to_float() }
}

/// # Safety
/// The operand is valid and `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_truncate_to_int(a: *const Dec, out: *mut i64) -> u8 {
    // SAFETY: caller contract.
    match unsafe { (*a).truncate_to_int() } {
        Some(n) => {
            // SAFETY: `out` is writable.
            unsafe { out.write(n) };
            1
        }
        None => 0,
    }
}

fn fail_status(f: RoundFail) -> u8 {
    match f {
        RoundFail::InvalidInput => STATUS_INVALID_INPUT,
        RoundFail::OutOfRange => STATUS_OUT_OF_RANGE,
    }
}

fn mode_of(has: u8, index: i64) -> Option<Mode> {
    if has == 0 {
        return Some(Mode::HalfEven);
    }
    Mode::from_index(index)
}

/// # Safety
/// The operand is valid and `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_round(
    value: *const Dec,
    places: i64,
    has_mode: u8,
    mode: i64,
    out: *mut Dec,
) -> u8 {
    let Some(mode) = mode_of(has_mode, mode) else {
        return STATUS_INVALID_INPUT;
    };
    // SAFETY: caller contract.
    match unsafe { (*value).round(places, mode) } {
        Ok(v) => {
            // SAFETY: `out` is writable.
            unsafe { out.write(v) };
            STATUS_OK
        }
        Err(f) => fail_status(f),
    }
}

/// # Safety
/// The operand is valid and `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_decimal_to_fixed(
    value: *const Dec,
    digits: i64,
    has_mode: u8,
    mode: i64,
    out: *mut *mut StrObj,
) -> u8 {
    let Some(mode) = mode_of(has_mode, mode) else {
        return STATUS_INVALID_INPUT;
    };
    // SAFETY: caller contract.
    match unsafe { (*value).to_fixed(digits, mode) } {
        Ok(text) => {
            // SAFETY: `out` is writable.
            unsafe { out.write(new_string(&text)) };
            STATUS_OK
        }
        Err(f) => fail_status(f),
    }
}

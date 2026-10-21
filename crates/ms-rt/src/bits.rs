//! `@std/math`: integer bit operations. Shifts fault outside 0 through 63; rotations take
//! the count modulo 64; the wrapping operations never fault.

use crate::fault::fault_fmt;

fn shift_count(operation: &str, count: i64) -> u32 {
    if !(0..=63).contains(&count) {
        fault_fmt(format_args!(
            "{operation}: count must be between 0 and 63, found {count}"
        ));
    }
    count as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_bit_and(left: i64, right: i64) -> i64 {
    left & right
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_bit_or(left: i64, right: i64) -> i64 {
    left | right
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_bit_xor(left: i64, right: i64) -> i64 {
    left ^ right
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_bit_not(value: i64) -> i64 {
    !value
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_shift_left(value: i64, count: i64) -> i64 {
    value << shift_count("shift_left", count)
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_shift_right(value: i64, count: i64) -> i64 {
    value >> shift_count("shift_right", count)
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_shift_right_unsigned(value: i64, count: i64) -> i64 {
    ((value as u64) >> shift_count("shift_right_unsigned", count)) as i64
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_rotate_left(value: i64, count: i64) -> i64 {
    (value as u64).rotate_left((count % 64).rem_euclid(64) as u32) as i64
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_rotate_right(value: i64, count: i64) -> i64 {
    (value as u64).rotate_right((count % 64).rem_euclid(64) as u32) as i64
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_count_ones(value: i64) -> i64 {
    i64::from(value.count_ones())
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_leading_zeros(value: i64) -> i64 {
    i64::from(value.leading_zeros())
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_trailing_zeros(value: i64) -> i64 {
    i64::from(value.trailing_zeros())
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_wrapping_add(left: i64, right: i64) -> i64 {
    left.wrapping_add(right)
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_wrapping_subtract(left: i64, right: i64) -> i64 {
    left.wrapping_sub(right)
}

#[unsafe(no_mangle)]
pub extern "C" fn msrt_bits_wrapping_multiply(left: i64, right: i64) -> i64 {
    left.wrapping_mul(right)
}

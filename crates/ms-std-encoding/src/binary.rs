//! C ABI shims for `@std/binary.ms`: fixed-width integers and binary64 floats in either byte
//! order. Symbols are `msrt_binary_<function>`; fallible ones return a status byte and write the
//! ok value through `out` only on success.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use ms_std_core::{VecVal, bytes_ref, write_bytes};

const STATUS_OUT_OF_RANGE: u8 = ms_rt_abi::STATUS_OUT_OF_RANGE;
const STATUS_INVALID_INPUT: u8 = ms_rt_abi::STATUS_INVALID_INPUT;

/// `binary.read_integer`: `width` is 1, 2, 4 or 8; the value must fit an `Int`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_binary_read_integer(
    data: *const VecVal,
    offset: i64,
    width: i64,
    signed: u8,
    little: u8,
    out: *mut i64,
) -> u8 {
    if !matches!(width, 1 | 2 | 4 | 8) {
        return STATUS_INVALID_INPUT;
    }
    // SAFETY: `data` is a live Bytes value.
    let bytes = unsafe { bytes_ref(data) };
    let width = width as usize;
    let Some(chunk) = usize::try_from(offset)
        .ok()
        .and_then(|o| bytes.get(o..o.checked_add(width)?))
    else {
        return STATUS_OUT_OF_RANGE;
    };
    let mut n = 0u64;
    if little != 0 {
        for b in chunk.iter().rev() {
            n = n << 8 | u64::from(*b);
        }
    } else {
        for b in chunk {
            n = n << 8 | u64::from(*b);
        }
    }
    if signed != 0 {
        if width < 8 && n & (1 << (width * 8 - 1)) != 0 {
            n |= u64::MAX << (width * 8);
        }
        // SAFETY: `out` is writable.
        unsafe { out.write(n as i64) };
        return ms_rt_abi::STATUS_OK;
    }
    if n > i64::MAX as u64 {
        return STATUS_OUT_OF_RANGE;
    }
    // SAFETY: `out` is writable.
    unsafe { out.write(n as i64) };
    ms_rt_abi::STATUS_OK
}

/// `binary.read_float`: binary64 at `offset`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_binary_read_float(
    data: *const VecVal,
    offset: i64,
    little: u8,
    out: *mut f64,
) -> u8 {
    // SAFETY: `data` is a live Bytes value.
    let bytes = unsafe { bytes_ref(data) };
    let Some(chunk) = usize::try_from(offset)
        .ok()
        .and_then(|o| bytes.get(o..o.checked_add(8)?))
    else {
        return STATUS_OUT_OF_RANGE;
    };
    let raw: [u8; 8] = chunk.try_into().expect("eight bytes");
    let bits = if little != 0 {
        u64::from_le_bytes(raw)
    } else {
        u64::from_be_bytes(raw)
    };
    // SAFETY: `out` is writable.
    unsafe { out.write(f64::from_bits(bits)) };
    ms_rt_abi::STATUS_OK
}

/// `binary.write_integer`: the low `width` bytes, an error when the value does not fit.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_binary_write_integer(
    value: i64,
    width: i64,
    signed: u8,
    little: u8,
    out: *mut VecVal,
) -> u8 {
    if !matches!(width, 1 | 2 | 4 | 8) {
        return STATUS_INVALID_INPUT;
    }
    let width = width as usize;
    let fits = if signed == 0 && value < 0 {
        false
    } else if width == 8 {
        true
    } else if signed != 0 {
        let limit = 1i64 << (width * 8 - 1);
        (-limit..limit).contains(&value)
    } else {
        (value as u64) < (1u64 << (width * 8))
    };
    if !fits {
        return STATUS_OUT_OF_RANGE;
    }
    let le = (value as u64).to_le_bytes();
    let mut bytes = [0u8; 8];
    for i in 0..width {
        bytes[if little != 0 { i } else { width - 1 - i }] = le[i];
    }
    // SAFETY: `out` is writable.
    unsafe { write_bytes(out, &bytes[..width]) };
    ms_rt_abi::STATUS_OK
}

/// `binary.write_float`: binary64 as eight bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_binary_write_float(value: f64, little: u8, out: *mut VecVal) {
    let bits = if little != 0 {
        value.to_bits().to_le_bytes()
    } else {
        value.to_bits().to_be_bytes()
    };
    // SAFETY: `out` is writable.
    unsafe { write_bytes(out, &bits) };
}

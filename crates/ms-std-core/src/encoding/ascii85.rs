//! Unframed ASCII85 using the Go-derived codec, with a strict sizing/validation pass.
use alloc::{string::String, vec, vec::Vec};
use crabmole::encoding::ascii85 as codec;
use ms_rt::ffi::Fail;

pub fn ascii85_encode(data: &[u8]) -> String {
    let capacity = data
        .len()
        .div_ceil(4)
        .checked_mul(5)
        .expect("ASCII85 output is too large");
    let mut output = vec![0; capacity];
    let written = codec::encode(data, &mut output);
    output.truncate(written);
    String::from_utf8(output).expect("ASCII85 codec produces ASCII")
}

pub fn ascii85_decode(text: &str, max_bytes: Option<i64>) -> Result<Vec<u8>, Fail> {
    let limit = super::limit(max_bytes)?;
    let expected = decoded_length(text.as_bytes(), limit)?;
    if expected == 0 {
        return Ok(Vec::new());
    }
    // The codec requires four writable bytes before inspecting each source byte,
    // even trailing whitespace. This also accommodates partial final groups.
    let capacity = expected.checked_add(4).ok_or(Fail::LimitExceeded)?;
    let mut output = vec![0; capacity];
    let (written, consumed) =
        codec::decode_with_flush(text.as_bytes(), &mut output).map_err(|_| Fail::InvalidData)?;
    if written != expected || consumed != text.len() {
        return Err(Fail::InvalidData);
    }
    output.truncate(written);
    Ok(output)
}

// The upstream decoder uses unchecked u32 arithmetic. A sizing pass both enforces
// output budgets before allocation and excludes overflowing complete/partial groups.
fn decoded_length(input: &[u8], limit: usize) -> Result<usize, Fail> {
    let mut size = 0usize;
    let mut word = 0u64;
    let mut digits = 0;
    for &byte in input {
        if byte <= b' ' {
            continue;
        }
        if byte == b'z' {
            if digits != 0 {
                return Err(Fail::InvalidData);
            }
            size = grow(size, 4, limit)?;
            continue;
        }
        if !(b'!'..=b'u').contains(&byte) {
            return Err(Fail::InvalidData);
        }
        word = word * 85 + u64::from(byte - b'!');
        digits += 1;
        if digits == 5 {
            if word > u64::from(u32::MAX) {
                return Err(Fail::InvalidData);
            }
            size = grow(size, 4, limit)?;
            word = 0;
            digits = 0;
        }
    }
    if digits == 1 {
        return Err(Fail::InvalidData);
    }
    if digits > 1 {
        for _ in digits..5 {
            word = word * 85 + 84;
        }
        if word > u64::from(u32::MAX) {
            return Err(Fail::InvalidData);
        }
        size = grow(size, digits - 1, limit)?;
    }
    Ok(size)
}

fn grow(size: usize, count: usize, limit: usize) -> Result<usize, Fail> {
    size.checked_add(count)
        .filter(|&next| next <= limit)
        .ok_or(Fail::LimitExceeded)
}

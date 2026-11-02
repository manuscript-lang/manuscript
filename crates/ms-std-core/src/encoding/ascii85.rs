//! Unframed ASCII85 (Go's `encoding/ascii85` alphabet): `z` stands for a zero group, ASCII
//! controls and space are ignored when decoding, and a partial final group is allowed.
use alloc::{string::String, vec::Vec};
use ms_rt::ffi::Fail;

pub fn ascii85_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(4).saturating_mul(5));
    for chunk in data.chunks(4) {
        let mut word = [0u8; 4];
        word[..chunk.len()].copy_from_slice(chunk);
        let mut v = u32::from_be_bytes(word);
        if chunk.len() == 4 && v == 0 {
            out.push('z');
            continue;
        }
        let mut digits = [0u8; 5];
        for d in digits.iter_mut().rev() {
            *d = b'!' + (v % 85) as u8;
            v /= 85;
        }
        // A partial group of n bytes keeps its first n + 1 digits.
        for &d in &digits[..chunk.len() + 1] {
            out.push(d as char);
        }
    }
    out
}

pub fn ascii85_decode(text: &str, max_bytes: Option<i64>) -> Result<Vec<u8>, Fail> {
    let limit = super::limit(max_bytes)?;
    let mut size = 0;
    if max_bytes.is_some() {
        // A supplied budget must reject the complete output before allocating it.
        visit_groups(text, |bytes| {
            size = grow(size, bytes.len(), limit)?;
            Ok(())
        })?;
        if size == 0 {
            return Ok(Vec::new());
        }
    }
    let mut out = Vec::with_capacity(size);
    visit_groups(text, |bytes| {
        grow(out.len(), bytes.len(), limit)?;
        out.extend_from_slice(bytes);
        Ok(())
    })?;
    Ok(out)
}

fn visit_groups(text: &str, mut emit: impl FnMut(&[u8]) -> Result<(), Fail>) -> Result<(), Fail> {
    let mut word = 0u64;
    let mut digits = 0usize;
    for &byte in text.as_bytes() {
        if byte <= b' ' {
            continue;
        }
        if byte == b'z' {
            if digits != 0 {
                return Err(Fail::InvalidData);
            }
            emit(&[0; 4])?;
            continue;
        }
        if !(b'!'..=b'u').contains(&byte) {
            return Err(Fail::InvalidData);
        }
        word = word * 85 + u64::from(byte - b'!');
        digits += 1;
        if digits == 5 {
            let v = u32::try_from(word).map_err(|_| Fail::InvalidData)?;
            emit(&v.to_be_bytes())?;
            word = 0;
            digits = 0;
        }
    }
    if digits == 1 {
        return Err(Fail::InvalidData);
    }
    if digits > 1 {
        // Pad the partial group with the highest digit; the kept bytes are its first digits - 1.
        for _ in digits..5 {
            word = word * 85 + 84;
        }
        let v = u32::try_from(word).map_err(|_| Fail::InvalidData)?;
        emit(&v.to_be_bytes()[..digits - 1])?;
    }
    Ok(())
}

fn grow(size: usize, count: usize, limit: usize) -> Result<usize, Fail> {
    match size.checked_add(count) {
        Some(next) if next <= limit => Ok(next),
        _ => Err(Fail::LimitExceeded),
    }
}

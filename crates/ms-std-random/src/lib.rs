//! `@std/random.ms` natives: a port of `pkg/runtime/random.go`.
//!
//! The algorithms take the entropy source as a closure so that a user-defined `Entropy` (an
//! interface value the generated code calls) and the operating-system source share them.
#![no_std]

extern crate alloc;

pub mod ffi;

use alloc::string::{String, ToString};
use alloc::vec::Vec;

/// Largest request an `Entropy` source must serve.
pub const MAX_BYTES: i64 = 16 * 1024 * 1024;

/// The `RandomError` cases.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RandomFail {
    InvalidInput,
    LimitExceeded,
    Failed(String),
}

type R<T> = Result<T, RandomFail>;

/// Source of bytes: returns the requested number of bytes or fails.
pub type Fetch<'a> = &'a mut dyn FnMut(usize) -> R<Vec<u8>>;

fn incorrect_length() -> RandomFail {
    RandomFail::Failed("entropy source returned incorrect length".to_string())
}

/// The operating system's entropy source (`osEntropy.Bytes`).
pub fn os_bytes(count: i64) -> R<Vec<u8>> {
    if !(0..=MAX_BYTES).contains(&count) {
        return Err(RandomFail::InvalidInput);
    }
    let mut b = alloc::vec![0u8; count as usize];
    getrandom::fill(&mut b).map_err(|e| RandomFail::Failed(alloc::format!("{e}")))?;
    Ok(b)
}

/// An unbiased integer in `[min, max_exclusive)`, `max_exclusive` defaulting to `i64::MAX`.
pub fn secure_int(fetch: Fetch, min: i64, max_exclusive: Option<i64>) -> R<i64> {
    let max = max_exclusive.unwrap_or(i64::MAX);
    if min >= max {
        return Err(RandomFail::InvalidInput);
    }
    let width = (i128::from(max) - i128::from(min)) as u128;
    let bits = 128 - width.leading_zeros() as usize;
    let count = bits.div_ceil(8);
    loop {
        let mut data = fetch(count)?;
        if data.len() != count {
            return Err(incorrect_length());
        }
        data[0] &= (255u32 >> (count * 8 - bits)) as u8;
        let n = data.iter().fold(0u128, |a, &b| a << 8 | u128::from(b));
        if n < width {
            return Ok((i128::from(min) + n as i128) as i64);
        }
    }
}

/// A version-4 UUID.
pub fn uuid_v4(fetch: Fetch) -> R<String> {
    let mut d = fetch(16)?;
    if d.len() != 16 {
        return Err(incorrect_length());
    }
    d[6] = d[6] & 15 | 64;
    d[8] = d[8] & 63 | 128;
    let mut s = String::with_capacity(36);
    for (i, b) in d.iter().enumerate() {
        if matches!(i, 4 | 6 | 8 | 10) {
            s.push('-');
        }
        s.push_str(&alloc::format!("{b:02x}"));
    }
    Ok(s)
}

/// A secure Float in `[0, 1)` with 53 random bits.
pub fn float(fetch: Fetch) -> R<f64> {
    Ok(secure_int(fetch, 0, Some(1 << 53))? as f64 / (1u64 << 53) as f64)
}

/// Fisher-Yates shuffle in place.
pub fn shuffle<T>(fetch: Fetch, values: &mut [T]) -> R<()> {
    for i in (1..values.len()).rev() {
        let j = secure_int(fetch, 0, Some(i as i64 + 1))?;
        values.swap(i, j as usize);
    }
    Ok(())
}

/// A uniformly chosen index, or `None` for an empty list.
pub fn choice_index(fetch: Fetch, len: usize) -> R<Option<usize>> {
    if len == 0 {
        return Ok(None);
    }
    Ok(Some(secure_int(fetch, 0, Some(len as i64))? as usize))
}

//! `@std/random.ms` natives. The operating-system `Entropy` source is a plain function; the
//! algorithms over any `Entropy` are Manuscript source.

pub mod ffi;

use alloc::string::String;
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

/// The operating system's entropy source (`osEntropy.Bytes`).
pub fn os_bytes(count: i64) -> R<Vec<u8>> {
    if !(0..=MAX_BYTES).contains(&count) {
        return Err(RandomFail::InvalidInput);
    }
    let mut b = alloc::vec![0u8; count as usize];
    getrandom::fill(&mut b).map_err(|e| RandomFail::Failed(alloc::format!("{e}")))?;
    Ok(b)
}

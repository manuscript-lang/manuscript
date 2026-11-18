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

/// The last version-7 UUID stamp handed out: `(millis << 12) | sequence`.
static V7_LAST: core::sync::atomic::AtomicI64 = core::sync::atomic::AtomicI64::new(0);

/// The stamp of the next version-7 UUID made at `millis`, as `(millis << 12) | sequence`.
/// A new millisecond starts the sequence at `seed` (low 11 bits, leaving room to count up); the
/// same millisecond, or a clock that stepped back, continues from the last stamp. Stamps are
/// strictly increasing, and a full 12-bit sequence carries into the millisecond.
pub fn v7_next(millis: i64, seed: i64) -> i64 {
    use core::sync::atomic::Ordering::Relaxed;
    let fresh = (millis << 12) | (seed & 0x7ff);
    let mut last = V7_LAST.load(Relaxed);
    loop {
        let next = if fresh > last { fresh } else { last + 1 };
        match V7_LAST.compare_exchange_weak(last, next, Relaxed, Relaxed) {
            Ok(_) => return next,
            Err(seen) => last = seen,
        }
    }
}

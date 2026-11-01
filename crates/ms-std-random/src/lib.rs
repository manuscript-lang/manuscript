//! `@std/os/random.ms` natives. The operating-system `Entropy` source is a plain function; the
//! algorithms over any `Entropy` are a [`Draw`] the generated code feeds with the bytes it
//! fetches through the interface.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

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

/// What a [`Draw`] computes from the bytes the generated code fetches.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// `secure_int`: an integer in `[a, b)`.
    Int,
    /// `uuid_v4`.
    Uuid,
    /// `float`: 53 random bits.
    Float,
    /// `shuffle` of `a` items: the swaps of a Fisher-Yates pass, one per draw.
    Shuffle,
    /// `choice` over `a` items: an index, or -1 for none.
    Choice,
}

/// An unbiased integer in `[min, min + width)` drawn by rejection from big-endian bytes.
#[derive(Clone, Copy)]
struct Range {
    min: i64,
    width: u128,
    bits: usize,
}

impl Range {
    fn new(min: i64, max: i64) -> Option<Range> {
        if min >= max {
            return None;
        }
        let width = (i128::from(max) - i128::from(min)) as u128;
        Some(Range {
            min,
            width,
            bits: 128 - width.leading_zeros() as usize,
        })
    }

    /// Bytes needed for one attempt.
    fn count(&self) -> usize {
        self.bits.div_ceil(8)
    }

    /// The integer for `data`, or `None` when the attempt is rejected.
    fn accept(&self, data: &[u8]) -> Option<i64> {
        let spare = self.count() * 8 - self.bits;
        let mut n = 0u128;
        for (i, &b) in data.iter().enumerate() {
            let b = if i == 0 { b & (255u8 >> spare) } else { b };
            n = n << 8 | u128::from(b);
        }
        (n < self.width).then(|| (i128::from(self.min) + n as i128) as i64)
    }
}

/// One `@std/os/random.ms` operation over an `Entropy`. The generated code asks [`Draw::want`] how
/// many bytes to fetch through the interface, hands them to [`Draw::push`], and stops when
/// `want` answers zero; [`Draw::status`] then says whether the operation succeeded.
pub struct Draw {
    kind: Kind,
    /// The integer being drawn; none once it is accepted or when there is nothing to draw.
    range: Option<Range>,
    /// A shuffle's next position to fill, counting down to 1.
    cursor: i64,
    status: u8,
    int: i64,
    float: f64,
    text: String,
    swap: (i64, i64),
}

impl Draw {
    /// Starts an operation; `b` is the optional exclusive upper bound of `Kind::Int`.
    pub fn new(kind: Kind, a: i64, b: Option<i64>) -> Draw {
        let mut d = Draw {
            kind,
            range: None,
            cursor: a.wrapping_sub(1),
            status: ms_rt_abi::STATUS_OK,
            int: -1,
            float: 0.0,
            text: String::new(),
            swap: (0, 0),
        };
        match kind {
            Kind::Int => {
                d.range = Range::new(a, b.unwrap_or(i64::MAX));
                if d.range.is_none() {
                    d.status = ms_rt_abi::STATUS_INVALID_INPUT;
                }
            }
            Kind::Float => d.range = Range::new(0, 1 << 53),
            Kind::Choice => d.range = Range::new(0, a),
            // One item is already in place.
            Kind::Shuffle => d.range = Range::new(0, a).filter(|_| a > 1),
            Kind::Uuid => {}
        }
        d
    }

    /// Bytes to fetch next, or zero when the operation is complete or failed.
    pub fn want(&self) -> i64 {
        if self.status != ms_rt_abi::STATUS_OK {
            return 0;
        }
        match self.kind {
            Kind::Uuid if self.text.is_empty() => 16,
            Kind::Uuid => 0,
            _ => self.range.map_or(0, |r| r.count() as i64),
        }
    }

    /// Consumes fetched bytes; answers `true` when a shuffle swap is ready ([`Draw::swap`]).
    pub fn push(&mut self, data: &[u8]) -> bool {
        let want = self.want();
        if want == 0 {
            return false;
        }
        if data.len() as i64 != want {
            self.status = ms_rt_abi::STATUS_FAILED;
            ms_rt::glue::record_failure(b"entropy source returned incorrect length".to_vec());
            return false;
        }
        let Some(range) = self.range else {
            // Only a UUID draws without a range.
            let mut d = [0u8; 16];
            d.copy_from_slice(data);
            d[6] = d[6] & 15 | 64;
            d[8] = d[8] & 63 | 128;
            for (i, b) in d.iter().enumerate() {
                if matches!(i, 4 | 6 | 8 | 10) {
                    self.text.push('-');
                }
                self.text.push_str(&alloc::format!("{b:02x}"));
            }
            return false;
        };
        let Some(n) = range.accept(data) else {
            return false;
        };
        if self.kind == Kind::Shuffle {
            self.swap = (self.cursor, n);
            self.cursor -= 1;
            self.range = Range::new(0, self.cursor + 1).filter(|_| self.cursor > 0);
            return true;
        }
        self.int = n;
        self.float = n as f64 / (1u64 << 53) as f64;
        self.range = None;
        false
    }

    pub fn status(&self) -> u8 {
        self.status
    }

    pub fn int(&self) -> i64 {
        self.int
    }

    pub fn float(&self) -> f64 {
        self.float
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    /// The positions a shuffle swaps after [`Draw::push`] answered `true`.
    pub fn swap(&self) -> (i64, i64) {
        self.swap
    }
}

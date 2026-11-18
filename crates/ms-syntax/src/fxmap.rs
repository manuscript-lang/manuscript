//! Hash maps and sets for compiler-internal keys (interned names, node ids, indices).
//! `std`'s default `SipHash` costs about 12% of a hello-world `ms check` (measured with callgrind,
//! 2026-11-13); these keys are not attacker-controlled, so one multiply-rotate mix per word is enough.
//! The fixed seed also makes iteration order the same on every run.

use std::hash::{BuildHasherDefault, Hasher};

/// A word-at-a-time multiplicative hasher.
#[derive(Default, Clone, Copy)]
pub struct Fx(u64);

const SEED: u64 = 0x517c_c1b7_2722_0a95;

impl Fx {
    #[inline]
    fn mix(&mut self, n: u64) {
        self.0 = (self.0.rotate_left(5) ^ n).wrapping_mul(SEED);
    }
}

impl Hasher for Fx {
    #[inline]
    fn finish(&self) -> u64 {
        self.0
    }
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let (words, rest) = bytes.as_chunks::<8>();
        for w in words {
            self.mix(u64::from_le_bytes(*w));
        }
        if !rest.is_empty() {
            let mut buf = [0u8; 8];
            buf[..rest.len()].copy_from_slice(rest);
            self.mix(u64::from_le_bytes(buf) ^ ((rest.len() as u64) << 56));
        }
    }
    #[inline]
    fn write_u8(&mut self, n: u8) {
        self.mix(n as u64);
    }
    #[inline]
    fn write_u16(&mut self, n: u16) {
        self.mix(n as u64);
    }
    #[inline]
    fn write_u32(&mut self, n: u32) {
        self.mix(n as u64);
    }
    #[inline]
    fn write_u64(&mut self, n: u64) {
        self.mix(n);
    }
    #[inline]
    fn write_usize(&mut self, n: usize) {
        self.mix(n as u64);
    }
}

pub type HashMap<K, V> = std::collections::HashMap<K, V, BuildHasherDefault<Fx>>;
pub type HashSet<K> = std::collections::HashSet<K, BuildHasherDefault<Fx>>;

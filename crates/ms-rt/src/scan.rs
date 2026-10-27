//! Byte scans for parsers: SSE2 on x86-64, NEON on aarch64, eight bytes at a time otherwise.
#![allow(clippy::undocumented_unsafe_blocks)]

const ONES: u64 = 0x0101_0101_0101_0101;
const HIGHS: u64 = 0x8080_8080_8080_8080;

#[inline(always)]
fn word(chunk: &[u8]) -> u64 {
    u64::from_le_bytes([
        chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
    ])
}

/// The index of the first byte at or after `i` that a JSON string must escape (`"`, `\` or a
/// control character).
#[inline]
pub fn json_special(b: &[u8], mut i: usize) -> Option<usize> {
    #[cfg(target_arch = "x86_64")]
    {
        use core::arch::x86_64::{
            __m128i, _mm_cmpeq_epi8, _mm_loadu_si128, _mm_min_epu8, _mm_movemask_epi8,
            _mm_or_si128, _mm_set1_epi8,
        };
        // SAFETY: SSE2 is part of the x86-64 baseline; each load reads 16 bytes inside `b`.
        unsafe {
            let (quote, slash, low) = (
                _mm_set1_epi8(b'"' as i8),
                _mm_set1_epi8(b'\\' as i8),
                _mm_set1_epi8(0x1f),
            );
            while i + 16 <= b.len() {
                let v = _mm_loadu_si128(b.as_ptr().add(i).cast::<__m128i>());
                let hit = _mm_or_si128(
                    _mm_or_si128(_mm_cmpeq_epi8(v, quote), _mm_cmpeq_epi8(v, slash)),
                    // `v <= 0x1f` unsigned, i.e. `min(v, 0x1f) == v`.
                    _mm_cmpeq_epi8(_mm_min_epu8(v, low), v),
                );
                let m = _mm_movemask_epi8(hit);
                if m != 0 {
                    return Some(i + m.trailing_zeros() as usize);
                }
                i += 16;
            }
        }
    }
    #[cfg(target_arch = "aarch64")]
    {
        use core::arch::aarch64::{
            vceqq_u8, vcltq_u8, vdupq_n_u8, vget_lane_u64, vld1q_u8, vorrq_u8, vreinterpret_u64_u8,
            vreinterpretq_u16_u8, vshrn_n_u16,
        };
        // SAFETY: NEON is part of the aarch64 baseline; each load reads 16 bytes inside `b`.
        unsafe {
            let (quote, slash, space) = (vdupq_n_u8(b'"'), vdupq_n_u8(b'\\'), vdupq_n_u8(0x20));
            while i + 16 <= b.len() {
                let v = vld1q_u8(b.as_ptr().add(i));
                let hit = vorrq_u8(
                    vorrq_u8(vceqq_u8(v, quote), vceqq_u8(v, slash)),
                    vcltq_u8(v, space),
                );
                // Four bits per byte, so the first hit is the lowest set nibble.
                let bits = vget_lane_u64::<0>(vreinterpret_u64_u8(vshrn_n_u16::<4>(
                    vreinterpretq_u16_u8(hit),
                )));
                if bits != 0 {
                    return Some(i + (bits.trailing_zeros() / 4) as usize);
                }
                i += 16;
            }
        }
    }
    while let Some(chunk) = b.get(i..i + 8) {
        let w = word(chunk);
        let zero = |x: u64| x.wrapping_sub(ONES) & !x & HIGHS;
        let m = zero(w ^ (ONES * 0x22))
            | zero(w ^ (ONES * 0x5c))
            | (w.wrapping_sub(ONES * 0x20) & !w & HIGHS);
        if m != 0 {
            return Some(i + (m.trailing_zeros() / 8) as usize);
        }
        i += 8;
    }
    while let Some(&c) = b.get(i) {
        if JSON_ESCAPE[usize::from(c)] {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// Bytes a JSON string must escape; short tails use it because one load per byte beats three
/// compares.
static JSON_ESCAPE: [bool; 256] = {
    let mut t = [false; 256];
    let mut c = 0;
    while c < 0x20 {
        t[c] = true;
        c += 1;
    }
    t[b'"' as usize] = true;
    t[b'\\' as usize] = true;
    t
};

/// The index of the first byte at or after `i` that is not a space (`b.len()` when none).
#[inline]
pub fn skip_spaces(b: &[u8], mut i: usize) -> usize {
    #[cfg(target_arch = "x86_64")]
    {
        use core::arch::x86_64::{
            __m128i, _mm_cmpeq_epi8, _mm_loadu_si128, _mm_movemask_epi8, _mm_set1_epi8,
        };
        // SAFETY: SSE2 is part of the x86-64 baseline; each load reads 16 bytes inside `b`.
        unsafe {
            let space = _mm_set1_epi8(b' ' as i8);
            while i + 16 <= b.len() {
                let v = _mm_loadu_si128(b.as_ptr().add(i).cast::<__m128i>());
                let m = !_mm_movemask_epi8(_mm_cmpeq_epi8(v, space)) & 0xffff;
                if m != 0 {
                    return i + m.trailing_zeros() as usize;
                }
                i += 16;
            }
        }
    }
    #[cfg(target_arch = "aarch64")]
    {
        use core::arch::aarch64::{
            vceqq_u8, vdupq_n_u8, vget_lane_u64, vld1q_u8, vmvnq_u8, vreinterpret_u64_u8,
            vreinterpretq_u16_u8, vshrn_n_u16,
        };
        // SAFETY: NEON is part of the aarch64 baseline; each load reads 16 bytes inside `b`.
        unsafe {
            let space = vdupq_n_u8(b' ');
            while i + 16 <= b.len() {
                let v = vld1q_u8(b.as_ptr().add(i));
                let other = vmvnq_u8(vceqq_u8(v, space));
                let bits = vget_lane_u64::<0>(vreinterpret_u64_u8(vshrn_n_u16::<4>(
                    vreinterpretq_u16_u8(other),
                )));
                if bits != 0 {
                    return i + (bits.trailing_zeros() / 4) as usize;
                }
                i += 16;
            }
        }
    }
    while let Some(chunk) = b.get(i..i + 8) {
        let x = word(chunk) ^ (ONES * 0x20);
        if x != 0 {
            return i + (x.trailing_zeros() / 8) as usize;
        }
        i += 8;
    }
    while b.get(i) == Some(&b' ') {
        i += 1;
    }
    i
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn special_bytes_are_found_at_every_offset() {
        for len in 0..70 {
            for at in 0..len {
                for special in [b'"', b'\\', 0x1f, 0, b'\n'] {
                    let mut text = std::vec![b'a'; len];
                    text[at] = special;
                    assert_eq!(json_special(&text, 0), Some(at), "{len} {at} {special}");
                    assert_eq!(json_special(&text, at), Some(at));
                    assert_eq!(json_special(&text, at + 1), None);
                }
            }
            assert_eq!(json_special(&std::vec![b' '; len], 0), None);
            assert_eq!(json_special(&std::vec![0x80u8; len], 0), None);
        }
    }

    #[test]
    fn spaces_stop_at_the_first_other_byte() {
        for len in 0..70 {
            assert_eq!(skip_spaces(&std::vec![b' '; len], 0), len);
            for at in 0..len {
                for other in [b'\n', b'a', 0, 0x80, b'!'] {
                    let mut text = std::vec![b' '; len];
                    text[at] = other;
                    assert_eq!(skip_spaces(&text, 0), at);
                    assert_eq!(skip_spaces(&text, at + 1), len);
                }
            }
        }
    }
}

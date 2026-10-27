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

/// Appends `s` to `buf`; up to 32 bytes with room to spare are two overlapping loads and
/// stores rather than a `memcpy` call, which dominates writing many short names and numbers.
#[inline(always)]
pub fn push_short(buf: &mut crate::stdalloc::vec::Vec<u8>, s: &[u8]) {
    let n = s.len();
    if n > 16 && n <= 32 && buf.capacity() - buf.len() >= n {
        // SAFETY: as below, with two overlapping 16-byte accesses inside the `n` bytes.
        unsafe {
            let src = s.as_ptr();
            let dst = buf.as_mut_ptr().add(buf.len());
            let head = src.cast::<u128>().read_unaligned();
            let tail = src.add(n - 16).cast::<u128>().read_unaligned();
            dst.cast::<u128>().write_unaligned(head);
            dst.add(n - 16).cast::<u128>().write_unaligned(tail);
            buf.set_len(buf.len() + n);
        }
    } else if n <= 16 && buf.capacity() - buf.len() >= n {
        // SAFETY: `n` bytes of spare capacity are writable, `s` has `n` readable bytes, and a
        // `&mut Vec` cannot alias `s`; the length grows only over the bytes just written.
        unsafe {
            crate::vec::copy_short(s.as_ptr(), buf.as_mut_ptr().add(buf.len()), n);
            buf.set_len(buf.len() + n);
        }
    } else {
        buf.extend_from_slice(s);
    }
}

/// Turns bytes the caller built from whole `&str`s and ASCII into a `String` without the
/// validation pass a serializer's output already satisfies.
#[inline]
pub fn string_from_valid_utf8(
    bytes: crate::stdalloc::vec::Vec<u8>,
) -> crate::stdalloc::string::String {
    debug_assert!(core::str::from_utf8(&bytes).is_ok());
    // SAFETY: the caller guarantees `bytes` is valid UTF-8.
    unsafe { crate::stdalloc::string::String::from_utf8_unchecked(bytes) }
}

/// Whether a string of at most 16 bytes holds nothing JSON must escape: two overlapping word
/// tests rather than a byte loop, which is most of the cost of writing short names.
#[inline(always)]
pub fn json_clean_short(b: &[u8]) -> bool {
    match short_words(b, b'A') {
        (w, None) => json_special_word(w) == 0,
        (w, Some(tail)) => (json_special_word(w) | json_special_word(tail)) == 0,
    }
}

/// The bytes of `b` (at most 16) as one word, or two overlapping words from eight bytes up, so
/// a test of the words covers every byte; the unused positions of a short string hold `pad`.
#[inline(always)]
fn short_words(b: &[u8], pad: u8) -> (u64, Option<u64>) {
    let n = b.len();
    debug_assert!(n <= 16);
    // SAFETY: every load reads inside `b[..n]`; each width is guarded by `n`.
    unsafe {
        let p = b.as_ptr();
        if n >= 8 {
            let head = p.cast::<u64>().read_unaligned();
            (head, Some(p.add(n - 8).cast::<u64>().read_unaligned()))
        } else if n >= 4 {
            let head = u64::from(p.cast::<u32>().read_unaligned());
            (
                head | u64::from(p.add(n - 4).cast::<u32>().read_unaligned()) << 32,
                None,
            )
        } else if n > 0 {
            let fill = u64::from_le_bytes([0, 0, 0, pad, pad, pad, pad, pad]);
            (
                u64::from(*p)
                    | u64::from(*p.add(n / 2)) << 8
                    | u64::from(*p.add(n - 1)) << 16
                    | fill,
                None,
            )
        } else {
            (u64::from_le_bytes([pad; 8]), None)
        }
    }
}

/// Whether `b` (at most 16 bytes) is a JSON integer without sign: digits only, no leading zero.
/// A short check ahead of the full number grammar, which most numbers in a document satisfy.
#[inline(always)]
pub fn json_plain_digits(b: &[u8]) -> bool {
    let n = b.len();
    if n == 0 || (n > 1 && b[0] == b'0') {
        return false;
    }
    // `t` bytes are below 10 exactly for digits; padding with `0` keeps unused bytes neutral.
    let nondigit = |x: u64| {
        let t = x ^ (ONES * 0x30);
        ((x | t) & HIGHS) | ((t & !HIGHS).wrapping_add(ONES * 0x76) & HIGHS)
    };
    match short_words(b, b'0') {
        (w, None) => nondigit(w) == 0,
        (w, Some(tail)) => (nondigit(w) | nondigit(tail)) == 0,
    }
}

/// The index of the first byte of `b` that is not an ASCII digit (`b.len()` when all are).
#[inline]
fn first_nondigit(b: &[u8]) -> usize {
    let nondigit = |x: u64| {
        let t = x ^ (ONES * 0x30);
        ((x | t) & HIGHS) | ((t & !HIGHS).wrapping_add(ONES * 0x76) & HIGHS)
    };
    let mut i = 0;
    while let Some(chunk) = b.get(i..i + 8) {
        let m = nondigit(word(chunk));
        if m != 0 {
            return i + (m.trailing_zeros() / 8) as usize;
        }
        i += 8;
    }
    while let Some(&c) = b.get(i) {
        if !c.is_ascii_digit() {
            return i;
        }
        i += 1;
    }
    i
}

/// Whether `b` is a JSON number without an exponent: `-?(0|[1-9][0-9]*)(\.[0-9]+)?`. A short
/// check ahead of the full number grammar for the integers and decimals most documents hold;
/// `false` means "not known to be valid", not "invalid".
#[inline]
pub fn json_simple_number(b: &[u8]) -> bool {
    let b = b.strip_prefix(b"-").unwrap_or(b);
    let int = first_nondigit(b);
    if int == 0 || (int > 1 && b[0] == b'0') {
        return false;
    }
    if int == b.len() {
        return true;
    }
    if b[int] != b'.' {
        return false;
    }
    let frac = &b[int + 1..];
    !frac.is_empty() && all_digits(frac)
}

/// Whether every byte of `b` is an ASCII digit. From eight bytes up, whole words and a final
/// word overlapping the last one, so a 15-digit fraction costs two tests rather than a tail loop.
#[inline]
fn all_digits(b: &[u8]) -> bool {
    let nondigit = |x: u64| {
        let t = x ^ (ONES * 0x30);
        ((x | t) & HIGHS) | ((t & !HIGHS).wrapping_add(ONES * 0x76) & HIGHS)
    };
    let n = b.len();
    if n < 8 {
        return first_nondigit(b) == n;
    }
    let mut i = 0;
    while i + 8 < n {
        if nondigit(word(&b[i..i + 8])) != 0 {
            return false;
        }
        i += 8;
    }
    nondigit(word(&b[n - 8..])) == 0
}

/// Appends `"s"` when `s` is at most 16 bytes with nothing to escape, and returns whether it
/// did; otherwise `buf` is left as it was.
#[inline(always)]
pub fn push_string_short(buf: &mut crate::stdalloc::vec::Vec<u8>, s: &[u8]) -> bool {
    let n = s.len();
    if n > 16 || !json_clean_short(s) {
        return false;
    }
    buf.reserve(18);
    // SAFETY: `reserve` left room for the two quotes and `n <= 16` bytes, at most 18; `s` cannot
    // alias the buffer's spare capacity.
    unsafe {
        let at = buf.as_mut_ptr().add(buf.len());
        *at = b'"';
        crate::vec::copy_short(s.as_ptr(), at.add(1), n);
        *at.add(n + 1) = b'"';
        buf.set_len(buf.len() + n + 2);
    }
    true
}

/// Appends `,` (when `comma`), the already quoted and escaped `quoted` name and `:` when
/// `quoted` is at most 16 bytes, and returns whether it did; otherwise `buf` is left as it was.
#[inline(always)]
pub fn push_member_quoted(
    buf: &mut crate::stdalloc::vec::Vec<u8>,
    comma: bool,
    quoted: &[u8],
) -> bool {
    let n = quoted.len();
    if n > 16 {
        return false;
    }
    buf.reserve(18);
    // SAFETY: `reserve` left room for the comma, `n <= 16` bytes and the colon, at most 18;
    // `quoted` cannot alias the buffer's spare capacity.
    unsafe {
        let mut at = buf.as_mut_ptr().add(buf.len());
        if comma {
            *at = b',';
            at = at.add(1);
        }
        crate::vec::copy_short(quoted.as_ptr(), at, n);
        *at.add(n) = b':';
        buf.set_len(buf.len() + usize::from(comma) + n + 1);
    }
    true
}

/// Appends `,"name":` (without the comma when `comma` is false) when `name` is at most 16 bytes
/// with nothing to escape, and returns whether it did; otherwise `buf` is left as it was.
#[inline(always)]
pub fn push_member_name(buf: &mut crate::stdalloc::vec::Vec<u8>, comma: bool, name: &[u8]) -> bool {
    let n = name.len();
    if n > 16 || !json_clean_short(name) {
        return false;
    }
    buf.reserve(20);
    // SAFETY: `reserve` left room for the comma, two quotes, the colon and `n <= 16` name
    // bytes, which is at most 20; `name` cannot alias the buffer's spare capacity.
    unsafe {
        let mut at = buf.as_mut_ptr().add(buf.len());
        if comma {
            *at = b',';
            at = at.add(1);
        }
        *at = b'"';
        crate::vec::copy_short(name.as_ptr(), at.add(1), n);
        *at.add(n + 1) = b'"';
        *at.add(n + 2) = b':';
        let used = usize::from(comma) + n + 3;
        buf.set_len(buf.len() + used);
    }
    true
}

/// Nonzero when any byte of `w` is `"`, `\` or below 0x20.
#[inline(always)]
fn json_special_word(w: u64) -> u64 {
    let zero = |x: u64| x.wrapping_sub(ONES) & !x & HIGHS;
    zero(w ^ (ONES * 0x22)) | zero(w ^ (ONES * 0x5c)) | (w.wrapping_sub(ONES * 0x20) & !w & HIGHS)
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

#[cfg(test)]
mod json_short_tests {
    use super::*;

    #[test]
    fn clean_short_matches_json_special() {
        let samples: [&[u8]; 14] = [
            b"",
            b"a",
            b"ab",
            b"abc",
            b"abcd",
            b"abcdefg",
            b"abcdefgh",
            b"abcdefghijklmno",
            b"abcdefghijklmnop",
            b"a\"b",
            b"\\",
            b"abcdefg\n",
            b"x\x1fyzabcdefghijkl",
            b"\x7f\xc3\xa9\xc3\xa9",
        ];
        for s in samples {
            assert_eq!(json_clean_short(s), json_special(s, 0).is_none(), "{s:?}");
        }
        for len in 1..=16usize {
            for at in 0..len {
                for bad in [b'"', b'\\', 0u8, 0x1f, b'\t'] {
                    let mut v = alloc_vec(len);
                    v[at] = bad;
                    assert!(!json_clean_short(&v), "{len} {at} {bad}");
                }
                for ok in [0x20u8, b'!', b'#', b'[', b']', 0x7f, 0x80, 0xff] {
                    let mut v = alloc_vec(len);
                    v[at] = ok;
                    assert!(json_clean_short(&v), "{len} {at} {ok}");
                }
            }
        }
    }

    fn alloc_vec(len: usize) -> crate::stdalloc::vec::Vec<u8> {
        crate::stdalloc::vec![b'a'; len]
    }

    #[test]
    fn all_digits_matches_a_byte_loop_at_every_length_and_position() {
        for n in 0..=40usize {
            let mut b = vec![b'7'; n];
            assert!(all_digits(&b), "{n}");
            for at in 0..n {
                for bad in [b'.', b'/', b':', b'a', 0x80u8, 0] {
                    let keep = b[at];
                    b[at] = bad;
                    assert!(!all_digits(&b), "{n} {at} {bad}");
                    b[at] = keep;
                }
            }
        }
    }

    #[test]
    fn simple_numbers_agree_with_the_grammar() {
        // The grammar, written out byte by byte as the oracle.
        let oracle = |s: &[u8]| {
            let mut i = usize::from(s.first() == Some(&b'-'));
            let start = i;
            while s.get(i).is_some_and(u8::is_ascii_digit) {
                i += 1;
            }
            let int = i - start;
            if int == 0 || (int > 1 && s[start] == b'0') {
                return false;
            }
            if i == s.len() {
                return true;
            }
            if s[i] != b'.' {
                return false;
            }
            i += 1;
            let f = i;
            while s.get(i).is_some_and(u8::is_ascii_digit) {
                i += 1;
            }
            i > f && i == s.len()
        };
        let alphabet = *b"0019.-e+ \xb1a";
        let mut x: u64 = 0x9e37_79b9_7f4a_7c15;
        for _ in 0..300_000 {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let len = (x % 26) as usize;
            let mut y = x;
            let s: crate::stdalloc::vec::Vec<u8> = (0..len)
                .map(|_| {
                    y = y
                        .wrapping_mul(6364136223846793005)
                        .wrapping_add(1442695040888963407);
                    alphabet[(y >> 33) as usize % alphabet.len()]
                })
                .collect();
            assert_eq!(json_simple_number(&s), oracle(&s), "{s:?}");
        }
        // Structured numbers, then one byte changed, so both outcomes are well covered.
        for _ in 0..200_000 {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let mut s: crate::stdalloc::vec::Vec<u8> = crate::stdalloc::vec::Vec::new();
            if x & 1 == 1 {
                s.push(b'-');
            }
            for k in 0..=(x >> 1) % 20 {
                s.push(b'0' + ((x >> (8 + k)) % 10) as u8);
            }
            if (x >> 40) & 3 != 0 {
                s.push(b'.');
                for k in 0..(x >> 42) % 21 {
                    s.push(b'0' + ((x >> (3 + k)) % 10) as u8);
                }
            }
            assert_eq!(json_simple_number(&s), oracle(&s), "{s:?}");
            let at = (x >> 20) as usize % s.len();
            s[at] = alphabet[(x >> 52) as usize % alphabet.len()];
            assert_eq!(json_simple_number(&s), oracle(&s), "{s:?}");
        }
        for ok in [
            "0",
            "-0",
            "7",
            "-65.613616999999977",
            "10.5",
            "0.25",
            "123456789012345678901234567890",
        ] {
            assert!(json_simple_number(ok.as_bytes()), "{ok}");
        }
    }

    #[test]
    fn plain_digits() {
        for (s, want) in [
            (&b"0"[..], true),
            (b"7", true),
            (b"10", true),
            (b"0123", false),
            (b"", false),
            (b"-1", false),
            (b"1.5", false),
            (b"1e5", false),
            (b"1234567", true),
            (b"12345678", true),
            (b"1234567890123456", true),
            (b"123456789012345a", false),
            (b"a123456789012345", false),
            (b"12/", false),
            (b"12:", false),
            (b"1 ", false),
            (b"\xb1\xb1\xb1", false),
        ] {
            assert_eq!(json_plain_digits(s), want, "{s:?}");
        }
    }
}

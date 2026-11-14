//! UTF-8 decoding: an invalid byte decodes as
//! U+FFFD with width 1.

pub const RUNE_ERROR: u32 = 0xFFFD;

/// Decodes the scalar at the start of `s` (which must be non-empty).
#[inline]
pub fn decode(s: &[u8]) -> (u32, usize) {
    let b0 = s[0];
    if b0 < 0x80 {
        return (b0 as u32, 1);
    }
    decode_multi(s)
}

fn decode_multi(s: &[u8]) -> (u32, usize) {
    let b0 = s[0];
    let cont = |i: usize, lo: u8, hi: u8| -> Option<u32> {
        match s.get(i) {
            Some(&b) if b >= lo && b <= hi => Some((b & 0x3F) as u32),
            _ => None,
        }
    };
    let err = (RUNE_ERROR, 1);
    match b0 {
        0xC2..=0xDF => match cont(1, 0x80, 0xBF) {
            Some(c1) => ((((b0 & 0x1F) as u32) << 6) | c1, 2),
            None => err,
        },
        0xE0..=0xEF => {
            let (lo, hi) = match b0 {
                0xE0 => (0xA0, 0xBF),
                0xED => (0x80, 0x9F),
                _ => (0x80, 0xBF),
            };
            match (cont(1, lo, hi), cont(2, 0x80, 0xBF)) {
                (Some(c1), Some(c2)) => ((((b0 & 0x0F) as u32) << 12) | (c1 << 6) | c2, 3),
                _ => err,
            }
        }
        0xF0..=0xF4 => {
            let (lo, hi) = match b0 {
                0xF0 => (0x90, 0xBF),
                0xF4 => (0x80, 0x8F),
                _ => (0x80, 0xBF),
            };
            match (cont(1, lo, hi), cont(2, 0x80, 0xBF), cont(3, 0x80, 0xBF)) {
                (Some(c1), Some(c2), Some(c3)) => (
                    (((b0 & 0x07) as u32) << 18) | (c1 << 12) | (c2 << 6) | c3,
                    4,
                ),
                _ => err,
            }
        }
        _ => err,
    }
}

/// Decodes the last scalar of `s` (non-empty).
pub fn decode_last(s: &[u8]) -> (u32, usize) {
    let end = s.len();
    let b = s[end - 1];
    if b < 0x80 {
        return (b as u32, 1);
    }
    let lim = end.saturating_sub(4);
    let mut start = end - 1;
    while start > lim {
        start -= 1;
        if s[start] & 0xC0 != 0x80 {
            break;
        }
    }
    let (r, size) = decode(&s[start..end]);
    if start + size != end {
        return (RUNE_ERROR, 1);
    }
    (r, size)
}

/// Encodes a scalar; invalid values (surrogates, out of range) encode U+FFFD.
pub fn encode(c: u32, out: &mut [u8; 4]) -> usize {
    char::from_u32(c)
        .unwrap_or('\u{FFFD}')
        .encode_utf8(out)
        .len()
}

pub fn is_ascii(s: &[u8]) -> bool {
    s.is_ascii()
}

/// Whether a string of at most 16 bytes is ASCII, by reading it as one or two words; `None` for
/// longer strings.
#[inline(always)]
fn ascii_short(s: &[u8]) -> Option<bool> {
    let n = s.len();
    let p = s.as_ptr();
    // SAFETY: each read stays inside the `n` bytes.
    unsafe {
        if n > 16 {
            None
        } else if n >= 8 {
            let w =
                (p as *const u64).read_unaligned() | (p.add(n - 8) as *const u64).read_unaligned();
            Some(w & 0x8080_8080_8080_8080 == 0)
        } else if n >= 4 {
            let w =
                (p as *const u32).read_unaligned() | (p.add(n - 4) as *const u32).read_unaligned();
            Some(w & 0x8080_8080 == 0)
        } else {
            // 0..=3 bytes: the first, middle and last cover them all.
            Some(n == 0 || (*p | *p.add(n / 2) | *p.add(n - 1)) < 0x80)
        }
    }
}

/// Number of scalars.
#[inline(always)]
pub fn count(s: &[u8]) -> usize {
    if ascii_short(s) == Some(true) {
        return s.len();
    }
    count_long(s)
}

#[inline(never)]
fn count_long(s: &[u8]) -> usize {
    if s.is_ascii() {
        return s.len();
    }
    // A String is valid UTF-8, so a scalar starts at every byte that is not a continuation
    // byte (`10xxxxxx`); counting those needs no validation pass.
    const LOW_BITS: u64 = 0x0101_0101_0101_0101;
    let words = s.chunks_exact(8);
    let tail = words.remainder();
    let mut continuation = 0usize;
    for w in words {
        let w = u64::from_le_bytes(w.try_into().expect("an eight-byte chunk"));
        continuation += ((w >> 7) & !(w >> 6) & LOW_BITS).count_ones() as usize;
    }
    continuation += tail.iter().filter(|&&b| b & 0xC0 == 0x80).count();
    s.len() - continuation
}

/// Byte offset of scalar `n` (clamped to the end).
pub fn offset_of(s: &[u8], mut n: usize) -> usize {
    let mut i = 0;
    while n > 0 && i < s.len() {
        i += if s[i] < 0x80 { 1 } else { decode(&s[i..]).1 };
        n -= 1;
    }
    i
}

/// Byte offset reached by moving `n` scalars forward from byte offset `from`, or `None` when
/// fewer than `n` scalars remain. Runs of eight ASCII bytes are skipped a word at a time, and no
/// scalar count of the whole string is needed, so reaching a nearby index costs the distance only.
pub fn advance(s: &[u8], from: usize, mut n: usize) -> Option<usize> {
    let mut i = from;
    while n > 0 {
        if i >= s.len() {
            return None;
        }
        if n >= 8 && i + 8 <= s.len() {
            let w = u64::from_le_bytes(s[i..i + 8].try_into().unwrap());
            if w & 0x8080_8080_8080_8080 == 0 {
                i += 8;
                n -= 8;
                continue;
            }
        }
        i += if s[i] < 0x80 { 1 } else { decode(&s[i..]).1 };
        n -= 1;
    }
    Some(i)
}

/// Byte offset reached by moving `n` scalars backward from byte offset `end`, or `None` when
/// fewer than `n` scalars precede it. `s` is valid UTF-8, so a scalar starts at every non-continuation
/// byte; reaching a nearby index from the end costs the distance only.
pub fn retreat(s: &[u8], mut end: usize, mut n: usize) -> Option<usize> {
    while n > 0 {
        if end == 0 {
            return None;
        }
        end -= 1;
        while end > 0 && s[end] & 0xC0 == 0x80 {
            end -= 1;
        }
        n -= 1;
    }
    Some(end)
}

/// Unicode White_Space, as `unicode.IsSpace`.
pub fn is_space(c: u32) -> bool {
    match char::from_u32(c) {
        Some(ch) => ch.is_whitespace(),
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn count_matches_scalars_with_and_without_ascii_fast_path() {
        assert_eq!(count(b""), 0);
        assert_eq!(count(b"padded"), 6);
        assert_eq!(count("héllo 😀".as_bytes()), 7);
        assert_eq!(count(&[b'a', 0xFF, b'b', 0xC3]), 4);
    }

    #[test]
    fn count_of_long_mixed_text_matches_chars_at_every_length_and_offset() {
        let text = "aé日😀bПривет你好ñ".repeat(9);
        for start in (0..text.len()).filter(|&i| text.is_char_boundary(i)) {
            for end in (start..=text.len()).filter(|&i| text.is_char_boundary(i)) {
                let part = &text[start..end];
                assert_eq!(
                    count(part.as_bytes()),
                    part.chars().count(),
                    "{start}..{end}"
                );
            }
        }
    }

    #[test]
    fn retreat_mirrors_advance_from_the_end() {
        for text in ["", "a", "é", "aé😀b日", "😀😀"] {
            let b = text.as_bytes();
            let starts: Vec<usize> = text.char_indices().map(|(i, _)| i).collect();
            for n in 0..=starts.len() + 1 {
                let expected = starts
                    .len()
                    .checked_sub(n)
                    .map(|k| if n == 0 { b.len() } else { starts[k] });
                assert_eq!(retreat(b, b.len(), n), expected, "{text:?} back {n}");
            }
        }
    }

    #[test]
    fn decode_matches_std_on_valid_and_replaces_invalid() {
        for text in ["", "a", "é", "日本語", "😀x", "a\u{0}b"] {
            let b = text.as_bytes();
            let mut i = 0;
            let mut chars = text.chars();
            while i < b.len() {
                let (c, w) = decode(&b[i..]);
                assert_eq!(char::from_u32(c), chars.next());
                i += w;
            }
        }
        assert_eq!(decode(&[0xFF]), (RUNE_ERROR, 1));
        assert_eq!(decode(&[0xE2, 0x82]), (RUNE_ERROR, 1));
        assert_eq!(decode(&[0xED, 0xA0, 0x80]), (RUNE_ERROR, 1));
        assert_eq!(decode(&[0xC0, 0x80]), (RUNE_ERROR, 1));
        assert_eq!(count(&[b'a', 0xFF, 0xFF, b'b']), 4);
    }

    #[test]
    fn decode_last_roundtrip() {
        let s = "a日😀é";
        let mut b = s.as_bytes();
        let mut got = std::vec::Vec::new();
        while !b.is_empty() {
            let (c, w) = decode_last(b);
            got.push(char::from_u32(c).unwrap());
            b = &b[..b.len() - w];
        }
        let want: std::vec::Vec<char> = s.chars().rev().collect();
        assert_eq!(got, want);
        assert_eq!(decode_last(&[b'a', 0xE2, 0x82]), (RUNE_ERROR, 1));
    }

    #[test]
    fn encode_matches_std() {
        for c in ['a', 'é', '日', '😀'] {
            let mut out = [0u8; 4];
            let n = encode(c as u32, &mut out);
            let mut want = [0u8; 4];
            assert_eq!(&out[..n], c.encode_utf8(&mut want).as_bytes());
        }
        let mut out = [0u8; 4];
        assert_eq!(encode(0xD800, &mut out), 3);
    }
}

//! UTF-8 decoding with Go's `unicode/utf8` semantics: an invalid byte decodes as
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
    let c = if c > 0x10FFFF || (0xD800..=0xDFFF).contains(&c) {
        RUNE_ERROR
    } else {
        c
    };
    if c < 0x80 {
        out[0] = c as u8;
        1
    } else if c < 0x800 {
        out[0] = 0xC0 | (c >> 6) as u8;
        out[1] = 0x80 | (c & 0x3F) as u8;
        2
    } else if c < 0x10000 {
        out[0] = 0xE0 | (c >> 12) as u8;
        out[1] = 0x80 | ((c >> 6) & 0x3F) as u8;
        out[2] = 0x80 | (c & 0x3F) as u8;
        3
    } else {
        out[0] = 0xF0 | (c >> 18) as u8;
        out[1] = 0x80 | ((c >> 12) & 0x3F) as u8;
        out[2] = 0x80 | ((c >> 6) & 0x3F) as u8;
        out[3] = 0x80 | (c & 0x3F) as u8;
        4
    }
}

pub fn is_ascii(s: &[u8]) -> bool {
    s.is_ascii()
}

/// Number of scalars (Go's `utf8.RuneCountInString`).
pub fn count(s: &[u8]) -> usize {
    if core::str::from_utf8(s).is_ok() {
        return s.iter().filter(|&&b| b & 0xC0 != 0x80).count();
    }
    let mut n = 0;
    let mut i = 0;
    while i < s.len() {
        i += decode(&s[i..]).1;
        n += 1;
    }
    n
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

//! `@std/encoding.ms` natives: hex, base64, UTF-16, Latin-1 and ASCII.
//!
//! Behavior mirrors `pkg/runtime/encoding.go`. Limits are `Option<i64>`; `None` is unlimited.
#![no_std]

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::Fail;

fn limit(max: Option<i64>) -> Result<usize, Fail> {
    match max {
        None => Ok(usize::MAX),
        Some(n) if n < 0 => Err(Fail::InvalidInput),
        Some(n) => Ok(n as usize),
    }
}

/// Lowercase hexadecimal text of `data`.
pub fn hex_encode(data: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(data.len() * 2);
    for &b in data {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 15) as usize] as char);
    }
    out
}

fn hex_val(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

/// Decodes hexadecimal text (either case); the byte budget is checked before the digits.
pub fn hex_decode(text: &str, max_bytes: Option<i64>) -> Result<Vec<u8>, Fail> {
    let n = limit(max_bytes)?;
    let t = text.as_bytes();
    if t.len() / 2 > n {
        return Err(Fail::LimitExceeded);
    }
    if !t.len().is_multiple_of(2) {
        return Err(Fail::InvalidData);
    }
    t.chunks(2)
        .map(|p| {
            Ok(hex_val(p[0]).ok_or(Fail::InvalidData)? << 4
                | hex_val(p[1]).ok_or(Fail::InvalidData)?)
        })
        .collect()
}

const STD: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const URL: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// Padded Base64 (standard or URL-safe alphabet).
pub fn base64_encode(data: &[u8], url_safe: bool) -> String {
    let alpha = if url_safe { URL } else { STD };
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for c in data.chunks(3) {
        let v = (c[0] as u32) << 16
            | (*c.get(1).unwrap_or(&0) as u32) << 8
            | *c.get(2).unwrap_or(&0) as u32;
        out.push(alpha[(v >> 18) as usize & 63] as char);
        out.push(alpha[(v >> 12) as usize & 63] as char);
        out.push(if c.len() > 1 {
            alpha[(v >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if c.len() > 2 {
            alpha[v as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

/// Strict padded Base64: no whitespace, length a multiple of four, zero trailing bits.
pub fn base64_decode(text: &str, url_safe: bool, max_bytes: Option<i64>) -> Result<Vec<u8>, Fail> {
    let n = limit(max_bytes)?;
    let t = text.as_bytes();
    if t.iter().any(|&c| matches!(c, b'\r' | b'\n' | b'\t' | b' ')) {
        return Err(Fail::InvalidData);
    }
    let padding = t.iter().rev().take_while(|&&c| c == b'=').count();
    if padding > 2 || !t.len().is_multiple_of(4) {
        return Err(Fail::InvalidData);
    }
    if (t.len() / 4 * 3).saturating_sub(padding) > n {
        return Err(Fail::LimitExceeded);
    }
    let alpha = if url_safe { URL } else { STD };
    let mut rev = [0xffu8; 256];
    for (i, &c) in alpha.iter().enumerate() {
        rev[c as usize] = i as u8;
    }
    let mut out = Vec::with_capacity(t.len() / 4 * 3);
    let quads = t.len() / 4;
    for (qi, q) in t.chunks(4).enumerate() {
        let last = qi + 1 == quads;
        let pad = if last { padding } else { 0 };
        let mut v = 0u32;
        for (i, &c) in q.iter().enumerate() {
            let d = if i >= 4 - pad {
                if c != b'=' {
                    return Err(Fail::InvalidData);
                }
                0
            } else {
                match rev[c as usize] {
                    0xff => return Err(Fail::InvalidData),
                    d => d as u32,
                }
            };
            v = v << 6 | d;
        }
        // Strict mode: the unused low bits of the last group must be zero.
        match pad {
            1 if v & 0xff != 0 => return Err(Fail::InvalidData),
            2 if v & 0xffff != 0 => return Err(Fail::InvalidData),
            _ => {}
        }
        out.push((v >> 16) as u8);
        if pad < 2 {
            out.push((v >> 8) as u8);
        }
        if pad < 1 {
            out.push(v as u8);
        }
    }
    Ok(out)
}

/// UTF-16 code units of `text`, without a byte order mark.
pub fn utf16_encode(text: &str, little_endian: bool) -> Vec<u8> {
    let mut out = Vec::with_capacity(text.len() * 2);
    for u in text.encode_utf16() {
        let b = if little_endian {
            u.to_le_bytes()
        } else {
            u.to_be_bytes()
        };
        out.extend_from_slice(&b);
    }
    out
}

/// Strict UTF-16: an odd length or an unpaired surrogate is `InvalidData`.
pub fn utf16_decode(
    data: &[u8],
    little_endian: bool,
    max_bytes: Option<i64>,
) -> Result<String, Fail> {
    let n = limit(max_bytes)?;
    if !data.len().is_multiple_of(2) {
        return Err(Fail::InvalidData);
    }
    let units = data.chunks(2).map(|p| {
        let a = [p[0], p[1]];
        if little_endian {
            u16::from_le_bytes(a)
        } else {
            u16::from_be_bytes(a)
        }
    });
    let mut out = String::new();
    for r in char::decode_utf16(units) {
        out.push(r.map_err(|_| Fail::InvalidData)?);
        if out.len() > n {
            return Err(Fail::LimitExceeded);
        }
    }
    Ok(out)
}

fn encode_narrow(text: &str, max: u32) -> Result<Vec<u8>, Fail> {
    text.chars()
        .map(|c| {
            if c as u32 > max {
                Err(Fail::InvalidData)
            } else {
                Ok(c as u32 as u8)
            }
        })
        .collect()
}

/// Latin-1: a scalar above U+00FF is `InvalidData`.
pub fn latin1_encode(text: &str) -> Result<Vec<u8>, Fail> {
    encode_narrow(text, 0xff)
}

/// Maps every byte to the scalar of the same value.
pub fn latin1_decode(data: &[u8]) -> String {
    data.iter().map(|&b| b as char).collect()
}

/// 7-bit ASCII: a scalar above U+007F is `InvalidData`.
pub fn ascii_encode(text: &str) -> Result<Vec<u8>, Fail> {
    encode_narrow(text, 0x7f)
}

/// A byte above 0x7F is `InvalidData`.
pub fn ascii_decode(data: &[u8]) -> Result<String, Fail> {
    if data.iter().any(|&b| b > 0x7f) {
        return Err(Fail::InvalidData);
    }
    Ok(data.iter().map(|&b| b as char).collect())
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    #[test]
    fn hex() {
        assert_eq!(hex_encode(b"\x00\xffAz"), "00ff417a");
        assert_eq!(hex_decode("00FF417a", None).unwrap(), b"\x00\xffAz");
        assert_eq!(hex_decode("0", None), Err(Fail::InvalidData));
        assert_eq!(hex_decode("zz", None), Err(Fail::InvalidData));
        assert_eq!(hex_decode("aabb", Some(1)), Err(Fail::LimitExceeded));
        assert_eq!(hex_decode("aabb", Some(-1)), Err(Fail::InvalidInput));
        // The budget is checked on the length before the digits are validated.
        assert_eq!(hex_decode("zzzz", Some(1)), Err(Fail::LimitExceeded));
    }

    #[test]
    fn base64() {
        for (raw, enc) in [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
        ] {
            assert_eq!(base64_encode(raw.as_bytes(), false), enc);
            assert_eq!(base64_decode(enc, false, None).unwrap(), raw.as_bytes());
        }
        assert_eq!(base64_encode(&[0xfb, 0xff], false), "+/8=");
        assert_eq!(base64_encode(&[0xfb, 0xff], true), "-_8=");
        assert_eq!(base64_decode("-_8=", true, None).unwrap(), [0xfb, 0xff]);
        assert_eq!(base64_decode("-_8=", false, None), Err(Fail::InvalidData));
        assert_eq!(base64_decode("Zg", false, None), Err(Fail::InvalidData));
        assert_eq!(base64_decode("Zh==", false, None), Err(Fail::InvalidData));
        assert_eq!(base64_decode("Zm9 v", false, None), Err(Fail::InvalidData));
        assert_eq!(
            base64_decode("Zm9vYg==", false, Some(3)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(
            base64_decode("Zg==", false, Some(-1)),
            Err(Fail::InvalidInput)
        );
        assert_eq!(base64_decode("=Zg=", false, None), Err(Fail::InvalidData));
    }

    #[test]
    fn utf16() {
        assert_eq!(utf16_encode("a😀", true), [0x61, 0, 0x3d, 0xd8, 0x00, 0xde]);
        assert_eq!(utf16_encode("a", false), [0, 0x61]);
        assert_eq!(
            utf16_decode(&utf16_encode("a😀é", true), true, None).unwrap(),
            "a😀é"
        );
        assert_eq!(utf16_decode(&[0x61], true, None), Err(Fail::InvalidData));
        assert_eq!(
            utf16_decode(&[0x00, 0xd8], true, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            utf16_decode(&[0x00, 0xdc], true, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            utf16_decode(&utf16_encode("abc", true), true, Some(2)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(utf16_decode(&[], true, Some(-1)), Err(Fail::InvalidInput));
    }

    #[test]
    fn narrow() {
        assert_eq!(latin1_encode("é").unwrap(), [0xe9]);
        assert_eq!(latin1_encode("€"), Err(Fail::InvalidData));
        assert_eq!(latin1_decode(&[0xe9, 0x41]), "éA");
        assert_eq!(ascii_encode("é"), Err(Fail::InvalidData));
        assert_eq!(ascii_decode(b"abc").unwrap(), "abc");
        assert_eq!(ascii_decode(&[0x80]), Err(Fail::InvalidData));
    }
}

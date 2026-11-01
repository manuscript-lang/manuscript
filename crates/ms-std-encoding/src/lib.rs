//! `@std/data/encoding.ms` natives: Base64 (hex, UTF-16, Latin-1 and ASCII are Manuscript).
//!
//! Limits are `Option<i64>`; `None` is unlimited.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::Fail;

fn limit(max: Option<i64>) -> Result<usize, Fail> {
    match max {
        None => Ok(usize::MAX),
        Some(n) if n < 0 => Err(Fail::InvalidInput),
        Some(n) => Ok(n as usize),
    }
}

const STD: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const URL: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

// Both alphabets are fixed. Build their decoding tables once at compile time rather than
// initializing 256 entries and installing the alphabet for every decoded byte string.
const fn reverse_alphabet(alpha: &[u8; 64]) -> [u8; 256] {
    let mut reverse = [0xff; 256];
    let mut i = 0;
    while i < alpha.len() {
        reverse[alpha[i] as usize] = i as u8;
        i += 1;
    }
    reverse
}

static STD_REVERSE: [u8; 256] = reverse_alphabet(STD);
static URL_REVERSE: [u8; 256] = reverse_alphabet(URL);

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
    base64_decode_with(text, url_safe, max_bytes, false)
}

/// Padded standard Base64 that tolerates non-zero trailing bits, as PEM and WebSocket keys allow.
pub fn base64_decode_lenient(text: &str) -> Option<Vec<u8>> {
    base64_decode_with(text, false, None, true).ok()
}

fn base64_decode_with(
    text: &str,
    url_safe: bool,
    max_bytes: Option<i64>,
    allow_trailing_bits: bool,
) -> Result<Vec<u8>, Fail> {
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
    let rev = if url_safe { &URL_REVERSE } else { &STD_REVERSE };
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
            _ if allow_trailing_bits => {}
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

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    #[test]
    fn base64_alphabets_and_strict_validation() {
        for url_safe in [false, true] {
            let alpha = if url_safe { URL } else { STD };
            for (digit, &byte) in alpha.iter().enumerate() {
                let encoded = String::from_utf8(alloc::vec![byte, b'A', b'A', b'A']).unwrap();
                assert_eq!(
                    base64_decode(&encoded, url_safe, Some(3)).unwrap(),
                    [(digit as u8) << 2, 0, 0]
                );
            }
            for len in 0..257 {
                let raw: Vec<u8> = (0..len).map(|i| (i * 73 + 11) as u8).collect();
                let encoded = base64_encode(&raw, url_safe);
                assert_eq!(base64_decode(&encoded, url_safe, Some(len)), Ok(raw));
                if len > 0 {
                    assert_eq!(
                        base64_decode(&encoded, url_safe, Some(len - 1)),
                        Err(Fail::LimitExceeded)
                    );
                }
            }
            for invalid in [
                "=AAA", "A=AA", "AA=A", "AA==AAAA", "éAA", "😀", "Zh==", "Zm9=",
            ] {
                assert_eq!(
                    base64_decode(invalid, url_safe, None),
                    Err(Fail::InvalidData)
                );
            }
            // Syntax whitespace precedes the byte limit; alphabet errors follow it.
            assert_eq!(
                base64_decode("AA A", url_safe, Some(0)),
                Err(Fail::InvalidData)
            );
            assert_eq!(
                base64_decode("!!!!", url_safe, Some(0)),
                Err(Fail::LimitExceeded)
            );
        }
        for text in ["+AAA", "/AAA"] {
            assert_eq!(base64_decode(text, true, None), Err(Fail::InvalidData));
        }
        for text in ["-AAA", "_AAA"] {
            assert_eq!(base64_decode(text, false, None), Err(Fail::InvalidData));
        }
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
}

//! `@std/data/encoding.ms` natives: RFC 4648 codecs and ASCII85.
//!
//! Limits are `Option<i64>`; `None` is unlimited.

mod ascii85;
pub mod ffi;
mod variants;

pub use ascii85::{ascii85_decode, ascii85_encode};
pub use variants::{
    base32_decode, base32_encode, base64_decode_unpadded, base64_encode_unpadded, hex_decode,
    hex_encode,
};

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
const fn reverse_alphabet(alpha: &[u8]) -> [u8; 256] {
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
    base64_encode_with(data, if url_safe { URL } else { STD }, true)
}

/// Base64 text built as bytes, three input bytes per four output bytes, then the tail.
pub(crate) fn base64_encode_with(data: &[u8], alpha: &[u8; 64], pad: bool) -> String {
    let mut out = Vec::with_capacity(data.len().div_ceil(3) * 4);
    out.resize(data.len() / 3 * 4, 0);
    let (groups, tail) = data.as_chunks::<3>();
    for (quad, c) in out.as_chunks_mut::<4>().0.iter_mut().zip(groups) {
        let v = u32::from(c[0]) << 16 | u32::from(c[1]) << 8 | u32::from(c[2]);
        *quad = [
            alpha[(v >> 18) as usize & 63],
            alpha[(v >> 12) as usize & 63],
            alpha[(v >> 6) as usize & 63],
            alpha[v as usize & 63],
        ];
    }
    if let [a] = *tail {
        out.extend_from_slice(&[alpha[usize::from(a >> 2)], alpha[usize::from(a << 4 & 63)]]);
        if pad {
            out.extend_from_slice(b"==");
        }
    } else if let [a, b] = *tail {
        let v = u32::from(a) << 8 | u32::from(b);
        out.extend_from_slice(&[
            alpha[(v >> 10) as usize & 63],
            alpha[(v >> 4) as usize & 63],
            alpha[(v << 2) as usize & 63],
        ]);
        if pad {
            out.push(b'=');
        }
    }
    // The alphabets and `=` are ASCII, so this validation cannot fail.
    String::from_utf8(out).unwrap_or_default()
}

/// Decodes unpadded Base64 symbols (`symbols.len() % 4 != 1`): four symbols make three bytes. The
/// last two or three symbols must leave zero unused bits unless `allow_trailing_bits`. A byte
/// outside the alphabet, including `=`, is invalid data.
pub(crate) fn base64_decode_symbols(
    symbols: &[u8],
    rev: &[u8; 256],
    allow_trailing_bits: bool,
) -> Result<Vec<u8>, Fail> {
    let mut out = Vec::with_capacity(symbols.len() / 4 * 3 + 2);
    out.resize(symbols.len() / 4 * 3, 0);
    let (quads, tail) = symbols.as_chunks::<4>();
    // Every valid digit is below 64 and every invalid byte maps to 0xff, so ORing all digits
    // finds a bad byte without a branch per quad.
    let mut bad = 0u8;
    for (triple, q) in out.as_chunks_mut::<3>().0.iter_mut().zip(quads) {
        let (a, b, c, d) = (
            rev[usize::from(q[0])],
            rev[usize::from(q[1])],
            rev[usize::from(q[2])],
            rev[usize::from(q[3])],
        );
        bad |= a | b | c | d;
        let v = u32::from(a) << 18 | u32::from(b) << 12 | u32::from(c) << 6 | u32::from(d);
        *triple = [(v >> 16) as u8, (v >> 8) as u8, v as u8];
    }
    if bad > 63 {
        return Err(Fail::InvalidData);
    }
    let digit = |i: usize| rev[usize::from(tail[i])];
    match tail.len() {
        2 => {
            let (a, b) = (digit(0), digit(1));
            if a | b > 63 || (!allow_trailing_bits && b & 0xf != 0) {
                return Err(Fail::InvalidData);
            }
            out.push(a << 2 | b >> 4);
        }
        3 => {
            let (a, b, c) = (digit(0), digit(1), digit(2));
            if a | b | c > 63 || (!allow_trailing_bits && c & 0x3 != 0) {
                return Err(Fail::InvalidData);
            }
            let v = u32::from(a) << 10 | u32::from(b) << 4 | u32::from(c) >> 2;
            out.extend_from_slice(&[(v >> 8) as u8, v as u8]);
        }
        _ => {}
    }
    Ok(out)
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
    // The trailing `=` are the padding; an `=` anywhere before them is not in the alphabet.
    base64_decode_symbols(&t[..t.len() - padding], rev, allow_trailing_bits)
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

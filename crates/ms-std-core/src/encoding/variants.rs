//! Base32 (RFC 4648, both alphabets, padded or not) and unpadded Base64, strict like the padded
//! Base64 in `mod.rs`: no whitespace, canonical length, zero trailing bits, padding only at the end.
use super::{STD, STD_REVERSE, URL, URL_REVERSE, limit, reverse_alphabet};
use alloc::{string::String, vec::Vec};
use ms_rt::ffi::Fail;

const B32: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const B32HEX: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUV";
static B32_REVERSE: [u8; 256] = reverse_alphabet(B32);
static B32HEX_REVERSE: [u8; 256] = reverse_alphabet(B32HEX);

/// Encodes `data` in groups of `bits`-bit symbols; `group` is the symbols per full block (8 or 4).
fn encode(data: &[u8], alpha: &[u8], bits: u32, group: usize, pad: bool) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(bits as usize) * group);
    let (mut acc, mut held) = (0u32, 0u32);
    let mut symbols = 0;
    for &byte in data {
        acc = acc << 8 | u32::from(byte);
        held += 8;
        while held >= bits {
            held -= bits;
            out.push(alpha[(acc >> held) as usize & ((1 << bits) - 1)] as char);
            symbols += 1;
        }
        acc &= (1 << held) - 1;
    }
    if held > 0 {
        out.push(alpha[(acc << (bits - held)) as usize & ((1 << bits) - 1)] as char);
        symbols += 1;
    }
    if pad {
        while symbols % group != 0 {
            out.push('=');
            symbols += 1;
        }
    }
    out
}

fn decode(
    text: &str,
    rev: &[u8; 256],
    bits: u32,
    group: usize,
    padded: bool,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    let max = limit(max_bytes)?;
    let t = text.as_bytes();
    let pad = t.iter().rev().take_while(|&&c| c == b'=').count();
    let n = t.len() - pad;
    // Padding belongs only to padded text, only at the end, and completes the last block.
    if (pad > 0 && !padded) || (padded && !t.len().is_multiple_of(group)) {
        return Err(Fail::InvalidData);
    }
    // A last block of 1, 3 or 6 symbols (Base32) or 1 symbol (Base64) cannot encode whole bytes.
    let tail = n % group;
    let valid_tail = match bits {
        5 => matches!(tail, 0 | 2 | 4 | 5 | 7),
        _ => matches!(tail, 0 | 2 | 3),
    };
    if !valid_tail || (padded && pad != (group - tail) % group) {
        return Err(Fail::InvalidData);
    }
    let bytes = (n as u128 * u128::from(bits) / 8) as usize;
    if bytes > max {
        return Err(Fail::LimitExceeded);
    }
    let mut out = Vec::with_capacity(bytes);
    let (mut acc, mut held) = (0u32, 0u32);
    for &c in &t[..n] {
        let d = rev[c as usize];
        if d == 0xff {
            return Err(Fail::InvalidData);
        }
        acc = acc << bits | u32::from(d);
        held += bits;
        if held >= 8 {
            held -= 8;
            out.push((acc >> held) as u8);
            acc &= (1 << held) - 1;
        }
    }
    if acc != 0 {
        return Err(Fail::InvalidData);
    }
    Ok(out)
}

pub fn base64_encode_unpadded(data: &[u8], url_safe: bool) -> String {
    encode(data, if url_safe { URL } else { STD }, 6, 4, false)
}

pub fn base64_decode_unpadded(
    text: &str,
    url_safe: bool,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    // The unpadded Base64 contract checks encoded length and its potential decoded size
    // before alphabet/padding errors.
    let max = limit(max_bytes)?;
    let length = text.len();
    if length > usize::MAX / 8 {
        return Err(Fail::LimitExceeded);
    }
    if length % 4 == 1 {
        return Err(Fail::InvalidData);
    }
    if length / 4 * 3 + length % 4 * 6 / 8 > max {
        return Err(Fail::LimitExceeded);
    }
    let rev = if url_safe { &URL_REVERSE } else { &STD_REVERSE };
    decode(text, rev, 6, 4, false, max_bytes)
}

pub fn base32_encode(data: &[u8], hex_alphabet: bool, padded: bool) -> String {
    encode(data, if hex_alphabet { B32HEX } else { B32 }, 5, 8, padded)
}

pub fn base32_decode(
    text: &str,
    hex_alphabet: bool,
    padded: bool,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    let rev = if hex_alphabet {
        &B32HEX_REVERSE
    } else {
        &B32_REVERSE
    };
    decode(text, rev, 5, 8, padded, max_bytes)
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    #[test]
    fn rfc4648_base32_vectors() {
        for (raw, std, hex) in [
            ("", "", ""),
            ("f", "MY======", "CO======"),
            ("fo", "MZXQ====", "CPNG===="),
            ("foo", "MZXW6===", "CPNMU==="),
            ("foob", "MZXW6YQ=", "CPNMUOG="),
            ("fooba", "MZXW6YTB", "CPNMUOJ1"),
            ("foobar", "MZXW6YTBOI======", "CPNMUOJ1E8======"),
        ] {
            for (hex_alphabet, want) in [(false, std), (true, hex)] {
                assert_eq!(base32_encode(raw.as_bytes(), hex_alphabet, true), want);
                let bare = want.trim_end_matches('=');
                assert_eq!(base32_encode(raw.as_bytes(), hex_alphabet, false), bare);
                assert_eq!(
                    base32_decode(want, hex_alphabet, true, None).unwrap(),
                    raw.as_bytes()
                );
                assert_eq!(
                    base32_decode(bare, hex_alphabet, false, None).unwrap(),
                    raw.as_bytes()
                );
            }
        }
    }

    #[test]
    fn strict_rejections_and_limits() {
        for bad in [
            "M",
            "MY=====",
            "MY======MY======",
            "my======",
            "MZ======",
            "M=Y=====",
        ] {
            assert_eq!(
                base32_decode(bad, false, true, None),
                Err(Fail::InvalidData),
                "{bad}"
            );
        }
        assert_eq!(base32_decode("MY", false, false, None).unwrap(), b"f");
        assert_eq!(
            base32_decode("MY======", false, false, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            base32_decode("MY", false, true, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            base32_decode("MZXW6===", false, true, Some(2)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(base64_decode_unpadded("Zg", false, None).unwrap(), b"f");
        assert_eq!(
            base64_decode_unpadded("Zh", false, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            base64_decode_unpadded("Z", false, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            base64_decode_unpadded("Zg==", false, None),
            Err(Fail::InvalidData)
        );
        assert_eq!(
            base64_decode_unpadded("-_8", true, None).unwrap(),
            [0xfb, 0xff]
        );
        for len in 0..64 {
            let raw: Vec<u8> = (0..len).map(|i| (i * 37 + 5) as u8).collect();
            for url in [false, true] {
                let e = base64_encode_unpadded(&raw, url);
                assert_eq!(base64_decode_unpadded(&e, url, None).unwrap(), raw);
            }
        }
    }

    #[test]
    fn unpadded_base64_budget_precedes_padding_errors() {
        for url in [false, true] {
            for text in ["AA==", "AAA=", "===="] {
                for max in 0..3 {
                    assert_eq!(
                        base64_decode_unpadded(text, url, Some(max)),
                        Err(Fail::LimitExceeded)
                    );
                }
                assert_eq!(
                    base64_decode_unpadded(text, url, Some(3)),
                    Err(Fail::InvalidData)
                );
                assert_eq!(
                    base64_decode_unpadded(text, url, Some(-1)),
                    Err(Fail::InvalidInput)
                );
            }
        }
        for url in [false, true] {
            assert_eq!(
                base64_decode_unpadded("A", url, Some(0)),
                Err(Fail::InvalidData)
            );
            assert_eq!(
                base64_decode_unpadded("!!!!", url, Some(0)),
                Err(Fail::LimitExceeded)
            );
            assert_eq!(
                base64_decode_unpadded("!!!!", url, Some(3)),
                Err(Fail::InvalidData)
            );
            assert_eq!(
                base64_decode_unpadded("Zg", url, Some(1)),
                Ok(b"f".to_vec())
            );
        }
    }
}

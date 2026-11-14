//! Base32 (RFC 4648, both alphabets, padded or not) and unpadded Base64, strict like the padded
//! Base64 in `mod.rs`: no whitespace, canonical length, zero trailing bits, padding only at the end.
use super::{
    STD, STD_REVERSE, URL, URL_REVERSE, base64_decode_symbols, base64_encode_with, limit,
    reverse_alphabet,
};
use alloc::{string::String, vec::Vec};
use ms_rt::ffi::Fail;

const B32: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const B32HEX: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUV";
static B32_REVERSE: [u8; 256] = reverse_alphabet(B32);
static B32HEX_REVERSE: [u8; 256] = reverse_alphabet(B32HEX);

/// Encodes `data` in groups of `bits`-bit symbols; `group` is the symbols per full block (8 or 4).
fn encode(data: &[u8], alpha: &[u8], bits: u32, group: usize, pad: bool) -> String {
    let bytes_per_group = bits as usize * group / 8;
    let mut out = String::with_capacity(data.len().div_ceil(bytes_per_group) * group);
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
        // Base32 interior padding takes precedence over an insufficient budget.
        // With a fitting budget, the normal alphabet loop rejects it instead.
        if bits == 5 && t[..n].contains(&b'=') {
            return Err(Fail::InvalidData);
        }
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

/// Lowercase hexadecimal, two digits per byte.
pub fn hex_encode(data: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = alloc::vec![0u8; data.len() * 2];
    for ([high, low], &byte) in out.as_chunks_mut::<2>().0.iter_mut().zip(data) {
        *high = DIGITS[usize::from(byte >> 4)];
        *low = DIGITS[usize::from(byte & 15)];
    }
    // Hexadecimal digits are ASCII, so this validation cannot fail.
    String::from_utf8(out).unwrap_or_default()
}

/// Hexadecimal of either case. The budget is checked before the length parity and the digits.
pub fn hex_decode(text: &str, max_bytes: Option<i64>) -> Result<Vec<u8>, Fail> {
    static REVERSE: [u8; 256] = {
        let mut table = [0xff; 256];
        let mut i = 0;
        while i < 16 {
            let digit = b"0123456789abcdef"[i];
            table[digit as usize] = i as u8;
            table[digit.to_ascii_uppercase() as usize] = i as u8;
            i += 1;
        }
        table
    };
    let max = limit(max_bytes)?;
    let t = text.as_bytes();
    if t.len() / 2 > max {
        return Err(Fail::LimitExceeded);
    }
    if !t.len().is_multiple_of(2) {
        return Err(Fail::InvalidData);
    }
    let mut out = alloc::vec![0u8; t.len() / 2];
    // Bad digits map to 0xff, which ORs into `bad` above 15 instead of branching per byte.
    let mut bad = 0u8;
    for (byte, [first, second]) in out.iter_mut().zip(t.as_chunks::<2>().0) {
        let (high, low) = (REVERSE[usize::from(*first)], REVERSE[usize::from(*second)]);
        bad |= high | low;
        *byte = high << 4 | low;
    }
    if bad > 15 {
        return Err(Fail::InvalidData);
    }
    Ok(out)
}

pub fn base64_encode_unpadded(data: &[u8], url_safe: bool) -> String {
    base64_encode_with(data, if url_safe { URL } else { STD }, false)
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
    base64_decode_symbols(text.as_bytes(), rev, false)
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
    fn hex_round_trips_and_reports_errors_in_contract_order() {
        let raw: Vec<u8> = (0..=255).collect();
        let text = hex_encode(&raw);
        assert_eq!(&text[..8], "00010203");
        assert_eq!(hex_decode(&text, None).unwrap(), raw);
        assert_eq!(hex_decode(&text.to_uppercase(), None).unwrap(), raw);
        assert_eq!(hex_decode("", None).unwrap(), b"");
        // The budget is checked before parity and digits; parity before digits.
        assert_eq!(hex_decode("zz", Some(0)), Err(Fail::LimitExceeded));
        assert_eq!(hex_decode("abc", Some(1)), Err(Fail::InvalidData));
        assert_eq!(hex_decode("zz", None), Err(Fail::InvalidData));
        assert_eq!(hex_decode("0g", None), Err(Fail::InvalidData));
        assert_eq!(hex_decode("00 0", None), Err(Fail::InvalidData));
        assert_eq!(hex_decode("00", Some(-1)), Err(Fail::InvalidInput));
        // A bad digit anywhere in a long input is found.
        let mut long = hex_encode(&[7; 1000]);
        long.replace_range(1500..1501, "x");
        assert_eq!(hex_decode(&long, None), Err(Fail::InvalidData));
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

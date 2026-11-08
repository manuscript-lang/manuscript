//! Number literal spelling: `_` separators and `0x`/`0b` integer radixes.

use std::borrow::Cow;

/// The literal as plain decimal text: separators removed and a `0x` or `0b` value written in
/// base 10. A hex or binary value beyond 128 bits is returned unconverted so range checks fail.
pub fn canonical(text: &str) -> Cow<'_, str> {
    let radix = match text.get(..2) {
        Some("0x") => 16,
        Some("0b") => 2,
        _ => 10,
    };
    let digits = || text.chars().filter(|&c| c != '_');
    if radix == 10 {
        return if text.contains('_') {
            Cow::Owned(digits().collect())
        } else {
            Cow::Borrowed(text)
        };
    }
    let plain: String = digits().skip(2).collect();
    match u128::from_str_radix(&plain, radix) {
        Ok(v) => Cow::Owned(v.to_string()),
        Err(_) => Cow::Borrowed(text),
    }
}

/// Whether canonical literal text is a `Decimal` (`d` suffix). Hex digits `d` and `e` never reach
/// this: `canonical` has already written a `0x` value in base 10.
pub fn is_decimal(canonical: &str) -> bool {
    canonical.ends_with('d')
}

/// Whether canonical literal text is a fractional float (a point or exponent), not an integer or a
/// `Decimal`.
pub fn is_fractional(canonical: &str) -> bool {
    !is_decimal(canonical) && canonical.contains(['.', 'e', 'E'])
}

/// A decimal float literal rounded once, directly to binary32 (a contextual `Float32` literal),
/// widened to `f64` for immediates. Parsing as binary64 first would round twice; the result is
/// infinite when the literal is beyond the finite binary32 range.
pub fn float32(text: &str) -> Option<f64> {
    canonical(text).parse::<f32>().ok().map(f64::from)
}

#[cfg(test)]
mod tests {
    use super::{canonical, float32, is_decimal, is_fractional};

    #[test]
    fn hex_digits_d_and_e_are_not_decimal_or_fractional() {
        for hex in ["0xd", "0xe", "0xde", "0xE", "0x1e5", "0xfd"] {
            let text = canonical(hex);
            assert!(!is_decimal(&text) && !is_fractional(&text), "{hex}");
        }
        assert!(is_decimal("1.5d") && !is_fractional("1.5d"));
        assert!(is_fractional("1e5") && is_fractional("1.5") && !is_fractional("15"));
    }

    #[test]
    fn float32_rounds_once() {
        // One unit below the overflow midpoint rounds to the maximum finite binary32.
        let max = float32("340282356779733661637539395458142568447.0").unwrap();
        assert_eq!(max, f64::from(f32::MAX));
        assert!(
            float32("340282356779733661637539395458142568448.0")
                .unwrap()
                .is_infinite()
        );
        assert_eq!(
            float32("1.0000000596046448").unwrap(),
            f64::from(f32::from_bits(0x3f80_0001))
        );
        assert_eq!(
            float32("1.0000001788139343").unwrap(),
            f64::from(f32::from_bits(0x3f80_0001))
        );
        assert_eq!(
            float32("7.0064923216240854e-46").unwrap(),
            f64::from(f32::from_bits(1))
        );
        assert_eq!(float32("1_0.5").unwrap(), 10.5);
    }

    #[test]
    fn canonicalizes() {
        assert_eq!(canonical("1_000"), "1000");
        assert_eq!(canonical("0xFF_ff"), "65535");
        assert_eq!(canonical("0b1010_0101"), "165");
        assert_eq!(canonical("3.141_592"), "3.141592");
        assert_eq!(canonical("42"), "42");
    }
}

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

#[cfg(test)]
mod tests {
    use super::canonical;

    #[test]
    fn canonicalizes() {
        assert_eq!(canonical("1_000"), "1000");
        assert_eq!(canonical("0xFF_ff"), "65535");
        assert_eq!(canonical("0b1010_0101"), "165");
        assert_eq!(canonical("3.141_592"), "3.141592");
        assert_eq!(canonical("42"), "42");
    }
}

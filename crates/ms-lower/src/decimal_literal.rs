//! Compile-time value of a `Decimal` literal: the coefficient and exponent the runtime's `Decimal`
//! stores (`coefficient * 10^exponent`, at most 34 significant digits, no trailing zeros). The
//! runtime arithmetic is C (`src/runtime/std/decimal.c`); this only reads a literal the checker accepted.

const DIGITS: usize = 34;
const MIN_QUANTUM: i64 = -6176;
const MAX_EXPONENT: i64 = 6144;

/// The runtime layout of a `Decimal`: the coefficient split into two words, and the exponent.
pub(crate) struct DecimalParts {
    pub lo: i64,
    pub hi: i64,
    pub exp: i64,
}

/// Parses a canonical literal such as `-12.50`, `1e-3` or `7d`; `None` when it does not fit the format.
pub(crate) fn parse(text: &str, negate: bool) -> Option<DecimalParts> {
    let raw = text.strip_suffix('d').unwrap_or(text);
    let negative = raw.starts_with('-') != negate;
    let raw = raw.strip_prefix(['-', '+']).unwrap_or(raw);
    let (mantissa, exponent_text) = raw.split_once(['e', 'E']).unwrap_or((raw, "0"));
    let exponent: i64 = exponent_text.parse().ok()?;
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let has_point = mantissa.contains('.');
    if whole.is_empty() || (has_point && fraction.is_empty()) {
        return None;
    }
    let digits = [whole, fraction].concat();
    if !digits.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let significant = digits.trim_start_matches('0');
    if significant.is_empty() {
        return Some(DecimalParts {
            lo: 0,
            hi: 0,
            exp: 0,
        });
    }
    let trimmed = significant.trim_end_matches('0');
    let quantum = exponent - fraction.len() as i64 + (significant.len() - trimmed.len()) as i64;
    let in_range = trimmed.len() <= DIGITS
        && quantum >= MIN_QUANTUM
        && quantum + trimmed.len() as i64 - 1 <= MAX_EXPONENT;
    if !in_range {
        return None;
    }
    let magnitude: i128 = trimmed.parse().ok()?;
    let coefficient = if negative { -magnitude } else { magnitude };
    Some(DecimalParts {
        lo: coefficient as i64,
        hi: (coefficient >> 64) as i64,
        exp: quantum,
    })
}

#[cfg(test)]
mod tests {
    use super::parse;

    fn parts(text: &str) -> Option<(i128, i64)> {
        let p = parse(text, false)?;
        Some(((i128::from(p.hi) << 64) | i128::from(p.lo as u64), p.exp))
    }

    #[test]
    fn literals_normalize_to_a_coefficient_without_trailing_zeros() {
        assert_eq!(parts("12.50"), Some((125, -1)));
        assert_eq!(parts("1e-3"), Some((1, -3)));
        assert_eq!(parts("-700d"), Some((-7, 2)));
        assert_eq!(parts("0.000"), Some((0, 0)));
    }

    #[test]
    fn literals_beyond_the_format_are_rejected() {
        assert_eq!(parts("1.2345678901234567890123456789012345"), None);
        assert_eq!(parts("1e6145"), None);
        assert_eq!(parts("1e-6177"), None);
        assert_eq!(parts("1."), None);
    }

    #[test]
    fn negate_flips_the_sign() {
        let p = parse("5", true).unwrap();
        assert_eq!((p.lo, p.hi), (-5, -1));
    }
}

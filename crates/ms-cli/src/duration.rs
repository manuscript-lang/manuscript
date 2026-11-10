//! CLI durations use the syntax, per-component truncation, and signed range of
//! the standard library's `time.parse_duration`, returning nanoseconds.

/// Parse a duration such as `300ms`, `-1.5h` or `2h45m`.
pub fn parse(text: &str) -> Option<i128> {
    let original = text;
    let mut s = text;
    let mut negative = false;
    if let Some(rest) = s.strip_prefix('-') {
        negative = true;
        s = rest;
    } else if let Some(rest) = s.strip_prefix('+') {
        s = rest;
    }
    if s == "0" {
        return Some(0);
    }
    if s.is_empty() || original.is_empty() {
        return None;
    }
    let limit = i128::from(i64::MAX) + i128::from(negative);
    let mut total: i128 = 0;
    while !s.is_empty() {
        let digits_end = s.find(|c: char| !c.is_ascii_digit()).unwrap_or(s.len());
        let whole = &s[..digits_end];
        s = &s[digits_end..];
        let mut fraction = "";
        if let Some(rest) = s.strip_prefix('.') {
            let end = rest
                .find(|c: char| !c.is_ascii_digit())
                .unwrap_or(rest.len());
            fraction = &rest[..end];
            s = &rest[end..];
            if whole.is_empty() && fraction.is_empty() {
                return None;
            }
        } else if whole.is_empty() {
            return None;
        }
        let unit_end = s
            .find(|c: char| c == '.' || c.is_ascii_digit())
            .unwrap_or(s.len());
        let unit = &s[..unit_end];
        s = &s[unit_end..];
        let scale: i128 = match unit {
            "ns" => 1,
            "us" | "\u{b5}s" | "\u{3bc}s" => 1_000,
            "ms" => 1_000_000,
            "s" => 1_000_000_000,
            "m" => 60 * 1_000_000_000,
            "h" => 3600 * 1_000_000_000,
            _ => return None,
        };
        let whole_value: i128 = if whole.is_empty() {
            0
        } else {
            whole.parse().ok()?
        };
        total = total.checked_add(whole_value.checked_mul(scale)?)?;
        // Reverse decimal evaluation gives floor(fraction * scale) exactly for
        // any number of digits; every intermediate is less than 10 * scale.
        let nanos = fraction
            .bytes()
            .rev()
            .fold(0, |n, digit| (i128::from(digit - b'0') * scale + n) / 10);
        total = total.checked_add(nanos)?;
        if total > limit {
            return None;
        }
    }
    Some(if negative { -total } else { total })
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn go_durations() {
        assert_eq!(parse("0"), Some(0));
        assert_eq!(parse("30s"), Some(30_000_000_000));
        assert_eq!(parse("1m30s"), Some(90_000_000_000));
        assert_eq!(parse("1.5h"), Some(5_400_000_000_000));
        assert_eq!(parse("100ms"), Some(100_000_000));
        assert_eq!(parse("-1s"), Some(-1_000_000_000));
        for bad in ["", "1", "s", "1x", "1..5s", ".s", "abc", "1 s"] {
            assert_eq!(parse(bad), None, "{bad}");
        }
    }

    #[test]
    fn fractional_components_truncate_independently_without_rounding() {
        for (text, expected) in [
            ("0.5ns0.5ns", 0),
            ("1.5ns2.5ns", 3),
            ("-1.5ns2.5ns", -3),
            ("0.999999999999999999ms", 999_999),
            ("0.999999999999999999h", 3_599_999_999_999),
            ("1.999999999999999999ns", 1),
            ("0.000000000000000001h", 0),
            (".5s", 500_000_000),
            ("1.s", 1_000_000_000),
            ("1.5us1.5µs1.5μs", 4_500),
        ] {
            assert_eq!(parse(text), Some(expected), "{text}");
        }
        assert_eq!(
            parse(&format!("0.{}h", "9".repeat(1_000))),
            Some(3_599_999_999_999)
        );
    }

    #[test]
    fn signed_nanosecond_boundaries_are_exact() {
        for (text, expected) in [
            ("9223372036854775807ns", i64::MAX),
            ("-9223372036854775808ns", i64::MIN),
            ("9223372036.854775807999999999s", i64::MAX),
            ("-9223372036.854775808999999999s", i64::MIN),
            ("9223372036854775806ns1.9ns", i64::MAX),
            ("-9223372036854775807ns1.9ns", i64::MIN),
        ] {
            assert_eq!(parse(text), Some(i128::from(expected)), "{text}");
        }
        for text in [
            "9223372036854775808ns",
            "-9223372036854775809ns",
            "9223372036.854775808s",
            "-9223372036.854775809s",
            "9223372036854775807ns1ns",
            "-9223372036854775808ns1ns",
        ] {
            assert_eq!(parse(text), None, "{text}");
        }
    }

    #[test]
    fn fractional_units_agree_with_integer_ratio_oracle() {
        for (unit, scale) in [
            ("ns", 1),
            ("us", 1_000),
            ("ms", 1_000_000),
            ("s", 1_000_000_000),
            ("m", 60_000_000_000),
            ("h", 3_600_000_000_000_i128),
        ] {
            let digits = "123456789876543210999999";
            for end in 1..=digits.len() {
                let fraction = &digits[..end];
                let numerator = fraction.parse::<i128>().unwrap();
                let expected = numerator * scale / 10_i128.pow(end as u32);
                for (sign, value) in [("", expected), ("-", -expected)] {
                    let text = format!("{sign}0.{fraction}{unit}");
                    assert_eq!(parse(&text), Some(value), "{text}");
                }
            }
        }
    }
}

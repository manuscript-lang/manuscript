//! Go `time.ParseDuration`, returning nanoseconds.

/// Parse a duration such as `300ms`, `-1.5h` or `2h45m`. `None` where Go errors.
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
    let mut total: f64 = 0.0;
    let mut exact: i128 = 0;
    let mut integral = true;
    while !s.is_empty() {
        let digits_end = s.find(|c: char| !c.is_ascii_digit()).unwrap_or(s.len());
        let whole = &s[..digits_end];
        s = &s[digits_end..];
        let mut fraction = "";
        if let Some(rest) = s.strip_prefix('.') {
            let end = rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len());
            fraction = &rest[..end];
            s = &rest[end..];
            if whole.is_empty() && fraction.is_empty() {
                return None;
            }
        } else if whole.is_empty() {
            return None;
        }
        let unit_end = s.find(|c: char| c == '.' || c.is_ascii_digit()).unwrap_or(s.len());
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
        let whole_value: i128 = if whole.is_empty() { 0 } else { whole.parse().ok()? };
        exact = exact.checked_add(whole_value.checked_mul(scale)?)?;
        if !fraction.is_empty() {
            integral = false;
            let value: f64 = format!("0.{fraction}").parse().ok()?;
            total += value * scale as f64;
        }
        if exact > i64::MAX as i128 {
            return None;
        }
    }
    let nanos = if integral { exact } else { exact + total as i128 };
    if nanos > i64::MAX as i128 {
        return None;
    }
    Some(if negative { -nanos } else { nanos })
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
}

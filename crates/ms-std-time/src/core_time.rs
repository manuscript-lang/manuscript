//! Timestamp semantics of `@std/time`.
//!
//! Failures are the ABI status codes of `ms-rt-abi` (`TimeError.InvalidInput`, `OutOfRange`,
//! `InvalidData`).
use crate::civil::{
    Civil, MAX_SECONDS, MIN_SECONDS, NANOS_PER_SECOND, civil_of, days_in_month, local_seconds,
};
use crate::zone::Zone;
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;
use ms_rt_abi::{STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE};

/// Seconds since the Unix epoch and a nanosecond part in `0..1_000_000_000`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Ts {
    pub seconds: i64,
    pub nanos: i64,
}

fn in_range(seconds: i64) -> bool {
    (MIN_SECONDS..=MAX_SECONDS).contains(&seconds)
}

/// `time.timestamp(seconds, nanoseconds)`.
pub fn new_timestamp(seconds: i64, nanos: i64) -> Result<Ts, u8> {
    if !(0..NANOS_PER_SECOND).contains(&nanos) || !in_range(seconds) {
        return Err(STATUS_OUT_OF_RANGE);
    }
    Ok(Ts { seconds, nanos })
}

fn digits(b: &[u8]) -> Option<i64> {
    b.iter().try_fold(0i64, |acc, &c| {
        c.is_ascii_digit().then(|| acc * 10 + (c - b'0') as i64)
    })
}

/// `time.parse_timestamp`: RFC 3339 with an optional fraction of 1 to 9 digits and a `Z` or `+hh:mm` zone.
pub fn parse_timestamp(text: &[u8]) -> Result<Ts, u8> {
    let bad = STATUS_INVALID_DATA;
    if text.len() < 20
        || text[4] != b'-'
        || text[7] != b'-'
        || text[10] != b'T'
        || text[13] != b':'
        || text[16] != b':'
    {
        return Err(bad);
    }
    let year = digits(&text[0..4]).ok_or(bad)?;
    let month = digits(&text[5..7]).ok_or(bad)?;
    let day = digits(&text[8..10]).ok_or(bad)?;
    let hour = digits(&text[11..13]).ok_or(bad)?;
    let minute = digits(&text[14..16]).ok_or(bad)?;
    let second = digits(&text[17..19]).ok_or(bad)?;
    let mut i = 19;
    let mut nanos = 0;
    if text[i] == b'.' {
        let start = i + 1;
        i = start;
        while i < text.len() && text[i].is_ascii_digit() {
            i += 1;
        }
        let width = i - start;
        if !(1..=9).contains(&width) {
            return Err(bad);
        }
        nanos = digits(&text[start..i]).ok_or(bad)? * 10i64.pow(9 - width as u32);
    }
    let offset = match &text[i..] {
        b"Z" => 0,
        [sign @ (b'+' | b'-'), h1, h2, b':', m1, m2] => {
            let h = digits(&[*h1, *h2]).ok_or(bad)?;
            let m = digits(&[*m1, *m2]).ok_or(bad)?;
            if h > 23 || m > 59 {
                return Err(bad);
            }
            let seconds = h * 3_600 + m * 60;
            if *sign == b'-' { -seconds } else { seconds }
        }
        _ => return Err(bad),
    };
    if year < 1
        || !(1..=12).contains(&month)
        || day < 1
        || day > days_in_month(year, month)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return Err(bad);
    }
    let seconds = local_seconds(year, month, day, hour, minute, second) - offset;
    if !in_range(seconds) {
        return Err(STATUS_OUT_OF_RANGE);
    }
    Ok(Ts { seconds, nanos })
}

/// `Timestamp.to_string()`: UTC RFC 3339 with the fraction trimmed of trailing zeros.
pub fn to_string(ts: Ts) -> String {
    let c = civil_of(ts.seconds, ts.nanos);
    // Four year digits, the calendar/time separators, nine fractional digits and Z.
    // This is an initial capacity, so internal callers outside the UTC range still grow.
    let mut s = String::with_capacity(30);
    let _ = write!(
        s,
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        c.year, c.month, c.day, c.hour, c.minute, c.second
    );
    if ts.nanos != 0 {
        let _ = write!(s, ".{:09}", ts.nanos);
        while s.ends_with('0') {
            s.pop();
        }
    }
    s.push('Z');
    s
}

/// `Timestamp.shift(duration)`.
pub fn shift(ts: Ts, duration: i64) -> Result<Ts, u8> {
    let total = ts.seconds as i128 * NANOS_PER_SECOND as i128 + ts.nanos as i128 + duration as i128;
    let seconds = total.div_euclid(NANOS_PER_SECOND as i128);
    if seconds < MIN_SECONDS as i128 || seconds > MAX_SECONDS as i128 {
        return Err(STATUS_OUT_OF_RANGE);
    }
    Ok(Ts {
        seconds: seconds as i64,
        nanos: total.rem_euclid(NANOS_PER_SECOND as i128) as i64,
    })
}

/// `Timestamp.difference(other)`: nanoseconds, or out of range when they do not fit.
pub fn difference(left: Ts, other: Ts) -> Result<i64, u8> {
    let d = (left.seconds as i128 - other.seconds as i128) * NANOS_PER_SECOND as i128
        + (left.nanos - other.nanos) as i128;
    i64::try_from(d).map_err(|_| STATUS_OUT_OF_RANGE)
}

pub fn compare(left: Ts, other: Ts) -> i64 {
    let a = (left.seconds, left.nanos);
    let b = (other.seconds, other.nanos);
    (a > b) as i64 - (a < b) as i64
}

/// A timestamp broken down in a zone.
pub struct Calendar {
    pub civil: Civil,
    pub offset_seconds: i64,
    pub zone: String,
}

pub fn calendar(ts: Ts, zone: &str) -> Result<Calendar, u8> {
    let z = Zone::load(zone).ok_or(STATUS_INVALID_INPUT)?;
    let (offset, name) = z.at(ts.seconds);
    Ok(Calendar {
        civil: civil_of(ts.seconds + offset, ts.nanos),
        offset_seconds: offset,
        zone: name,
    })
}

// A padded i64 needs at most 20 bytes; the signed hh:mm offset also fits. Keep
// the ordinary formatter's minimum-width behavior, including years 0 and 10000.
#[derive(Clone, Copy)]
struct TokenText {
    bytes: [u8; 32],
    len: usize,
}

impl Write for TokenText {
    fn write_str(&mut self, text: &str) -> core::fmt::Result {
        let end = self.len + text.len();
        let dst = self.bytes.get_mut(self.len..end).ok_or(core::fmt::Error)?;
        dst.copy_from_slice(text.as_bytes());
        self.len = end;
        Ok(())
    }
}

fn render_token(index: usize, c: &Calendar, out: &mut TokenText) {
    let v = &c.civil;
    let result = match index {
        0 => write!(out, "{:04}", v.year),
        1 => write!(out, "{:02}", v.month),
        2 => write!(out, "{:02}", v.day),
        3 => write!(out, "{:02}", v.hour),
        4 => write!(out, "{:02}", v.minute),
        5 => write!(out, "{:02}", v.second),
        6 => write!(out, "{:03}", v.nanosecond / 1_000_000),
        7 => {
            let sign = if c.offset_seconds < 0 { '-' } else { '+' };
            let abs = c.offset_seconds.abs();
            write!(out, "{sign}{:02}:{:02}", abs / 3_600, abs % 3_600 / 60)
        }
        _ => unreachable!(),
    };
    result.expect("numeric calendar token fits in 32 bytes");
}

/// `Timestamp.format(pattern, zone)`: at each position the first matching token wins, in this order.
pub fn format(ts: Ts, pattern: &[u8], zone: &str) -> Result<Vec<u8>, u8> {
    let c = calendar(ts, zone)?;
    let keys: [&[u8]; 9] = [
        b"YYYY", b"MM", b"DD", b"HH", b"mm", b"ss", b"SSS", b"ZZ", b"zone",
    ];
    let mut values = [TokenText {
        bytes: [0; 32],
        len: 0,
    }; 8];
    let mut out = Vec::with_capacity(pattern.len() + 16);
    let mut i = 0;
    'scan: while i < pattern.len() {
        for (index, key) in keys.iter().enumerate() {
            if pattern[i..].starts_with(key) {
                if index == values.len() {
                    out.extend_from_slice(c.zone.as_bytes());
                } else {
                    let value = &mut values[index];
                    // Every numeric token emits at least one byte; render it only once.
                    if value.len == 0 {
                        render_token(index, &c, value);
                    }
                    out.extend_from_slice(&value.bytes[..value.len]);
                }
                i += key.len();
                continue 'scan;
            }
        }
        out.push(pattern[i]);
        i += 1;
    }
    Ok(out)
}

/// `time.from_calendar(...)`: strictly validated fields; DST gaps and overlaps resolve to the earlier offset.
#[allow(clippy::too_many_arguments)]
pub fn from_calendar(
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
    nanosecond: i64,
    zone: &str,
) -> Result<Ts, u8> {
    let z = Zone::load(zone).ok_or(STATUS_INVALID_INPUT)?;
    let out_of_range = STATUS_OUT_OF_RANGE;
    if !(1..=9999).contains(&year)
        || !(1..=12).contains(&month)
        || day < 1
        || !(0..=23).contains(&hour)
        || !(0..=59).contains(&minute)
        || !(0..=59).contains(&second)
        || !(0..NANOS_PER_SECOND).contains(&nanosecond)
        || day > days_in_month(year, month)
    {
        return Err(out_of_range);
    }
    let local = local_seconds(year, month, day, hour, minute, second);
    // A repeated local time resolves to the earlier instant; a skipped one takes the offset in
    // force before the transition. Candidate offsets come from a day on either side.
    let before = z.offset_at(local - 86_400);
    let after = z.offset_at(local + 86_400);
    let valid = |offset: i64| z.offset_at(local - offset) == offset;
    let offset = match (valid(before), valid(after)) {
        (true, true) => before.max(after),
        (true, false) => before,
        (false, true) => after,
        (false, false) => before,
    };
    let unix = local - offset;
    if !in_range(unix) {
        return Err(out_of_range);
    }
    Ok(Ts {
        seconds: unix,
        nanos: nanosecond,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // The original eager renderer is a byte-for-byte differential oracle for
    // token ordering, padding, truncation and unmatched (possibly non-UTF-8) bytes.
    fn eager_format(ts: Ts, pattern: &[u8], zone: &str) -> Result<Vec<u8>, u8> {
        let c = calendar(ts, zone)?;
        let v = &c.civil;
        let sign = if c.offset_seconds < 0 { '-' } else { '+' };
        let abs = c.offset_seconds.abs();
        let tokens: [(&[u8], String); 9] = [
            (b"YYYY", alloc::format!("{:04}", v.year)),
            (b"MM", alloc::format!("{:02}", v.month)),
            (b"DD", alloc::format!("{:02}", v.day)),
            (b"HH", alloc::format!("{:02}", v.hour)),
            (b"mm", alloc::format!("{:02}", v.minute)),
            (b"ss", alloc::format!("{:02}", v.second)),
            (b"SSS", alloc::format!("{:03}", v.nanosecond / 1_000_000)),
            (
                b"ZZ",
                alloc::format!("{sign}{:02}:{:02}", abs / 3_600, abs % 3_600 / 60),
            ),
            (b"zone", c.zone),
        ];
        let mut out = Vec::new();
        let mut i = 0;
        'scan: while i < pattern.len() {
            for (key, value) in &tokens {
                if pattern[i..].starts_with(key) {
                    out.extend_from_slice(value.as_bytes());
                    i += key.len();
                    continue 'scan;
                }
            }
            out.push(pattern[i]);
            i += 1;
        }
        Ok(out)
    }

    #[test]
    fn format_matches_eager_renderer_across_patterns_and_zones() {
        let patterns: &[&[u8]] = &[
            b"",
            b"literal",
            b"YYYY",
            b"YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]",
            b"YYYYYYYYYMMMMMDDDDHHHHmmmmssssSSSSSSSZZZZzonezone",
            b"YYY M D H m s SS Z zon",
            b"\xffYYYY\x80MM\0zone",
            "日付 YYYY 年 MM 月 DD 日 🕰 HH:mm:ss".as_bytes(),
        ];
        let zones = [
            "UTC",
            "",
            "+23:59",
            "-23:59",
            "Europe/Berlin",
            "America/New_York",
        ];
        let mut random = 42_u64;
        for i in 0..512 {
            random = random
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1);
            let seconds = match i {
                0 => MIN_SECONDS,
                1 => MAX_SECONDS,
                2 => -1,
                3 => 0,
                _ => MIN_SECONDS + (random % (MAX_SECONDS - MIN_SECONDS + 1) as u64) as i64,
            };
            let ts = Ts {
                seconds,
                nanos: (random % 1_000_000_000) as i64,
            };
            for zone in zones {
                for pattern in patterns {
                    assert_eq!(
                        format(ts, pattern, zone),
                        eager_format(ts, pattern, zone),
                        "{ts:?}, {pattern:?}, {zone}"
                    );
                }
            }
        }
    }

    #[test]
    fn format_preserves_extended_years_and_output_growth() {
        let first = Ts {
            seconds: MIN_SECONDS,
            nanos: 0,
        };
        let last = Ts {
            seconds: MAX_SECONDS,
            nanos: 999_999_999,
        };
        assert_eq!(
            format(first, b"YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", "-23:59").unwrap(),
            b"0000-12-31 00:01:00.000 -23:59 [-23:59]"
        );
        assert_eq!(
            format(last, b"YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", "+23:59").unwrap(),
            b"10000-01-01 23:58:59.999 +23:59 [+23:59]"
        );
        assert_eq!(
            format(last, &b"YYYYZZzone".repeat(256), "+23:59").unwrap(),
            b"10000+23:59+23:59".repeat(256)
        );
    }

    #[test]
    fn format_validates_zone_even_without_tokens() {
        let ts = Ts {
            seconds: 0,
            nanos: 0,
        };
        for pattern in [b"".as_slice(), b"literal"] {
            assert_eq!(
                format(ts, pattern, "Nowhere/City"),
                Err(STATUS_INVALID_INPUT)
            );
        }
    }
    use alloc::string::ToString;

    fn ts(text: &str) -> Ts {
        parse_timestamp(text.as_bytes()).unwrap()
    }

    #[test]
    fn parses_and_prints_rfc3339() {
        assert_eq!(
            ts("1970-01-01T00:00:00Z"),
            Ts {
                seconds: 0,
                nanos: 0
            }
        );
        assert_eq!(
            ts("2024-02-29T12:30:45.5+02:00"),
            Ts {
                seconds: 1_709_202_645,
                nanos: 500_000_000
            }
        );
        assert_eq!(
            to_string(ts("2024-02-29T12:30:45.120+02:00")),
            "2024-02-29T10:30:45.12Z"
        );
        assert_eq!(
            to_string(ts("0001-01-01T00:00:00Z")),
            "0001-01-01T00:00:00Z"
        );
        assert_eq!(
            parse_timestamp(b"2023-02-29T00:00:00Z"),
            Err(STATUS_INVALID_DATA)
        );
        assert_eq!(
            parse_timestamp(b"2024-01-01T00:00:60Z"),
            Err(STATUS_INVALID_DATA)
        );
        assert_eq!(
            parse_timestamp(b"2024-01-01T00:00:00.1234567890Z"),
            Err(STATUS_INVALID_DATA)
        );
        assert_eq!(
            parse_timestamp(b"2024-01-01t00:00:00z"),
            Err(STATUS_INVALID_DATA)
        );
        assert_eq!(
            parse_timestamp(b"0000-01-01T00:00:00Z"),
            Err(STATUS_INVALID_DATA)
        );
        assert_eq!(
            parse_timestamp(b"0001-01-01T00:00:00+01:00"),
            Err(STATUS_OUT_OF_RANGE)
        );
        assert_eq!(
            parse_timestamp(b"9999-12-31T23:59:59-01:00"),
            Err(STATUS_OUT_OF_RANGE)
        );
    }

    #[test]
    fn shifts_and_differences() {
        let a = ts("2024-01-01T00:00:00Z");
        assert_eq!(
            to_string(shift(a, -1).unwrap()),
            "2023-12-31T23:59:59.999999999Z"
        );
        assert_eq!(
            shift(ts("9999-12-31T23:59:59.999999999Z"), 1),
            Err(STATUS_OUT_OF_RANGE)
        );
        assert_eq!(difference(shift(a, 5).unwrap(), a), Ok(5));
        assert_eq!(
            difference(ts("9999-12-31T00:00:00Z"), ts("0001-01-01T00:00:00Z")),
            Err(STATUS_OUT_OF_RANGE)
        );
        assert_eq!(compare(a, shift(a, 1).unwrap()), -1);
    }

    #[test]
    fn zones() {
        let t = ts("2024-07-04T16:05:09.123456789Z");
        let c = calendar(t, "America/New_York").unwrap();
        assert_eq!(
            (c.civil.hour, c.offset_seconds, c.zone.as_str()),
            (12, -4 * 3600, "EDT")
        );
        let c = calendar(t, "+05:30").unwrap();
        assert_eq!(
            (c.civil.hour, c.civil.minute, c.zone.as_str()),
            (21, 35, "+05:30")
        );
        assert_eq!(
            calendar(t, "Nowhere/City").err(),
            Some(STATUS_INVALID_INPUT)
        );
        // Names are case-sensitive, as zoneinfo file names are in Go.
        for name in [
            "america/new_york",
            "AMERICA/NEW_YORK",
            "utc",
            "Utc",
            "local",
        ] {
            assert_eq!(
                calendar(t, name).err(),
                Some(STATUS_INVALID_INPUT),
                "{name}"
            );
        }
        assert!(calendar(t, "US/Pacific").is_ok());
        let text = format(t, b"YYYY-MM-DD HH:mm:ss.SSS ZZ [zone] SS", "Europe/Berlin").unwrap();
        assert_eq!(
            core::str::from_utf8(&text).unwrap(),
            "2024-07-04 18:05:09.123 +02:00 [CEST] SS"
        );
    }

    #[test]
    fn timestamp_text_matches_previous_renderer() {
        let mut random = 7_u64;
        for i in 0..512 {
            random = random
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1);
            let seconds = match i {
                0 => MIN_SECONDS,
                1 => MAX_SECONDS,
                2 => -1,
                3 => 0,
                _ => MIN_SECONDS + (random % (MAX_SECONDS - MIN_SECONDS + 1) as u64) as i64,
            };
            for nanos in [
                0,
                1,
                9,
                10,
                99,
                100,
                99_999_999,
                100_000_000,
                250_000_000,
                999_999_999,
            ] {
                let c = civil_of(seconds, nanos);
                let mut previous = String::new();
                let _ = write!(
                    previous,
                    "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
                    c.year, c.month, c.day, c.hour, c.minute, c.second
                );
                if nanos != 0 {
                    let mut frac = String::new();
                    let _ = write!(frac, "{:09}", nanos);
                    previous.push('.');
                    previous.push_str(frac.trim_end_matches('0'));
                }
                previous.push('Z');
                let value = Ts { seconds, nanos };
                assert_eq!(to_string(value), previous, "{value:?}");
                assert_eq!(parse_timestamp(previous.as_bytes()), Ok(value));
            }
        }
    }

    #[test]
    fn calendar_to_timestamp() {
        let f = |y, mo, d, h, zone: &str| from_calendar(y, mo, d, h, 30, 0, 0, zone).map(to_string);
        assert_eq!(
            f(2024, 7, 4, 12, "America/New_York").unwrap(),
            "2024-07-04T16:30:00Z"
        );
        // Spring forward: 02:30 does not exist; the offset in force before the gap (EST) applies.
        assert_eq!(
            f(2024, 3, 10, 2, "America/New_York").unwrap(),
            "2024-03-10T07:30:00Z"
        );
        // Midnight gap (Santiago skips 00:00-01:00): resolves instead of failing.
        assert_eq!(
            from_calendar(2024, 9, 8, 0, 30, 0, 0, "America/Santiago")
                .map(to_string)
                .unwrap(),
            "2024-09-08T04:30:00Z"
        );
        // Repeated hour east of UTC: the earlier instant (BST).
        assert_eq!(
            f(2024, 10, 27, 1, "Europe/London").unwrap(),
            "2024-10-27T00:30:00Z"
        );
        // Fall back: 01:30 occurs twice; the first (EDT) wins.
        assert_eq!(
            f(2024, 11, 3, 1, "America/New_York").unwrap(),
            "2024-11-03T05:30:00Z"
        );
        assert_eq!(f(2024, 2, 30, 1, "UTC"), Err(STATUS_OUT_OF_RANGE));
        assert_eq!(f(2024, 2, 1, 1, "Bogus/Zone"), Err(STATUS_INVALID_INPUT));
        assert_eq!(f(1, 1, 1, 0, "+01:00"), Err(STATUS_OUT_OF_RANGE));
        let _ = "".to_string();
    }
}

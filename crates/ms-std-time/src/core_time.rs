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
    let mut s = String::new();
    let _ = write!(
        s,
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        c.year, c.month, c.day, c.hour, c.minute, c.second
    );
    if ts.nanos != 0 {
        let mut frac = String::new();
        let _ = write!(frac, "{:09}", ts.nanos);
        s.push('.');
        s.push_str(frac.trim_end_matches('0'));
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

/// `Timestamp.format(pattern, zone)`: at each position the first matching token wins, in this order.
pub fn format(ts: Ts, pattern: &[u8], zone: &str) -> Result<Vec<u8>, u8> {
    let c = calendar(ts, zone)?;
    let (sign, abs) = if c.offset_seconds < 0 {
        ('-', -c.offset_seconds)
    } else {
        ('+', c.offset_seconds)
    };
    let v = &c.civil;
    let mut tokens: [(&[u8], String); 9] = [
        (b"YYYY", String::new()),
        (b"MM", String::new()),
        (b"DD", String::new()),
        (b"HH", String::new()),
        (b"mm", String::new()),
        (b"ss", String::new()),
        (b"SSS", String::new()),
        (b"ZZ", String::new()),
        (b"zone", c.zone.clone()),
    ];
    let _ = write!(tokens[0].1, "{:04}", v.year);
    let _ = write!(tokens[1].1, "{:02}", v.month);
    let _ = write!(tokens[2].1, "{:02}", v.day);
    let _ = write!(tokens[3].1, "{:02}", v.hour);
    let _ = write!(tokens[4].1, "{:02}", v.minute);
    let _ = write!(tokens[5].1, "{:02}", v.second);
    let _ = write!(tokens[6].1, "{:03}", v.nanosecond / 1_000_000);
    let _ = write!(
        tokens[7].1,
        "{sign}{:02}:{:02}",
        abs / 3_600,
        abs % 3_600 / 60
    );
    let mut out = Vec::with_capacity(pattern.len() + 16);
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

/// `time.from_calendar(...)`: strictly validated fields, resolved like Go's `time.Date`.
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
    // Go's `Date`: guess the offset at the local time read as UTC, then correct it once.
    let offset = z.offset_at(local);
    let unix = local - z.offset_at(local - offset);
    let seen = civil_of(unix + z.offset_at(unix), 0);
    if seen.day != day || seen.month != month || !in_range(unix) {
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
    fn calendar_to_timestamp() {
        let f = |y, mo, d, h, zone: &str| from_calendar(y, mo, d, h, 30, 0, 0, zone).map(to_string);
        assert_eq!(
            f(2024, 7, 4, 12, "America/New_York").unwrap(),
            "2024-07-04T16:30:00Z"
        );
        // Spring forward: 02:30 does not exist; Go resolves it with the offset in force after the gap.
        assert_eq!(
            f(2024, 3, 10, 2, "America/New_York").unwrap(),
            "2024-03-10T06:30:00Z"
        );
        // Fall back: 01:30 occurs twice; Go picks the first (EDT).
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

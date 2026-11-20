//! Proleptic Gregorian calendar arithmetic on Unix seconds (all functions are total on `i64` ranges
//! that matter: timestamps are limited to years 1 through 9999).

/// Smallest and largest timestamp seconds (0001-01-01T00:00:00Z and 9999-12-31T23:59:59Z).
pub const MIN_SECONDS: i64 = -62_135_596_800;
pub const MAX_SECONDS: i64 = 253_402_300_799;
pub const NANOS_PER_SECOND: i64 = 1_000_000_000;

/// Days since 1970-01-01 of a civil date (`month` 1..=12).
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The civil date of a day number since 1970-01-01.
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

pub fn is_leap(year: i64) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

pub fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        2 if is_leap(year) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Calendar fields of a local time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Civil {
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub second: i64,
    pub nanosecond: i64,
    /// Sunday is 0.
    pub weekday: i64,
    /// January 1 is 1.
    pub day_of_year: i64,
}

/// Breaks local seconds (Unix seconds plus the zone offset) and nanoseconds into fields.
pub fn civil_of(local_seconds: i64, nanosecond: i64) -> Civil {
    let days = local_seconds.div_euclid(86_400);
    let rem = local_seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    Civil {
        year,
        month,
        day,
        hour: rem / 3_600,
        minute: rem % 3_600 / 60,
        second: rem % 60,
        nanosecond,
        weekday: (days + 4).rem_euclid(7),
        day_of_year: days - days_from_civil(year, 1, 1) + 1,
    }
}

/// Local seconds of a civil date and time of day.
pub fn local_seconds(year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64) -> i64 {
    days_from_civil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_every_day_in_range() {
        let first = days_from_civil(1, 1, 1);
        let last = days_from_civil(9999, 12, 31);
        assert_eq!(first * 86_400, MIN_SECONDS);
        assert_eq!(last * 86_400 + 86_399, MAX_SECONDS);
        let mut d = first;
        while d <= last {
            let (y, m, dd) = civil_from_days(d);
            assert_eq!(days_from_civil(y, m, dd), d);
            assert!(dd >= 1 && dd <= days_in_month(y, m));
            d += 1;
        }
    }

    #[test]
    fn fields() {
        let c = civil_of(1_709_164_800, 5); // 2024-02-29T00:00:00Z, a Thursday
        assert_eq!(
            (c.year, c.month, c.day, c.weekday, c.day_of_year),
            (2024, 2, 29, 4, 60)
        );
        let c = civil_of(-1, 0);
        assert_eq!(
            (
                c.year, c.month, c.day, c.hour, c.minute, c.second, c.weekday
            ),
            (1969, 12, 31, 23, 59, 59, 3)
        );
    }
}

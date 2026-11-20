//! The zone database behind the C time natives (runtime/std/time_zone.c): IANA names from the bundled tzdb and the
//! host's local zone. UTC and fixed offsets are handled in C. This crate goes away when the zone data is read in C.
use alloc::string::{String, ToString};
use jiff::tz::{AmbiguousOffset, TimeZone};

/// Resolves `Local` or an IANA name; `None` for anything else (names are case-sensitive, as in Go).
pub fn load(zone: &str) -> Option<TimeZone> {
    if zone == "Local" {
        return Some(TimeZone::system());
    }
    if zone.contains("..") || zone.starts_with('/') || zone.starts_with('\\') {
        return None;
    }
    // The bundled database matches names case-insensitively; Go reads zoneinfo files by exact name.
    let tz = TimeZone::get(zone).ok()?;
    (tz.iana_name() == Some(zone)).then_some(tz)
}

/// Offset east of UTC in seconds and the zone abbreviation at a Unix time.
pub fn at(tz: &TimeZone, unix: i64) -> (i64, String) {
    let ts = jiff::Timestamp::from_second(unix).unwrap_or(if unix < 0 {
        jiff::Timestamp::MIN
    } else {
        jiff::Timestamp::MAX
    });
    let info = tz.to_offset_info(ts);
    (
        i64::from(info.offset().seconds()),
        info.abbreviation().to_string(),
    )
}

/// Local calendar fields the caller has validated (year 1 to 9999, a real day, a time of day).
pub struct LocalFields {
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub second: i64,
    pub nanosecond: i64,
}

/// The offset for validated local fields, choosing the pre-transition offset in gaps and folds.
pub fn offset_for_local(tz: &TimeZone, f: &LocalFields) -> i64 {
    let datetime = jiff::civil::DateTime::new(
        f.year as i16,
        f.month as i8,
        f.day as i8,
        f.hour as i8,
        f.minute as i8,
        f.second as i8,
        f.nanosecond as i32,
    )
    .expect("from_calendar validates civil fields");
    // Inspect the raw offset rather than constructing a Jiff Timestamp, whose
    // supported range excludes part of Manuscript's final UTC day.
    let offset = match tz.to_ambiguous_timestamp(datetime).offset() {
        AmbiguousOffset::Unambiguous { offset } => offset,
        AmbiguousOffset::Gap { before, .. } | AmbiguousOffset::Fold { before, .. } => before,
    };
    i64::from(offset.seconds())
}

/// `time.local_zone()`: the IANA name of the local zone, `UTC` when it has none.
pub fn local_zone_name() -> String {
    TimeZone::system()
        .iana_name()
        .map_or_else(|| "UTC".to_string(), ToString::to_string)
}

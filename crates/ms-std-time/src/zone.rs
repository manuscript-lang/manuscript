//! Zones: UTC, fixed offsets such as `+05:30`, the host's local zone and IANA names (bundled data).
use alloc::string::{String, ToString};
use jiff::tz::TimeZone;

pub enum Zone {
    Utc,
    Fixed { seconds: i32, name: String },
    Named(TimeZone),
}

/// `^[+-](?:[01][0-9]|2[0-3]):[0-5][0-9]$`
fn fixed_offset(zone: &str) -> Option<i32> {
    let b = zone.as_bytes();
    if b.len() != 6 || !(b[0] == b'+' || b[0] == b'-') || b[3] != b':' {
        return None;
    }
    let d = |i: usize| b[i].is_ascii_digit().then(|| (b[i] - b'0') as i32);
    let hours = d(1)? * 10 + d(2)?;
    let minutes = d(4)? * 10 + d(5)?;
    if hours > 23 || minutes > 59 {
        return None;
    }
    let seconds = hours * 3_600 + minutes * 60;
    Some(if b[0] == b'-' { -seconds } else { seconds })
}

impl Zone {
    /// Resolves `UTC`, the empty string, `Local`, a fixed offset or an IANA name.
    pub fn load(zone: &str) -> Option<Zone> {
        match zone {
            "UTC" | "" => return Some(Zone::Utc),
            "Local" => return Some(local()),
            _ => {}
        }
        if let Some(seconds) = fixed_offset(zone) {
            return Some(Zone::Fixed {
                seconds,
                name: zone.to_string(),
            });
        }
        named(zone)
    }

    /// Offset east of UTC in seconds and the zone abbreviation at a Unix time.
    pub fn at(&self, unix: i64) -> (i64, String) {
        match self {
            Zone::Utc => (0, "UTC".to_string()),
            Zone::Fixed { seconds, name } => (*seconds as i64, name.clone()),
            Zone::Named(tz) => {
                let ts = jiff::Timestamp::from_second(unix).unwrap_or(if unix < 0 {
                    jiff::Timestamp::MIN
                } else {
                    jiff::Timestamp::MAX
                });
                let info = tz.to_offset_info(ts);
                (
                    info.offset().seconds() as i64,
                    info.abbreviation().to_string(),
                )
            }
        }
    }

    pub fn offset_at(&self, unix: i64) -> i64 {
        match self {
            Zone::Utc => 0,
            Zone::Fixed { seconds, .. } => *seconds as i64,
            Zone::Named(_) => self.at(unix).0,
        }
    }
}

fn named(name: &str) -> Option<Zone> {
    if name.contains("..") || name.starts_with('/') || name.starts_with('\\') {
        return None;
    }
    // The bundled database matches names case-insensitively; Go reads zoneinfo files by exact name.
    let tz = TimeZone::get(name).ok()?;
    (tz.iana_name() == Some(name)).then_some(Zone::Named(tz))
}

/// The host's local zone as jiff reads it: `TZ`, then `/etc/localtime` on Unix and the system
/// setting on Windows, else UTC.
pub fn local() -> Zone {
    Zone::Named(jiff::tz::TimeZone::system())
}

/// `time.local_zone()`: the IANA name of the local zone, `UTC` when it has none.
pub fn local_zone_name() -> String {
    jiff::tz::TimeZone::system()
        .iana_name()
        .map_or_else(|| "UTC".to_string(), ToString::to_string)
}

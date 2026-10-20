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

#[cfg(unix)]
mod host {
    use super::{Zone, named};
    use alloc::string::{String, ToString};

    unsafe extern "C" {
        fn getenv(name: *const u8) -> *const u8;
        fn readlink(path: *const u8, buf: *mut u8, size: usize) -> isize;
    }

    fn env_tz() -> Option<String> {
        // SAFETY: `getenv` takes a NUL-terminated name and returns a NUL-terminated string or null.
        let p = unsafe { getenv(c"TZ".as_ptr().cast()) };
        if p.is_null() {
            return None;
        }
        let mut len = 0;
        // SAFETY: the string is NUL-terminated.
        while unsafe { *p.add(len) } != 0 {
            len += 1;
        }
        // SAFETY: `len` bytes were just scanned.
        let bytes = unsafe { core::slice::from_raw_parts(p, len) };
        Some(String::from_utf8_lossy(bytes).into_owned())
    }

    /// The zone name behind `/etc/localtime`, when it is a symlink into a zoneinfo tree.
    fn localtime_link() -> Option<String> {
        let mut buf = [0u8; 256];
        // SAFETY: the path is NUL-terminated and `buf` is writable for its length.
        let n = unsafe {
            readlink(
                c"/etc/localtime".as_ptr().cast(),
                buf.as_mut_ptr(),
                buf.len(),
            )
        };
        if n <= 0 {
            return None;
        }
        let target = core::str::from_utf8(&buf[..n as usize]).ok()?;
        target
            .rsplit_once("zoneinfo/")
            .map(|(_, name)| name.to_string())
    }

    /// The host's local zone: `TZ`, else `/etc/localtime`, else UTC.
    pub fn local() -> Zone {
        let name = match env_tz() {
            Some(tz) => tz.strip_prefix(':').unwrap_or(&tz).to_string(),
            None => localtime_link().unwrap_or_default(),
        };
        if name.is_empty() || name == "UTC" {
            return Zone::Utc;
        }
        named(&name).unwrap_or(Zone::Utc)
    }

    /// `time.local_zone()`: the `TZ` name when it loads, else `UTC`.
    pub fn local_zone_name() -> String {
        match env_tz() {
            Some(tz) => {
                let name = tz.strip_prefix(':').unwrap_or(&tz);
                if !name.is_empty() && named(name).is_some() {
                    name.to_string()
                } else {
                    "UTC".to_string()
                }
            }
            None => "UTC".to_string(),
        }
    }
}

/// Windows ignores `TZ`; the local zone is the system setting, mapped to an IANA zone by jiff.
/// Like Go's `time.Local` there, it has no IANA name, so `local_zone()` stays `UTC`.
#[cfg(windows)]
mod host {
    use super::Zone;
    use alloc::string::{String, ToString};

    pub fn local() -> Zone {
        Zone::Named(jiff::tz::TimeZone::system())
    }

    pub fn local_zone_name() -> String {
        "UTC".to_string()
    }
}

use host::local;
pub use host::local_zone_name;

//! Portable clocks and the host's zone setting behind the native time wrappers.
use alloc::string::String;
use alloc::vec::Vec;

/// Seconds and nanoseconds since the Unix epoch; the nanoseconds stay in `0..1e9` before it too.
pub fn realtime() -> (i64, i64) {
    use std::time::{SystemTime, UNIX_EPOCH};
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => (d.as_secs() as i64, i64::from(d.subsec_nanos())),
        Err(e) => {
            let d = e.duration();
            let nanos = i64::from(d.subsec_nanos());
            if nanos == 0 {
                (-(d.as_secs() as i64), 0)
            } else {
                (-(d.as_secs() as i64) - 1, 1_000_000_000 - nanos)
            }
        }
    }
}

/// Nanoseconds since the first reading in this process.
pub fn monotonic_since_start() -> i64 {
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_nanos() as i64
}

/// How the host names its local zone (the `TZ` setting first, on every platform), for `@std/internal/zone.ms` to resolve:
/// `tz:<value>` from the `TZ` setting (an IANA name or a POSIX rule; `UTC` when empty),
/// `link:<name>` when `/etc/localtime` links into a zoneinfo directory, `windows:<key>` for a
/// Windows time-zone key, and the empty string when only the system zone file is left.
#[allow(unsafe_code)] // the Win32 time-zone call
pub fn system_zone() -> String {
    if let Some(value) = std::env::var_os("TZ") {
        let text = value.to_str().unwrap_or("");
        let text = text.strip_prefix(':').unwrap_or(text);
        let name = text.rsplit_once("zoneinfo/").map_or(text, |(_, name)| name);
        return std::format!("tz:{}", if name.is_empty() { "UTC" } else { name });
    }
    #[cfg(unix)]
    {
        if let Ok(target) = std::fs::read_link("/etc/localtime")
            && let Some((_, name)) = target.to_str().unwrap_or("").rsplit_once("zoneinfo/")
        {
            return std::format!("link:{name}");
        }
        String::new()
    }
    #[cfg(windows)]
    {
        use windows_sys::Win32::System::Time::{
            DYNAMIC_TIME_ZONE_INFORMATION, GetDynamicTimeZoneInformation,
        };
        // SAFETY: the structure is plain data that the call fills in before it is read.
        let info = unsafe {
            let mut info: DYNAMIC_TIME_ZONE_INFORMATION = core::mem::zeroed();
            if GetDynamicTimeZoneInformation(&mut info) == u32::MAX {
                return String::new();
            }
            info
        };
        let key = &info.TimeZoneKeyName;
        let length = key.iter().position(|&unit| unit == 0).unwrap_or(key.len());
        std::format!("windows:{}", String::from_utf16_lossy(&key[..length]))
    }
    #[cfg(not(any(unix, windows)))]
    {
        String::new()
    }
}

/// The contents of the system zone file (`/etc/localtime`), empty when there is none.
pub fn system_zone_file() -> Vec<u8> {
    #[cfg(unix)]
    {
        std::fs::read("/etc/localtime").unwrap_or_default()
    }
    #[cfg(not(unix))]
    {
        Vec::new()
    }
}

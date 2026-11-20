//! The zone seam of `@std/time`. Everything else in the module is C (runtime/std/time*.c); the C code asks this
//! crate for the offset of a named zone, because the tz database is read with `jiff`. Removed when it is read in C.
//! ms: domain time
#![no_std]

extern crate alloc;
extern crate std;

pub mod zone;

use alloc::string::String;
use ms_rt::ffi::{StatusCode, Str, abi_type, native};
use ms_rt_abi::STATUS_INVALID_INPUT;

abi_type! {
    /// What a zone says about one instant: the offset east of UTC and the zone abbreviation (an owned string).
    pub struct ZoneInfo {
        pub offset: i64,
        pub name: Str,
    }
}

fn unknown_zone() -> StatusCode {
    StatusCode(STATUS_INVALID_INPUT)
}

native! {
    /// The offset and abbreviation of `zone` (`Local` or an IANA name) at a Unix time.
    fn msstd_time_zone_info(zone: &str, unix: i64) -> Result<ZoneInfo, StatusCode> {
        let tz = zone::load(zone).ok_or_else(unknown_zone)?;
        let (offset, name) = zone::at(&tz, unix);
        Ok(ZoneInfo { offset, name: Str::new(&name) })
    }

    /// The offset of `zone` for validated local fields, earlier offset in a gap or fold.
    fn msstd_time_zone_local_offset(
        zone: &str,
        year: i64,
        month: i64,
        day: i64,
        hour: i64,
        minute: i64,
        second: i64,
        nanosecond: i64,
    ) -> Result<i64, StatusCode> {
        let tz = zone::load(zone).ok_or_else(unknown_zone)?;
        let fields = zone::LocalFields { year, month, day, hour, minute, second, nanosecond };
        Ok(zone::offset_for_local(&tz, &fields))
    }

    /// `time.local_zone()`.
    safe fn msstd_time_local_zone() -> String {
        zone::local_zone_name()
    }
}

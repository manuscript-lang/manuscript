//! C ABI shims for `@std/semver.ms` (`msrt_semver_*`).
//!
//! `Version` is a record `major, minor, patch: Int, prerelease, build: List[String]` in declaration
//! order ([`VersionRec`]); lists written by the runtime are owned by the record.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::Version;
use ms_std_core::{StrObj, VecVal, new_string, read_string_list, str_ref, write_string_list};

#[repr(C)]
pub struct VersionRec {
    pub major: i64,
    pub minor: i64,
    pub patch: i64,
    pub prerelease: VecVal,
    pub build: VecVal,
}

unsafe fn read_version(v: *const VersionRec) -> Version {
    // SAFETY: `v` is a live Version record.
    unsafe {
        let v = &*v;
        let strings = |l: *const VecVal| read_string_list(l).into_iter().map(Into::into).collect();
        Version {
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            prerelease: strings(&raw const v.prerelease),
            build: strings(&raw const v.build),
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_semver_parse(text: *const StrObj, out: *mut VersionRec) -> u8 {
    // SAFETY: `text` is live; `out` is writable memory for a record.
    unsafe {
        match crate::parse(str_ref(text)) {
            Ok(v) => {
                (&raw mut (*out).major).write(v.major);
                (&raw mut (*out).minor).write(v.minor);
                (&raw mut (*out).patch).write(v.patch);
                write_string_list(&raw mut (*out).prerelease, &v.prerelease);
                write_string_list(&raw mut (*out).build, &v.build);
                0
            }
            Err(e) => e.status(),
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_semver_format(v: *const VersionRec) -> *mut StrObj {
    // SAFETY: `v` is a live Version record.
    new_string(&crate::format(&unsafe { read_version(v) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_semver_compare(l: *const VersionRec, r: *const VersionRec) -> i64 {
    // SAFETY: both are live Version records.
    unsafe { crate::compare(&read_version(l), &read_version(r)) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols

    #[test]
    fn abi_roundtrip() {
        let t = new_string("1.2.3-rc.1+b.7");
        let mut rec = MaybeUninit::<VersionRec>::uninit();
        // SAFETY: pointers are live; the record is released below.
        unsafe {
            assert_eq!(msrt_semver_parse(t, rec.as_mut_ptr()), 0);
            let f = msrt_semver_format(rec.as_ptr());
            assert_eq!(str_ref(f), "1.2.3-rc.1+b.7");
            assert_eq!(msrt_semver_compare(rec.as_ptr(), rec.as_ptr()), 0);
            let bad = new_string("01.2.3");
            assert_eq!(msrt_semver_parse(bad, rec.as_mut_ptr()), 4);
            let big = new_string("99999999999999999999.2.3");
            assert_eq!(msrt_semver_parse(big, rec.as_mut_ptr()), 2);
        }
    }
}

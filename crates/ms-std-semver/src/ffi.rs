//! C ABI shims for `@std/semver.ms` (`msrt_semver_*`).
//!
//! `Version` is a record `major, minor, patch: Int, prerelease, build: List[String]` in declaration
//! order ([`VersionRec`]); lists written by the runtime are owned by the record.
use crate::{SemverFail, Version};
use alloc::string::String;
use ms_std_core::{Status, StringList, abi_record, native};

abi_record! {
    pub struct VersionRec {
        pub major: i64,
        pub minor: i64,
        pub patch: i64,
        pub prerelease: StringList,
        pub build: StringList,
    }
}

impl Status for SemverFail {
    fn status(self) -> u8 {
        SemverFail::status(self)
    }
}

fn read_version(v: &VersionRec) -> Version {
    let strings = |l: &StringList| l.to_vec().into_iter().map(Into::into).collect();
    Version {
        major: v.major,
        minor: v.minor,
        patch: v.patch,
        prerelease: strings(&v.prerelease),
        build: strings(&v.build),
    }
}

fn write_version(v: Version) -> VersionRec {
    VersionRec {
        major: v.major,
        minor: v.minor,
        patch: v.patch,
        prerelease: StringList::new(&v.prerelease),
        build: StringList::new(&v.build),
    }
}

native! {
    fn msrt_semver_parse(text: &str) -> Result<VersionRec, SemverFail> {
        crate::parse(text).map(write_version)
    }

    fn msrt_semver_format(v: &VersionRec) -> String {
        crate::format(&read_version(v))
    }

    fn msrt_semver_compare(l: &VersionRec, r: &VersionRec) -> i64 {
        crate::compare(&read_version(l), &read_version(r))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt as _; // links the msrt_* runtime symbols
    use ms_std_core::{new_string, str_ref};

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

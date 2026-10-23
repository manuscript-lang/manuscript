//! ABI round trip through the C entry points. Lives here, not in `ffi.rs`: `ms-rt` links
#![allow(unsafe_code)]

//! this crate's rlib, so a unit test that also uses `ms-rt` defines every `msrt_path_*` twice.
use ms_rt as _; // links the msrt_* runtime symbols
use ms_std_core::{StrVal, new_string, str_ref, str_release, take_string};
use ms_std_path::ffi::*;

#[test]
fn abi_roundtrip() {
    let p = new_string("/a/b/c.txt");
    let mut rec = core::mem::MaybeUninit::<[StrVal; 5]>::uninit();
    // SAFETY: all pointers are live; results are released below.
    unsafe {
        msrt_path_parse(0, &p, rec.as_mut_ptr());
        let r = rec.assume_init_ref();
        assert_eq!(
            (str_ref(&r[2]), str_ref(&r[3]), str_ref(&r[4])),
            ("c.txt", ".txt", "c")
        );
        let f = take_string(|o| msrt_path_format(0, rec.as_ptr(), o));
        assert_eq!(f, "/a/b/c.txt");
        let mut ok = 0u8;
        let pat = new_string("/a/*/c.*");
        assert_eq!(msrt_path_matches_glob(0, &p, &pat, &mut ok), 0);
        assert_eq!(ok, 1);
        for o in r.iter().chain([&p, &pat]) {
            str_release(o);
        }
    }
}

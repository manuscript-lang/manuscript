//! ABI round trip through the C entry point. Lives here, not in `ffi.rs`: `ms-rt` links
//! this crate's rlib, so a unit test that also uses `ms-rt` defines every `msstd_path_*` twice.
#![allow(unsafe_code)]

use ms_rt as _; // links the msrt_* runtime symbols
use ms_rt::ffi::{new_string, str_release};
use ms_std_path::ffi::*;

#[test]
fn abi_roundtrip() {
    let p = new_string("/a/b/c.txt");
    let pat = new_string("/a/*/c.*");
    let mut ok = 0u8;
    // SAFETY: all pointers are live; results are released below.
    unsafe {
        assert_eq!(msstd_path_matches_glob(0, &p, &pat, &mut ok), 0);
        assert_eq!(ok, 1);
        str_release(&p);
        str_release(&pat);
    }
}

//! ABI round trip through the C entry points. Lives here, not in `ffi.rs`: `ms-rt` links
//! this crate's rlib, so a unit test that also uses `ms-rt` defines every `msstd_path_*` twice.
#![allow(unsafe_code)]

use ms_rt as _; // links the msrt_* runtime symbols

#[test]
fn abi_symbols_link() {
    // The handle entry points are exercised end to end by the `path-glob` conformance test;
    // this only pins that the symbols exist in the rlib.
    let _compile = ms_std_path::ffi::msstd_path_compile_glob as *const ();
    let _matches = ms_std_path::ffi::msstd_path_glob_matches as *const ();
}

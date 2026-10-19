//! ABI round trip through the C entry points. Lives here, not in `ffi.rs`: `ms-rt` links
#![allow(unsafe_code)]

//! this crate's rlib, so a unit test that also uses `ms-rt` defines every `msrt_path_*` twice.
use ms_rt::obj::msrt_release;
use ms_std_core::{new_string, str_ref};
use ms_std_path::ffi::*;

#[test]
fn abi_roundtrip() {
    let p = new_string("/a/b/c.txt");
    let mut rec = core::mem::MaybeUninit::<PartsRec>::uninit();
    // SAFETY: all pointers are live; results are released below.
    unsafe {
        msrt_path_parse(0, p, rec.as_mut_ptr());
        let r = rec.assume_init_ref();
        assert_eq!(
            (str_ref(r.base), str_ref(r.extension), str_ref(r.name)),
            ("c.txt", ".txt", "c")
        );
        let f = msrt_path_format(0, rec.as_ptr());
        assert_eq!(str_ref(f), "/a/b/c.txt");
        let mut ok = 0u8;
        let pat = new_string("/a/*/c.*");
        assert_eq!(msrt_path_matches_glob(0, p, pat, &mut ok), 0);
        assert_eq!(ok, 1);
        for o in [r.root, r.directory, r.base, r.extension, r.name, p, f, pat] {
            msrt_release(o.cast());
        }
    }
}

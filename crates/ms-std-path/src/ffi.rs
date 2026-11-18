//! C ABI shim for `@std/os/path.ms`: a `Glob` handle compiled once by `msstd_path_compile_glob`
//! and matched by `msstd_path_glob_matches`. `windows` selects POSIX (false) or Windows (true)
//! separator rules; the one-shot `matches_glob` compiles and matches in Manuscript.
//! ms: domain path
use crate::{CompiledGlob, InvalidInput};
use ms_rt::ffi::{ObjRef, Object, Status, abi_handle, native};

/// `PathError.InvalidInput` is the only error case.
impl Status for InvalidInput {
    fn status(self) -> u8 {
        ms_rt::ffi::STATUS_INVALID_INPUT
    }
}

abi_handle!(CompiledGlob);

native! {
    // ms: leaf
    fn msstd_path_host_windows() -> bool {
        cfg!(windows)
    }

    // ms: leaf
    fn msstd_path_compile_glob(windows: bool, pattern: &str) -> Result<Object<CompiledGlob>, InvalidInput> {
        CompiledGlob::new(windows, pattern).map(Object)
    }

    // ms: leaf
    fn msstd_path_glob_matches(glob: ObjRef<CompiledGlob>, value: &str) -> Result<bool, InvalidInput> {
        glob.matches(value)
    }
}

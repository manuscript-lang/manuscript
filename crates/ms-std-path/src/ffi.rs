//! C ABI shim for `@std/os/path.ms` (`msstd_path_matches_glob`). The function takes `windows: u8`
//! first, selecting POSIX (0) or Windows (1) separators.
//! ms: domain path
use crate::{InvalidInput, matches_glob};
use ms_rt::ffi::{Status, native};

/// `PathError.InvalidInput` is the only error case.
impl Status for InvalidInput {
    fn status(self) -> u8 {
        ms_rt::ffi::STATUS_INVALID_INPUT
    }
}

native! {
    // ms: leaf
    fn msstd_path_matches_glob(windows: bool, value: &str, pattern: &str) -> Result<bool, InvalidInput> {
        matches_glob(windows, value, pattern)
    }
}

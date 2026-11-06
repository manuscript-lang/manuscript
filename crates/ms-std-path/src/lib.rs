//! `@std/os/path.ms` natives. Path text is Manuscript; the glob matcher stays native because
//! `@std/os/fs.ms` walks directories with the same matcher.
#![no_std]

extern crate alloc;

pub mod ffi;
pub mod glob;

use alloc::string::String;

/// `PathError.InvalidInput` is the only error case.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InvalidInput;

/// Tests `value` against `pattern`; Windows rules read backslashes as separators in both.
pub fn matches_glob(windows: bool, value: &str, pattern: &str) -> Result<bool, InvalidInput> {
    let slash = |s: &str| -> String {
        if windows {
            s.replace('\\', "/")
        } else {
            String::from(s)
        }
    };
    let glob = glob::Glob::new(&slash(pattern)).ok_or(InvalidInput)?;
    if value.contains('\0') {
        return Err(InvalidInput);
    }
    Ok(glob.matches(&slash(value)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dialect_selects_separator() {
        assert_eq!(matches_glob(false, "a/b.ms", "a/*.ms"), Ok(true));
        assert_eq!(matches_glob(true, "a\\b.ms", "a/*.ms"), Ok(true));
        assert_eq!(matches_glob(false, "a", "["), Err(InvalidInput));
        assert_eq!(matches_glob(false, "a\0", "*"), Err(InvalidInput));
    }
}

//! The glob matcher behind `@std/os/path.ms` natives (now C: `runtime/std/path.c`), kept in Rust because
//! `@std/os/fs.ms` walks directories with the same matcher.
#![no_std]

extern crate alloc;

pub mod glob;

use alloc::borrow::Cow;

/// `PathError.InvalidInput` is the only error case.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InvalidInput;

/// A glob pattern compiled once under one dialect's separator rules (Windows reads
/// backslashes as separators in both pattern and value).
pub struct CompiledGlob {
    windows: bool,
    glob: glob::Glob,
}

impl CompiledGlob {
    /// Compiles `pattern`; bad syntax, a NUL byte or an over-long pattern is `InvalidInput`.
    pub fn new(windows: bool, pattern: &str) -> Result<CompiledGlob, InvalidInput> {
        let glob = glob::Glob::new(&slash(windows, pattern)).ok_or(InvalidInput)?;
        Ok(CompiledGlob { windows, glob })
    }

    /// Whether `value` matches; a NUL byte in `value` is `InvalidInput`.
    pub fn matches(&self, value: &str) -> Result<bool, InvalidInput> {
        if value.contains('\0') {
            return Err(InvalidInput);
        }
        Ok(self.glob.matches(&slash(self.windows, value)))
    }
}

/// `text` with backslashes read as separators under Windows rules; borrowed otherwise.
pub fn slash(windows: bool, text: &str) -> Cow<'_, str> {
    if windows && text.contains('\\') {
        Cow::Owned(text.replace('\\', "/"))
    } else {
        Cow::Borrowed(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dialect_selects_separator() {
        let matches = |windows, value, pattern| {
            CompiledGlob::new(windows, pattern).and_then(|glob| glob.matches(value))
        };
        assert_eq!(matches(false, "a/b.ms", "a/*.ms"), Ok(true));
        assert_eq!(matches(true, "a\\b.ms", "a/*.ms"), Ok(true));
        assert_eq!(matches(false, "a", "["), Err(InvalidInput));
        assert_eq!(matches(false, "a\0", "*"), Err(InvalidInput));
    }
}

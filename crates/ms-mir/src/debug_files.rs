//! The path a debugger or profiler is given for a source file of a module.
//!
//! A standard-library module is known to the compiler by its logical name (`@std/data/csv.ms`),
//! which names no file. Debug info names the real file when the standard-library sources are on
//! disk (a checkout, or the directory in `MS_STDLIB_DIR`), so that `callgrind_annotate` and
//! debuggers show the lines without any setup; otherwise the logical name is kept.

use std::borrow::Cow;
use std::path::PathBuf;

/// The directory of the standard-library sources, when it exists.
fn stdlib_dir() -> Option<PathBuf> {
    let from_env = std::env::var_os("MS_STDLIB_DIR").map(PathBuf::from);
    let checkout = PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../stdlib"));
    [from_env, Some(checkout)]
        .into_iter()
        .flatten()
        .find(|d| d.join("bytes.ms").is_file())
        .and_then(|d| d.canonicalize().ok())
}

/// `path` spelled the way DWARF consumers split and rejoin it: forward slashes and no Windows
/// verbatim prefix (`\\?\C:\dir` becomes `C:/dir`). The LLVM tables rebuild a file's name from
/// its directory and base name joined by `/`, so a name with backslashes would never match.
fn portable(path: &str) -> String {
    let path = path.strip_prefix(r"\\?\").unwrap_or(path);
    path.replace('\\', "/")
}

/// `path` as debug info should name it: a logical `@std/` path becomes the file under the
/// standard-library sources when they are on disk.
pub fn debug_file_name(path: &str) -> Cow<'_, str> {
    let Some(rest) = path.strip_prefix("@std/") else {
        return Cow::Borrowed(path);
    };
    match stdlib_dir() {
        Some(dir) if dir.join(rest).is_file() => {
            Cow::Owned(portable(&dir.join(rest).to_string_lossy()))
        }
        _ => Cow::Borrowed(path),
    }
}

#[cfg(test)]
mod tests {
    use super::{debug_file_name, portable};

    #[test]
    fn a_windows_path_loses_its_verbatim_prefix_and_backslashes() {
        assert_eq!(
            portable(r"\\?\C:\repo\stdlib\bytes.ms"),
            "C:/repo/stdlib/bytes.ms"
        );
        assert_eq!(portable("/repo/stdlib/bytes.ms"), "/repo/stdlib/bytes.ms");
    }

    #[test]
    fn a_standard_library_path_names_its_source_file() {
        let name = debug_file_name("@std/bytes.ms");
        assert!(name.ends_with("stdlib/bytes.ms"), "{name}");
        assert!(std::path::Path::new(name.as_ref()).is_file());
    }

    #[test]
    fn other_paths_and_missing_modules_keep_their_name() {
        assert_eq!(debug_file_name("src/main.ms"), "src/main.ms");
        assert_eq!(
            debug_file_name("@std/nope/missing.ms"),
            "@std/nope/missing.ms"
        );
    }
}

//! C ABI shims for `@std/fs.ms` (`msrt_path_*`). Every function takes `windows: u8` first,
//! selecting POSIX (0) or Windows (1) rules; the host-rule functions pass the host's flag.
//! `PathParts` is a record of five strings (`root, directory, base, extension, name`) at its
//! natural layout; the runtime writes owned strings into it.
use crate::{InvalidInput, Parts, Rules};
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{Status, native};

/// `PathParts` is a record of five strings in field order (`root, directory, base, extension,
/// name`) at its natural layout.
type PartsRec<T> = [T; 5];

fn parts_from(r: PartsRec<&str>) -> Parts {
    let [root, directory, base, extension, name] = r.map(String::from);
    Parts {
        root,
        directory,
        base,
        extension,
        name,
    }
}

fn parts_to(p: Parts) -> PartsRec<String> {
    [p.root, p.directory, p.base, p.extension, p.name]
}

/// `PathError.InvalidInput` is the only error case.
impl Status for InvalidInput {
    fn status(self) -> u8 {
        ms_std_core::STATUS_INVALID_INPUT
    }
}

fn rules(windows: bool) -> Rules {
    Rules { windows }
}

native! {
    fn msrt_path_basename(windows: bool, path: &str) -> String {
        rules(windows).basename(path)
    }

    fn msrt_path_basename_without(windows: bool, path: &str, suffix: &str) -> String {
        rules(windows).basename_without(path, suffix)
    }

    fn msrt_path_dirname(windows: bool, path: &str) -> String {
        rules(windows).dirname(path)
    }

    fn msrt_path_extension(windows: bool, path: &str) -> String {
        rules(windows).extension(path)
    }

    fn msrt_path_is_absolute(windows: bool, path: &str) -> bool {
        rules(windows).is_absolute(path)
    }

    fn msrt_path_join(windows: bool, parts: Vec<&str>) -> String {
        rules(windows).join(&parts)
    }

    fn msrt_path_normalize(windows: bool, path: &str) -> String {
        rules(windows).normalize(path)
    }

    fn msrt_path_relative(windows: bool, base: &str, target: &str) -> Result<String, InvalidInput> {
        rules(windows).relative(base, target)
    }

    fn msrt_path_resolve(windows: bool, base: &str, parts: Vec<&str>) -> Result<String, InvalidInput> {
        rules(windows).resolve(base, &parts)
    }

    fn msrt_path_parse(windows: bool, path: &str) -> out PartsRec<String> {
        parts_to(rules(windows).parse(path))
    }

    fn msrt_path_format(windows: bool, parts: PartsRec<&str>) -> String {
        rules(windows).format(&parts_from(parts))
    }

    fn msrt_path_separator(windows: bool) -> &'static str {
        rules(windows).separator()
    }

    fn msrt_path_delimiter(windows: bool) -> &'static str {
        rules(windows).delimiter()
    }

    fn msrt_path_to_namespaced_path(windows: bool, path: &str) -> String {
        rules(windows).to_namespaced_path(path)
    }

    fn msrt_path_matches_glob(windows: bool, value: &str, pattern: &str) -> Result<bool, InvalidInput> {
        rules(windows).matches_glob(value, pattern)
    }
}

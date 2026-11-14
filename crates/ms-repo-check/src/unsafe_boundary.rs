//! Only listed Rust locations may use `unsafe` or lift the workspace
//! `unsafe_code` lint. Extending the list needs a reason in the same change.

use std::fs;

const ALLOWED: &[&str] = &[
    "crates/ms-rt/",     // raw memory behind the C ABI compiled code links against
    "crates/ms-std-",    // C ABI shims (ffi.rs) of the standard-library native crates
    "crates/ms-rt-abi/", // C-layout types and extern fn pointer types
    "crates/ms-native/src/entry.rs", // glibc process entry (`_start`) in global_asm
    "crates/ms-native/tests/std_natives.rs", // drives the exported natives through the C ABI with raw runtime values
    "crates/ms-cli/src/process.rs",          // libc signal/kill; std has no signal API
    "crates/ms-syntax/src/symbol.rs", // the name table hands out text that lives until its interner is dropped or released
    "crates/ms-lsp/src/server.rs", // frees the retired name table when the server starts over (Session::release)
    "crates/ms-cli/tests/terminal.rs", // libc pseudo-terminal to drive RawTerminal end to end; std has no pty API
];

// These standalone measurement binaries forward System's unsafe GlobalAlloc API and count
// requested bytes with atomics. They never inspect allocated contents or enter production builds.
const ALLOCATION_BENCHMARKS: &[&str] = &[
    "bench/perf/binding-flags/main.rs",
    "bench/perf/binding-flags/storage.rs",
];

fn checked(path: &str) -> bool {
    path.ends_with(".rs") && (path.starts_with("crates/") || path.starts_with("bench/"))
}

fn allowed(path: &str) -> bool {
    ALLOWED.iter().any(|a| path.starts_with(a)) || ALLOCATION_BENCHMARKS.contains(&path)
}

pub fn check(files: &[String]) -> Vec<String> {
    files
        .iter()
        .filter(|p| checked(p))
        .filter(|p| !allowed(p))
        .filter_map(|path| {
            let source = fs::read_to_string(path).ok()?;
            let found = unsafe_use(&source)?;
            Some(format!(
                "{path} uses unsafe ({found:?}) outside the allowed Rust modules; see ALLOWED in crates/ms-repo-check/src/unsafe_boundary.rs"
            ))
        })
        .collect()
}

/// The first use of the keyword in code, or a lint attribute lifting the ban.
pub(crate) fn unsafe_use(source: &str) -> Option<String> {
    // Assembled so this file does not match itself.
    for lint in ["allow", "forbid"] {
        let needle = format!("{lint}({}_code)", "uns".to_string() + "afe");
        if source.contains(&needle) {
            return Some(needle);
        }
    }
    let word = |b: u8| b.is_ascii_alphanumeric() || b == b'_';
    let bytes = source.as_bytes();
    let mut from = 0;
    while let Some(at) = source[from..].find("unsafe") {
        let start = from + at;
        let end = start + "unsafe".len();
        from = end;
        if start > 0 && word(bytes[start - 1]) {
            continue;
        }
        let rest = source[end..].trim_start();
        let opens = rest.starts_with('{')
            || ["fn", "impl", "trait", "extern"].iter().any(|k| {
                rest.strip_prefix(k)
                    .is_some_and(|after| !after.bytes().next().is_some_and(word))
            });
        if opens {
            return Some(source[start..end + (source[end..].len() - rest.len()) + 1].to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::{allowed, checked, unsafe_use};

    #[test]
    fn benchmark_allocators_have_exact_exceptions_and_other_benchmarks_are_checked() {
        assert!(checked("bench/perf/binding-flags/main.rs"));
        assert!(allowed("bench/perf/binding-flags/main.rs"));
        assert!(allowed("bench/perf/binding-flags/storage.rs"));
        assert!(checked("bench/perf/other/main.rs"));
        assert!(!allowed("bench/perf/other/main.rs"));
        assert!(!allowed("bench/perf/binding-flags/other.rs"));
        assert!(!allowed("bench/perf/binding-flags/main.rs.extra.rs"));
        assert!(!checked("bench/perf/binding-flags/README.md"));
    }

    #[test]
    fn finds_unsafe_code_not_prose() {
        // Spelled apart so this file does not match itself.
        let kw = "uns".to_string() + "afe";
        assert!(unsafe_use(&format!("fn f() {{ {kw} {{ g() }} }}")).is_some());
        assert!(unsafe_use(&format!("{kw} extern \"C\" {{}}")).is_some());
        assert!(unsafe_use(&format!("// this is {kw} to call")).is_none());
        assert!(unsafe_use(&format!("let not_{kw} = 1;")).is_none());
    }
}

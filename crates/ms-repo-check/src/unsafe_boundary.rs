//! Only listed Rust locations may use `unsafe` or lift the workspace
//! `unsafe_code` lint. Extending the list needs a reason in the same change.

use std::fs;

const ALLOWED: &[&str] = &[
    "crates/ms-rt/",     // raw memory behind the C ABI compiled code links against
    "crates/ms-std-",    // C ABI shims (ffi.rs) of the standard-library native crates
    "crates/ms-rt-abi/", // C-layout types and extern fn pointer types
    "crates/ms-cli/src/process.rs", // libc signal/kill; std has no signal API
    "crates/ms-cli/tests/terminal.rs", // libc pseudo-terminal to drive RawTerminal end to end; std has no pty API
];

pub fn check(files: &[String]) -> Vec<String> {
    files
        .iter()
        .filter(|p| p.starts_with("crates/") && p.ends_with(".rs"))
        .filter(|p| !ALLOWED.iter().any(|a| p.starts_with(a)))
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
    use super::unsafe_use;

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

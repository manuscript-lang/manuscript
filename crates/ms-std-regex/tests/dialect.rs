//! Pins the `regex` crate dialect that `@std/string.ms` exposes (no Go/RE2 translation layer).
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_regex::compile;

fn ok(pattern: &str) -> bool {
    compile(pattern).is_ok()
}

fn found(pattern: &str, text: &str) -> Vec<String> {
    compile(pattern).unwrap().find_all(text, None).unwrap()
}

#[test]
fn accepted() {
    for p in [
        "a**",
        "a*+",
        "a+*",
        "a{2}{3}",
        "a{1001}",
        "a{0,1001}",
        "(?P<n>a)(?P<m>b)",
        "(?u)a",
        "(?R)",
        "[[:foo:]]",
        "\\<",
        "\\>",
        "(?x)a b",
        "[a&&b]",
        "[a--b]",
        "[\\w-]",
        "\\B",
        "\\u0041",
        "\\U00000041",
        "\\p{Script=Greek}",
        "\\p{Alphabetic}",
        "(a{100}){100}",
        "[[:alpha:]]",
    ] {
        assert!(ok(p), "{p:?} should compile");
    }
}

#[test]
fn rejected() {
    for p in [
        "(?P<n>a)(?P<n>b)",
        "(?i-i)a",
        "\\Qa.b\\E",
        "\\0",
        "\\101",
        "a{",
        "a{,2}",
        "a{x}",
        "a{1,x}",
        "{",
        ".{{",
        "(a",
        "a)",
        "*a",
        "[a",
        "a\\",
    ] {
        assert!(!ok(p), "{p:?} should not compile");
    }
}

#[test]
fn classes_are_unicode_aware() {
    assert_eq!(found("\\w+", "héllo wörld"), ["héllo", "wörld"]);
    assert_eq!(found("\\d", "1٣"), ["1", "٣"]);
    assert_eq!(found("\\bé", "é"), ["é"]);
}

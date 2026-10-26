//! `MSL101` (unread bindings) for the borrow forms of `if var`.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::lint::lint_program;
use std::sync::Arc;

fn codes(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("lint.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    lint_program(&program)
        .iter()
        .map(|f| f.code.to_string())
        .collect()
}

#[test]
fn if_var_borrow_that_is_only_written_is_not_unread() {
    let source = "export def main() -> Int:
    var m = Map[String, Int]()
    m.add(\"a\", 1)
    if var n = m.get(\"a\"):
        n += 1
    return m.get(\"a\").get(0)
";
    assert!(!codes(source).contains(&"MSL101".to_string()));
}

#[test]
fn if_let_binding_that_is_never_read_is_still_reported() {
    let source = "export def main() -> Int:
    let m = Map[String, Int]()
    if let n = m.get(\"a\"):
        return 1
    return 0
";
    assert!(codes(source).contains(&"MSL101".to_string()));
}

#[test]
fn optional_get_without_default_is_reported() {
    let source = "export def main() -> Int:
    let m = Map[String, Int]()
    let a = m.get(\"a\").get(0)
    return m.get(\"a\").get() + a
";
    let found = codes(source);
    assert_eq!(
        found.iter().filter(|c| *c == "MSL110").count(),
        1,
        "{found:?}"
    );
}

fn recursive(source: &str) -> usize {
    codes(source).iter().filter(|c| *c == "MSL112").count()
}

#[test]
fn recursion_without_a_base_case_is_reported() {
    assert_eq!(
        recursive(
            "def forever(n: Int) -> Int:
    return forever(n - 1)

def both(n: Int) -> Int:
    if n > 0:
        return both(n - 1)
    else:
        return both(n + 1)

export def main() -> Int:
    return 0
"
        ),
        2
    );
}

#[test]
fn recursion_with_a_base_case_is_clean() {
    assert_eq!(
        recursive(
            "def fact(n: Int) -> Int:
    if n <= 1:
        return 1
    return n * fact(n - 1)

def sum(n: Int) -> Int:
    return 0 if n <= 0 else n + sum(n - 1)

def count(n: Int) -> Int:
    for i in 0..n:
        return i
    return count(n - 1)

def walk(n: Int) -> Int:
    if n > 0 and walk(n - 1) > 0:
        return 1
    return 0

export def main() -> Int:
    return fact(3) + sum(2) + count(1) + walk(1)
"
        ),
        0
    );
}

//! Diagnostics name the use site, the expected and found types, and the fix.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn first_message(source: &str) -> String {
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    program.diagnostics[0].message.clone()
}

#[test]
fn mismatch_names_its_use_site() {
    let cases = [
        (
            "fn f(a: Int) Int:\n    return a\nexport fn main() Int:\n    return f(\"s\")\n",
            "expected Int, found String (in argument 'a' of f)",
        ),
        (
            "export fn main() Int:\n    let x: String = 1\n    return 0\n",
            "expected String, found Int (in the initializer of 'x'); Int does not convert to String implicitly; interpolate it",
        ),
        (
            "fn f() Result[Int, Error]:\n    return 1\nexport fn main() Int:\n    return 0\n",
            "expected Result[Int, Error], found Int (in the return value); wrap the value in ok(",
        ),
        (
            "export fn main() Int:\n    let l = [1, \"a\"]\n    return 0\n",
            "expected Int, found String (in entry 2 of the literal",
        ),
    ];
    for (source, want) in cases {
        let got = first_message(source);
        assert!(
            got.starts_with(want),
            "{got}\n  does not start with\n{want}"
        );
    }
}

#[test]
fn match_and_member_errors_list_the_fix() {
    let got = first_message(
        "type S:\n    case A\n    case B(x: Int)\nfn f(s: S) Int:\n    match s:\n        A:\n            return 1\nexport fn main() Int:\n    return 0\n",
    );
    assert!(got.ends_with("add the arms 'B(x):'"), "{got}");
    let got = first_message(
        "export fn main() Int:\n    let m = Map[String, Int]()\n    m.set(1, 2)\n    return 0\n",
    );
    assert!(got.contains("available: add,"), "{got}");
}

#[test]
fn impl_cannot_mutate_what_the_interface_does_not() {
    let source = "interface Sink:\n    fn put(x: Int) Unit\ntype Buf:\n    n: Int\nimpl Sink for Buf:\n    var fn put(x: Int) Unit:\n        self.n = x\nexport fn main() Int:\n    return 0\n";
    let got = first_message(source);
    assert!(
        got.starts_with("implementation of put is declared var fn but Sink declares it fn"),
        "{got}"
    );
}

#[test]
fn comparing_with_none_points_to_is_none() {
    let got = first_message(
        "export fn main() Int:\n    let r: Optional[Int] = some(1)\n    if r == none:\n        return 1\n    return 0\n",
    );
    assert!(got.starts_with("none has no type of its own here"), "{got}");
}

#[test]
fn map_index_points_to_get_and_add() {
    let all = |source: &str| {
        let file: Arc<str> = Arc::from("t.ms");
        let module = ms_syntax::parser::parse(&file, source).expect("parses");
        ms_check::check(
            vec![ms_check::load_module(&module)],
            ImportMap::default(),
            CheckOptions::default(),
        )
        .diagnostics
        .into_iter()
        .map(|d| d.message)
        .collect::<Vec<_>>()
    };
    let write = all(
        "export fn main() Int:\n    var m = Map[String, Int]()\n    m[\"a\"] = 1\n    return 0\n",
    );
    assert_eq!(write.len(), 1, "{write:?}");
    assert!(write[0].contains("m.add(key, value)"), "{write:?}");
    let read = all("export fn main() Int:\n    let m = Map[String, Int]()\n    return m[\"a\"]\n");
    assert_eq!(read.len(), 1, "{read:?}");
    assert!(read[0].contains("m.get(key)"), "{read:?}");
}

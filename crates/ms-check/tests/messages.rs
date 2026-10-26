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
            "def f(a: Int) -> Int:\n    return a\nexport def main() -> Int:\n    return f(\"s\")\n",
            "expected Int, found String (in argument 'a' of f)",
        ),
        (
            "export def main() -> Int:\n    let x: String = 1\n    return 0\n",
            "expected String, found Int (in the initializer of 'x'); Int does not convert to String implicitly; interpolate it",
        ),
        (
            "def f() -> Result[Int, Error]:\n    return 1\nexport def main() -> Int:\n    return 0\n",
            "expected Result[Int, Error], found Int (in the return value); wrap the value in ok(",
        ),
        (
            "export def main() -> Int:\n    let l = [1, \"a\"]\n    return 0\n",
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
        "type S:\n    case A\n    case B(x: Int)\ndef f(s: S) -> Int:\n    match s:\n        case A:\n            return 1\nexport def main() -> Int:\n    return 0\n",
    );
    assert!(got.ends_with("add the arms 'case B(x):'"), "{got}");
    let got = first_message(
        "export def main() -> Int:\n    let m = Map[String, Int]()\n    m.set(1, 2)\n    return 0\n",
    );
    assert!(got.contains("available: add,"), "{got}");
}

#[test]
fn impl_cannot_mutate_what_the_interface_does_not() {
    let source = "interface Sink:\n    def put(x: Int) -> Unit\ntype Buf:\n    n: Int\nimpl Sink for Buf:\n    var def put(x: Int) -> Unit:\n        self.n = x\nexport def main() -> Int:\n    return 0\n";
    let got = first_message(source);
    assert!(
        got.starts_with("implementation of put is declared var def but Sink declares it def"),
        "{got}"
    );
}

#[test]
fn comparing_with_none_points_to_is_none() {
    let got = first_message(
        "export def main() -> Int:\n    let r: Optional[Int] = some(1)\n    if r == none:\n        return 1\n    return 0\n",
    );
    assert!(got.starts_with("none has no type of its own here"), "{got}");
}

#[test]
fn map_and_bytes_index_check_and_string_index_explains() {
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
    let ok = all(
        "export def main() -> Int:\n    var m = Map[String, Int]()\n    m[\"a\"] = 1\n    let b = \"x\".to_bytes()\n    return m[\"a\"] + b[0]\n",
    );
    assert!(ok.is_empty(), "{ok:?}");
    let text =
        all("export def main() -> Int:\n    let s = \"abc\"\n    let c = s[0]\n    return 0\n");
    assert_eq!(text.len(), 1, "{text:?}");
    assert!(text[0].contains("s.get(index)"), "{text:?}");
}

#[test]
fn foreign_idioms_name_the_replacement() {
    let cases = [
        ("let a = [1].first().unwrap()", "x.get(default)"),
        ("let a = [1].first().unwrap_or(0)", "x.get(default)"),
        ("let a = [1].includes(1)", "did you mean 'contains'?"),
        (
            "let a = [1].reduce(0, lambda (a: Int, b: Int) -> Int: a + b)",
            "did you mean 'fold'?",
        ),
        ("let a = \"x\".toUpperCase()", "did you mean 'upper'?"),
        (
            "let a = \"x\".startsWith(\"x\")",
            "did you mean 'starts_with'?",
        ),
        ("let a = Some(1)", "write the lowercase some(value)"),
        ("let a = Err(1)", "write error(cause)"),
        ("let a = len([1])", "xs.length()"),
        ("let a = Object.keys(1)", "m.keys()"),
        ("let a = Int(\"1\")", "text.parse_int()"),
        ("let a = String(1)", "interpolation"),
        ("let a = 1.0 * 2", "value.to_float()"),
    ];
    for (line, want) in cases {
        let got = first_message(&format!(
            "export def main() -> Int:\n    {line}\n    return 0\n"
        ));
        assert!(
            got.contains(want),
            "{line}: {got}\n  does not contain\n{want}"
        );
    }
    let got = first_message(
        "def f() -> Result[Int, Error]:\n    return ok(1)\nexport def main() -> Int:\n    let x = f().unwrap()\n    return 0\n",
    );
    assert!(got.contains("try x"), "{got}");
}

#[test]
fn var_parameter_def_is_not_a_function_value() {
    let source = "type Ch:\n    buf: List[String]\n\ndef child(var c: Ch) -> Int:\n    c.buf.append(\"a\")\n    return 1\n\ndef run(entry: Callable[[Ch], Int]) -> Int:\n    var c = Ch(buf: [])\n    return entry(c)\n\nexport def main() -> Int:\n    return run(child) - 1\n";
    assert!(
        first_message(source)
            .starts_with("child has a var parameter, so it cannot be a function value")
    );
    let call = "def child(var c: List[String]) -> Int:\n    c.append(\"a\")\n    return 1\n\nexport def main() -> Int:\n    var c = [\"x\"]\n    return child(var c) - 1\n";
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, call).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    assert!(
        program.diagnostics.is_empty(),
        "{:?}",
        program
            .diagnostics
            .iter()
            .map(|d| &d.message)
            .collect::<Vec<_>>()
    );
}

fn messages(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    program
        .diagnostics
        .iter()
        .map(|d| d.message.clone())
        .collect()
}

#[test]
fn none_where_a_plain_value_is_expected_is_one_mismatch() {
    let got = messages("export def main() -> Int:\n    var x: Int = none\n    return x\n");
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].starts_with("expected Int, found none"), "{got:?}");
    assert!(!got[0].contains("<invalid>"), "{got:?}");
}

#[test]
fn none_under_an_unknown_type_adds_no_inference_error() {
    let got = messages("export def main() -> Int:\n    let y: Option[Int] = none\n    return 0\n");
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(got[0].contains("unknown type Option"), "{got:?}");
}

#[test]
fn a_failed_bound_in_a_signature_is_reported_once() {
    let got = messages("def f() -> Result[Int, String]: ok(1)\nexport def main() -> Int: 0\n");
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].starts_with("String does not satisfy Error"),
        "{got:?}"
    );
}

#[test]
fn none_into_an_interface_still_asks_for_a_type_argument() {
    let got = messages("export def main() -> Int:\n    let r: Equal = none\n    return 0\n");
    assert_eq!(got.len(), 1, "{got:?}");
    assert!(
        got[0].starts_with("cannot infer constructor type argument T"),
        "{got:?}"
    );
}

#[test]
fn borrowed_spellings_name_the_manuscript_one() {
    let cases = [
        (
            "export def main() -> Int:\n    let a = true\n    return 0\n",
            "booleans are capitalized: True and False",
        ),
        (
            "export def main() -> Int:\n    let a: Integer = 1\n    return 0\n",
            "did you mean 'Int'?",
        ),
        (
            "export def main() -> Int:\n    let a: double = 1.0\n    return 0\n",
            "did you mean 'Float'?",
        ),
    ];
    for (source, want) in cases {
        let got = first_message(source);
        assert!(got.ends_with(want), "{got}");
    }
}

#[test]
fn invalid_callback_types_do_not_conflict_over_parameter_names() {
    for signature in [
        "def broken(value: Missing) -> Int: 1",
        "def broken(amount: Int) -> Missing: 1",
        "def broken(handler: Callable[[Missing], Int]) -> Int: 1",
    ] {
        let source = format!(
            "{signature}\ndef apply[T, U](callback: Callable[[T], U]) -> Unit: return\ndef exercise() -> Unit:\n    apply(broken)\n"
        );
        let file: Arc<str> = Arc::from("recovery.ms");
        let module = ms_syntax::parser::parse(&file, &source).expect("parses");
        let checked = ms_check::check(
            vec![ms_check::load_module(&module)],
            Default::default(),
            Default::default(),
        );
        let messages: Vec<_> = checked
            .diagnostics
            .iter()
            .map(|d| d.message.as_str())
            .collect();
        assert_eq!(messages.len(), 1, "{signature}: {messages:?}");
        assert!(
            messages[0].starts_with("unknown type Missing;"),
            "{messages:?}"
        );
    }
}

#[test]
fn invalid_callback_slots_preserve_known_type_conflicts() {
    let source = "def broken(first: Missing, second: Int) -> Int: 1\ndef apply[T](callback: Callable[[T, String], Int]) -> Unit: return\ndef exercise() -> Unit:\n    apply(broken)\n";
    let file: Arc<str> = Arc::from("conflict.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    let checked = ms_check::check(
        vec![ms_check::load_module(&module)],
        Default::default(),
        Default::default(),
    );
    let messages: Vec<_> = checked
        .diagnostics
        .iter()
        .map(|d| d.message.as_str())
        .collect();
    assert_eq!(
        messages
            .iter()
            .filter(|m| m.starts_with("unknown type Missing;"))
            .count(),
        1,
        "{messages:?}"
    );
    assert_eq!(
        messages
            .iter()
            .filter(|m| m.starts_with("conflicting generic inference;"))
            .count(),
        1,
        "{messages:?}"
    );
}

fn callable_messages(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("callable.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .into_iter()
    .map(|d| d.message)
    .collect()
}

#[test]
fn callable_type_mismatches_do_not_suggest_parameter_renames() {
    let cases = [
        (
            "def source(PARAM: Int) -> Int: PARAM",
            "Callable[[Optional[Int]], Int]",
            "Callable[[Int], Int]",
        ),
        (
            "def source(PARAM: Int) -> Int: PARAM",
            "Callable[[String], Int]",
            "Callable[[Int], Int]",
        ),
        (
            "def source(PARAM: Int) -> String: \"text\"",
            "Callable[[Int], Int]",
            "Callable[[Int], String]",
        ),
    ];
    for (declaration, expected, actual) in cases {
        for name in ["value", "_0"] {
            let declaration = declaration.replace("PARAM", name);
            let source = format!(
                "{declaration}\ndef exercise() -> Unit:\n    let callback: {expected} = source\n"
            );
            assert_eq!(
                callable_messages(&source),
                [format!(
                    "expected {expected}, found {actual} (in the initializer of 'callback')"
                )],
                "{source}"
            );
        }
    }
}

#[test]
fn map_callback_type_mismatch_retains_the_real_type_error() {
    for name in ["value", "_0"] {
        let source = format!(
            "def transform({name}: Int, key: String) -> Int: {name}\ndef wrong(values: Map[String, Int]) -> Map[String, Int]: values.map(transform)\n"
        );
        assert_eq!(
            callable_messages(&source),
            [
                "expected Callable[[String, Int], Int], found Callable[[Int, String], Int] (in argument 'transform' of values.map)"
            ],
            "{source}"
        );
    }
}

#[test]
fn generic_callback_evidence_still_reports_a_real_conflict() {
    let source = "def source(value: String) -> Int: value.length()\ndef apply[T](callback: Callable[[T], Int], value: T) -> Int: callback(value)\ndef exercise() -> Int: apply(source, 3)\n";
    assert_eq!(
        callable_messages(source),
        [
            "conflicting generic inference; arguments imply different types for one type parameter, so make them the same type or give type arguments explicitly, e.g. f[Int](...)",
            "expected String, found Int (in argument 'value' of apply); Int does not convert to String implicitly; interpolate it into text, e.g. f\"{value}\""
        ]
    );
}

#[test]
fn fixed_callback_mismatches_keep_their_primary_type_diagnostic() {
    let cases = [
        (
            "def source(PARAM: Int) -> String: \"text\"",
            "Callable[[T], Int]",
            "expected Callable[[<invalid>], Int], found Callable[[Int], String] (in argument 'callback' of apply)",
        ),
        (
            "def source(PARAM: Int) -> Int: PARAM",
            "Callable[[String], T]",
            "expected Callable[[String], <invalid>], found Callable[[Int], Int] (in argument 'callback' of apply)",
        ),
    ];
    for (declaration, expected, message) in cases {
        for name in ["value", "_0"] {
            let declaration = declaration.replace("PARAM", name);
            let source = format!(
                "{declaration}\ndef apply[T](callback: {expected}) -> Unit: return\ndef exercise() -> Unit: apply(source)\n"
            );
            assert_eq!(
                callable_messages(&source),
                [
                    "cannot infer type argument T for apply; write apply[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter",
                    message
                ],
                "{source}"
            );
        }
    }
}

#[test]
fn generic_callback_arity_mismatch_keeps_its_hint() {
    let source = "def source(first: Int, second: Int) -> Int: first + second\ndef apply[T](callback: Callable[[T], Int], value: T) -> Int: callback(value)\ndef exercise() -> Int: apply(source, 3)\n";
    assert_eq!(
        callable_messages(source),
        [
            "callback mismatch: the function takes 2 parameters but this position expects 1; pass a function with 1 parameter, or wrap it in a lambda that supplies the rest",
            "expected Callable[[Int], Int], found Callable[[Int, Int], Int] (in argument 'callback' of apply)"
        ]
    );
}

#[test]
fn constant_faults_are_compile_errors() {
    let cases = [
        ("1 / 0", "division by zero always faults"),
        ("7 % (2 - 2)", "division by zero always faults"),
        ("9223372036854775807 + 1", "overflows Int and always faults"),
        ("4611686018427387904 * 2", "overflows Int and always faults"),
        (
            "-9223372036854775807 - 2",
            "overflows Int and always faults",
        ),
        (
            "[1, 2][2]",
            "index 2 is outside this list literal of 2 element(s)",
        ),
        (
            "[1, 2][-3]",
            "index -3 is outside this list literal of 2 element(s)",
        ),
    ];
    for (expr, want) in cases {
        let source = format!("export def main() -> Int:\n    return {expr}\n");
        let got = first_message(&source);
        assert!(got.contains(want), "{expr}: {got}");
    }
}

#[test]
fn in_range_constants_and_runtime_operands_are_accepted() {
    for expr in [
        "9223372036854775806 + 1",
        "-9223372036854775808",
        "[1, 2][-2]",
        "[1, 2][1]",
        "8 / 2 % 3",
    ] {
        let source = format!("export def main() -> Int:\n    return {expr}\n");
        let file: Arc<str> = Arc::from("t.ms");
        let module = ms_syntax::parser::parse(&file, &source).expect("parses");
        let program = ms_check::check(
            vec![ms_check::load_module(&module)],
            ImportMap::default(),
            CheckOptions::default(),
        );
        assert!(
            program.diagnostics.is_empty(),
            "{expr}: {:?}",
            program.diagnostics
        );
    }
}

const LOCK_HEADER: &str = "from \"@std/shared.ms\" import Shared, share
from \"@std/sync.ms\" import lock
";

fn check_messages(source: &str) -> Vec<String> {
    let file: Arc<str> = Arc::from("t.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
    .diagnostics
    .iter()
    .map(|d| d.message.clone())
    .collect()
}

#[test]
fn locking_a_shared_inside_its_own_guard_is_rejected() {
    let source = format!(
        "{LOCK_HEADER}export def main() -> Int:
    let box = share(1)
    with var outer = lock(box):
        with var inner = lock(box):
            inner.value += 1
        outer.value += 1
    return 0
"
    );
    let found = check_messages(&source);
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(found[0].contains("box is already locked"), "{found:?}");
}

#[test]
fn sequential_and_distinct_locks_are_accepted() {
    let source = format!(
        "{LOCK_HEADER}export def main() -> Int:
    let a = share(1)
    let b = share(2)
    with var one = lock(a):
        with var two = lock(b):
            two.value += one.value
    with var again = lock(a):
        again.value += 1
    return 0
"
    );
    assert_eq!(check_messages(&source), Vec::<String>::new());
}

#[test]
fn key_holding_shared_state_is_not_hashable() {
    let got = first_message(
        "from \"@std/shared.ms\" import Shared\ntype K:\n    cell: Shared[Int]\nimpl Equal for K:\n    def equals(other: K) -> Bool: return True\nimpl Hashable for K:\n    def hash() -> Int: return 1\nexport def main() -> Int:\n    let s = Set[K]()\n    return 0\n",
    );
    assert!(
        got.starts_with("K does not satisfy Hashable; it holds a Shared handle"),
        "{got}"
    );
}

#[test]
fn nested_bindings_cannot_shadow_enclosing_locals() {
    let cases = [
        "export def main() -> Int:\n    let x = 1\n    if x > 0:\n        let x = 2\n        return x\n    return 0\n",
        "export def main() -> Int:\n    let x = 1\n    let f = lambda x: return x + 1\n    return f(x)\n",
        "export def main() -> Int:\n    let x = 1\n    for x in [1, 2]:\n        return x\n    return 0\n",
        "def f(x: Int) -> Int:\n    if x > 0:\n        let x = 2\n        return x\n    return 0\nexport def main() -> Int:\n    return f(1)\n",
    ];
    for source in cases {
        let found = check_messages(source);
        assert!(
            found.iter().any(|m| m.contains("shadows an outer binding")),
            "{source}: {found:?}"
        );
    }
}

#[test]
fn sibling_scopes_and_underscore_names_may_reuse_names() {
    let source = "export def main() -> Int:
    var total = 0
    for i in [1, 2]:
        total += i
    for i in [3, 4]:
        total += i
    let _x = 1
    if total > 0:
        let _x = 2
        total += _x
    return total
";
    assert_eq!(check_messages(source), Vec::<String>::new());
}

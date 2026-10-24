//! `drop_redundant_labels`: the cases of Go's `TestDropRedundantLabels`.

use ms_check::{CheckOptions, ImportMap, Program};
use ms_tooling::labels::drop_redundant_labels;
use std::sync::Arc;

fn check(source: &str) -> Program {
    let file: Arc<str> = Arc::from("labels.ms");
    let module = ms_syntax::parser::parse(&file, source).expect("parses");
    ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    )
}

const DECLARATIONS: &str = "type Point:
    x: Int
    y: Int

def bump(map: Int, key: Int, step: Int = 1) -> Int: map + key + step

type Counter:
    total: Int

interface Adder:
    def add(amount: Int, extra: Int) -> Int

impl Adder for Counter:
    def add(amount: Int, extra: Int) -> Int: self.total + amount + extra

def use(map: Int, key: Int, y: Int, x: Int, counter: Counter) -> Int:
";

#[test]
fn drops_only_labels_that_bind_the_same_parameter() {
    let cases = [
        (
            "all in order",
            "return bump(map: map, key: key)",
            "return bump(map, key)",
        ),
        (
            "label order differs",
            "return bump(key: key, map: map)",
            "return bump(key: key, map)",
        ),
        (
            "defaulted parameter is not skipped",
            "return bump(key: key, map: 1)",
            "return bump(key: key, map: 1)",
        ),
        (
            "labeled middle",
            "return bump(map: map, step: 3, key: key)",
            "return bump(map, step: 3, key)",
        ),
        (
            "different name stays labeled",
            "return bump(map: key, key: map)",
            "return bump(map: key, key: map)",
        ),
        (
            "expression stays labeled",
            "return bump(map: map + 1, key: key)",
            "return bump(map: map + 1, key)",
        ),
        (
            "record fields",
            "return Point(x: x, y: y).x",
            "return Point(x, y).x",
        ),
        (
            "record fields reordered",
            "return Point(y: y, x: x).x",
            "return Point(y: y, x).x",
        ),
        (
            "method arguments",
            "return counter.add(amount: key, extra: y)",
            "return counter.add(amount: key, extra: y)",
        ),
        (
            "method arguments by name",
            "let amount = key\n    let extra = y\n    return counter.add(amount: amount, extra: extra)",
            "let amount = key\n    let extra = y\n    return counter.add(amount, extra)",
        ),
    ];
    for (name, body, want) in cases {
        let source = format!("{DECLARATIONS}    {body}\n");
        let program = check(&source);
        assert!(
            program.diagnostics.is_empty(),
            "{name}: {:?}",
            program.diagnostics
        );
        let (got, _) = drop_redundant_labels(&program, &source);
        assert_eq!(got, format!("{DECLARATIONS}    {want}\n"), "{name}");
        let again = check(&got);
        assert!(
            again.diagnostics.is_empty(),
            "{name}: dropped labels changed validity"
        );
        let (second, n) = drop_redundant_labels(&again, &got);
        assert!(n == 0 && second == got, "{name}: not idempotent");
    }
}

#[test]
fn skips_broken_source() {
    let source = "def f(a: Int) -> Int:\n    return g(a: a)\n";
    let program = check(source);
    assert_eq!(
        drop_redundant_labels(&program, source),
        (source.to_string(), 0)
    );
}

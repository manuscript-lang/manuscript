//! `MSL111`: a `while True` loop in a tasks module that never waits.

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

const HEAD: &str =
    "import TaskGroup from \"@std/tasks.ms\"\nimport {nanoseconds, sleep} from \"@std/time.ms\"\n";

#[test]
fn spinning_loop_is_reported() {
    let source = format!(
        "{HEAD}fn spin() Int:\n    var items = List[Int]()\n    var n = 0\n    while true:\n        n += 1\n        items.append(n)\n    return n\nexport fn main() Int:\n    return 0\n"
    );
    assert!(codes(&source).contains(&"MSL111".to_string()));
}

#[test]
fn loops_that_wait_or_exit_are_not_reported() {
    let waits = format!(
        "{HEAD}fn tick() Int:\n    var n = 0\n    while true:\n        n += 1\n        sleep(nanoseconds(1000))\n    return n\nexport fn main() Int:\n    return 0\n"
    );
    let exits = format!(
        "{HEAD}fn count() Int:\n    var n = 0\n    while true:\n        n += 1\n        if n > 3:\n            return n\n    return n\nexport fn main() Int:\n    return 0\n"
    );
    assert!(!codes(&waits).contains(&"MSL111".to_string()));
    assert!(!codes(&exits).contains(&"MSL111".to_string()));
}

#[test]
fn modules_without_tasks_are_not_reported() {
    let source = "fn spin() Int:\n    var n = 0\n    while true:\n        n += 1\n    return n\nexport fn main() Int:\n    return 0\n";
    assert!(!codes(source).contains(&"MSL111".to_string()));
}

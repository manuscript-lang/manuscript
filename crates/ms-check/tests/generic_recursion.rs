//! Generic recursion checks must follow recursive paths without expanding finite call DAGs.

use ms_check::{CheckOptions, ImportMap};
use std::sync::Arc;

fn diagnostics(sources: &[(&str, &str)]) -> Vec<(String, u32, u32, String)> {
    let modules = sources
        .iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(*file);
            let module = ms_syntax::parser::parse(&file, source).expect("parses");
            ms_check::load_module(&module)
        })
        .collect();
    ms_check::check(modules, ImportMap::default(), CheckOptions::default())
        .diagnostics
        .into_iter()
        .map(|d| (d.file.to_string(), d.pos.line, d.pos.column, d.message))
        .collect()
}

fn graph(depth: usize, recursive: bool) -> String {
    let mut source = String::new();
    for i in 0..depth {
        source.push_str(&format!(
            "def f{i}[T](n: Int) -> Int:\n    return f{}[T](n) + f{}[T](n)\n\n",
            i + 1,
            i + 1
        ));
    }
    source.push_str(&format!("def f{depth}[T](n: Int) -> Int:\n"));
    if recursive {
        source.push_str(&format!("    return f{depth}[T](n)\n"));
    } else {
        source.push_str("    return n\n");
    }
    source
}

#[test]
fn shared_generic_dag_does_not_expand_every_call_path() {
    // Forty levels have only 41 declarations but over a trillion call paths. Checking a
    // finite declaration graph must not instantiate or execute each of those paths.
    assert!(diagnostics(&[("dag.ms", &graph(40, false))]).is_empty());
}

#[test]
fn preserving_cycles_and_branching_paths_to_them_remain_valid() {
    let source = "def a[T](n: Int) -> Int:\n    return b[T](n)\n\ndef b[U](n: Int) -> Int:\n    return a[U](n)\n";
    assert!(diagnostics(&[("mutual.ms", source)]).is_empty());
    // Paths feeding a cycle must remain checked; this optimization does not collapse them.
    assert!(diagnostics(&[("cyclic-dag.ms", &graph(6, true))]).is_empty());
}

const RECURSION_ERROR: &str = "recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])";

#[test]
fn changing_cycle_keeps_ancestor_sensitive_diagnostics_and_order() {
    // A specialization-only memo can incorrectly reuse b[Int] from root's first call
    // while checking its second call under a different active a specialization.
    let source = "def root[T](n: Int) -> Unit:\n    b[Int](n)\n    a[List[T]](n)\n\ndef a[T](n: Int) -> Unit:\n    b[Int](n)\n\ndef b[T](n: Int) -> Unit:\n    a[Int](n)\n";
    assert_eq!(
        diagnostics(&[("ancestors.ms", source)]),
        vec![
            ("ancestors.ms".into(), 9, 5, RECURSION_ERROR.into()),
            ("ancestors.ms".into(), 6, 5, RECURSION_ERROR.into()),
        ]
    );
}

#[test]
fn acyclic_tail_does_not_hide_a_changing_cycle() {
    let source = "def tail[T](n: Int) -> Unit:\n    return\n\ndef a[T](n: Int) -> Unit:\n    tail[T](n)\n    a[List[T]](n)\n";
    assert_eq!(
        diagnostics(&[("tail.ms", source)]),
        vec![("tail.ms".into(), 6, 5, RECURSION_ERROR.into())]
    );
}

#[test]
fn same_spelling_in_other_modules_does_not_change_recursive_identity() {
    let recursive = "def same[T](n: Int) -> Unit:\n    same[List[T]](n)\n";
    let finite = "def same[T](n: Int) -> Unit:\n    return\n";
    assert_eq!(
        diagnostics(&[("recursive.ms", recursive), ("finite.ms", finite)]),
        vec![("recursive.ms".into(), 2, 5, RECURSION_ERROR.into())]
    );
}

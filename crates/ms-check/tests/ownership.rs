//! The ownership corpus. Every file under `tests/ownership/accept` must pass
//! with no diagnostics; every file under `tests/ownership/reject` marks the
//! offending line with a trailing `# error: <text>` comment, and the checker
//! must report exactly those diagnostics, one per marker, on those lines.

use ms_check::{CheckOptions, ImportMap};
use std::path::Path;
use std::sync::Arc;

fn diagnostics(source: &str) -> Vec<(u32, String)> {
    let file: Arc<str> = Arc::from("t.ms");
    let module = match ms_syntax::parser::parse(&file, source) {
        Ok(m) => m,
        Err(d) => return vec![(d.pos.line, format!("parse: {}", d.message))],
    };
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    program
        .diagnostics
        .iter()
        .map(|d| (d.pos.line, d.message.clone()))
        .collect()
}

fn markers(source: &str) -> Vec<(u32, String)> {
    source
        .lines()
        .enumerate()
        .filter_map(|(i, line)| {
            let (_, text) = line.split_once("# error: ")?;
            Some((i as u32 + 1, text.trim().to_string()))
        })
        .collect()
}

fn sources(dir: &str) -> Vec<(String, String)> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/ownership")
        .join(dir);
    let mut files: Vec<_> = std::fs::read_dir(&root)
        .expect("corpus directory")
        .map(|e| e.expect("entry").path())
        .filter(|p| p.extension().is_some_and(|e| e == "ms"))
        .collect();
    files.sort();
    files
        .into_iter()
        .map(|p| {
            let name = p.file_name().expect("name").to_string_lossy().into_owned();
            (name, std::fs::read_to_string(&p).expect("readable"))
        })
        .collect()
}

fn run_on_big_stack(f: impl FnOnce() + Send + 'static) {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(f)
        .expect("spawn")
        .join()
        .expect("corpus");
}

#[test]
fn accepted_programs_have_no_diagnostics() {
    run_on_big_stack(|| {
        let mut failures = Vec::new();
        for (name, source) in sources("accept") {
            let got = diagnostics(&source);
            if !got.is_empty() {
                failures.push(format!("{name}: {got:#?}"));
            }
        }
        assert!(
            failures.is_empty(),
            "unexpected diagnostics:\n{}",
            failures.join("\n")
        );
    });
}

#[test]
fn rejected_programs_report_exactly_the_marked_lines() {
    run_on_big_stack(|| {
        let mut failures = Vec::new();
        for (name, source) in sources("reject") {
            let expected = markers(&source);
            assert!(!expected.is_empty(), "{name} has no `# error:` marker");
            let mut got = diagnostics(&source);
            let mut missing = Vec::new();
            for (line, text) in &expected {
                match got
                    .iter()
                    .position(|(l, m)| l == line && m.contains(text.as_str()))
                {
                    Some(i) => {
                        got.remove(i);
                    }
                    None => missing.push(format!("line {line}: {text}")),
                }
            }
            if !missing.is_empty() || !got.is_empty() {
                failures.push(format!("{name}: missing {missing:?}, unexpected {got:#?}"));
            }
        }
        assert!(
            failures.is_empty(),
            "corpus mismatches:\n{}",
            failures.join("\n")
        );
    });
}

#[test]
fn facts_expose_moves_modes_and_drops() {
    use ms_check::ownership::{Access, ParamMode};
    run_on_big_stack(|| {
        let source = "fn take(xs: List[Int]) List[Int]:\n    return xs\n\nfn grow(var xs: List[Int]) Unit:\n    xs.append(1)\n\nfn f() Int:\n    var a = [1]\n    grow(var a)\n    let b = take(a)\n    a = [2]\n    return b.length() + a.length()\n";
        let file: Arc<str> = Arc::from("t.ms");
        let module = ms_syntax::parser::parse(&file, source).expect("parses");
        let program = ms_check::check(
            vec![ms_check::load_module(&module)],
            ImportMap::default(),
            CheckOptions::default(),
        );
        assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
        let hir = program.hir();
        let ownership = hir.ownership();
        assert!(
            ownership.diagnostics.is_empty(),
            "{:?}",
            ownership.diagnostics
        );
        let callables = hir.callables();
        let mode = |name: &str| {
            let c = callables
                .iter()
                .find(|c| c.name.as_str() == name)
                .expect("callable");
            ownership.of(c).expect("facts").parameters.clone()
        };
        assert_eq!(mode("take"), vec![ParamMode::Consume]);
        assert_eq!(mode("grow"), vec![ParamMode::Mutate]);
        let c = callables
            .iter()
            .find(|c| c.name.as_str() == "f")
            .expect("f");
        let facts = ownership.of(c).expect("facts");
        let moves = facts
            .uses
            .values()
            .filter(|u| u.access == Access::Move && u.last)
            .count();
        let writes = facts
            .uses
            .values()
            .filter(|u| u.access == Access::Write)
            .count();
        assert_eq!((moves, writes), (1, 1));
        assert_eq!(facts.drops_old.len(), 1);
    });
}

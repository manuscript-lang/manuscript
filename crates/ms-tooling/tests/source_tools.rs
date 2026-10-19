//! Differential tests of lint and inspect against the Go `ms` oracle
//! (`make build`). Set `MS_GO_ORACLE` to the Go binary (default `../../ms`);
//! the tests skip when it is absent. `MS_TOOLING_CORPUS` bounds the repository
//! files used (default 80). The Go-only identities (`go_id`, `build_id`,
//! `go_locals`) are not compared: they name Go lowering artifacts.

use ms_check::{CheckOptions, ImportMap, Program};
use ms_cli::json::{Json, parse};
use ms_tooling::inspect::inspect;
use ms_tooling::lint::lint_modules;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

fn oracle() -> Option<PathBuf> {
    let path = std::env::var_os("MS_GO_ORACLE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../ms"));
    path.exists().then_some(path)
}

fn go(oracle: &Path, dir: &Path, args: &[&str]) -> Option<String> {
    let out = Command::new(oracle)
        .args(args)
        .current_dir(dir)
        .output()
        .expect("run oracle");
    // Lint exits 1 when it has findings; anything else is a real failure.
    matches!(out.status.code(), Some(0 | 1))
        .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Checks one standalone module that imports only the standard library.
fn check_source(source: &str) -> Option<Program> {
    let file: Arc<str> = Arc::from("r.ms");
    let module = ms_syntax::parser::parse(&file, source).ok()?;
    if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
        return None;
    }
    let program = ms_check::check(
        vec![ms_check::load_module(&module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    program.diagnostics.is_empty().then_some(program)
}

fn corpus() -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests");
    let limit = std::env::var("MS_TOOLING_CORPUS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(80);
    let mut files = Vec::new();
    let mut stack = vec![root];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "ms") {
                files.push(path);
            }
        }
    }
    files.sort();
    // Spread the sample over the whole tree instead of taking one directory.
    let step = (files.len() / limit.max(1)).max(1);
    files.into_iter().step_by(step).take(limit).collect()
}

/// Drops Go lowering identities and orders locals by position.
fn normalize(value: Json) -> Json {
    match value {
        Json::Obj(fields) => {
            let mut fields: Vec<(String, Json)> = fields
                .into_iter()
                .filter(|(k, _)| !matches!(k.as_str(), "go_id" | "build_id" | "go_locals"))
                .map(|(k, v)| {
                    let v = normalize(v);
                    let v = match (k.as_str(), v) {
                        ("locals", Json::Arr(mut items)) => {
                            items.sort_by_key(|l| (start(l), name(l)));
                            Json::Arr(items)
                        }
                        (_, v) => v,
                    };
                    (k, v)
                })
                .collect();
            fields.sort_by(|a, b| a.0.cmp(&b.0));
            Json::Obj(fields)
        }
        Json::Arr(items) => Json::Arr(items.into_iter().map(normalize).collect()),
        other => other,
    }
}

fn start(local: &Json) -> i64 {
    match local.get("span").and_then(|s| s.get("start")) {
        Some(Json::Num(n)) => n.parse().unwrap_or(0),
        _ => 0,
    }
}

fn name(local: &Json) -> String {
    local
        .get("name")
        .and_then(Json::as_str)
        .unwrap_or("")
        .to_string()
}

fn lint_lines(document: &Json) -> Vec<String> {
    document
        .get("diagnostics")
        .and_then(Json::as_array)
        .unwrap_or(&[])
        .iter()
        .map(|d| {
            let position = d.get("position");
            let number = |k: &str| match position.and_then(|p| p.get(k)) {
                Some(Json::Num(n)) => n.clone(),
                _ => String::new(),
            };
            format!(
                "{}:{} {} {}",
                number("line"),
                number("column"),
                d.get("code").and_then(Json::as_str).unwrap_or(""),
                d.get("message").and_then(Json::as_str).unwrap_or("")
            )
        })
        .collect()
}

#[test]
fn lint_and_inspect_match_go() {
    let Some(oracle) = oracle() else {
        eprintln!("skipping: no Go oracle (run `make build`)");
        return;
    };
    let dir = std::env::temp_dir().join(format!("ms-tooling-source-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut compared = 0;
    for path in corpus() {
        let Ok(source) = std::fs::read_to_string(&path) else {
            continue;
        };
        let Some(program) = check_source(&source) else {
            continue;
        };
        std::fs::write(dir.join("r.ms"), &source).unwrap();
        let label = path.display().to_string();

        let Some(lint) = go(&oracle, &dir, &["lint", "r.ms", "--json"]) else {
            continue;
        };
        let want = lint_lines(&parse(&lint).expect("oracle lint json"));
        let got: Vec<String> = lint_modules(&program)
            .iter()
            .map(|f| format!("{}:{} {} {}", f.pos.line, f.pos.column, f.code, f.message))
            .collect();
        assert_eq!(got, want, "{label}: lint differs");

        let Some(inspection) = go(&oracle, &dir, &["inspect", "r.ms"]) else {
            continue;
        };
        let want = normalize(parse(&inspection).expect("oracle inspection json"));
        let got = normalize(parse(&inspect(&program).to_json().encode()).expect("own json"));
        assert_eq!(got, want, "{label}: inspection differs");
        compared += 1;
    }
    let _ = std::fs::remove_dir_all(&dir);
    assert!(compared > 0, "no corpus file was comparable");
}

fn lint_of(source: &str) -> Vec<String> {
    let program = check_source(source).expect("source checks");
    lint_modules(&program)
        .iter()
        .map(|f| format!("{}:{} {}", f.pos.line, f.pos.column, f.code))
        .collect()
}

#[test]
fn lexical_findings() {
    let file: Arc<str> = Arc::from("a.ms");
    let findings = ms_tooling::lint::lint_source(&file, "fn f():  \r\n    return unit\t\nx");
    let got: Vec<_> = findings
        .iter()
        .map(|f| (f.code, f.pos.line, f.pos.column, f.pos.offset))
        .collect();
    assert_eq!(
        got,
        vec![
            ("MSL001", 1, 8, 7),
            ("MSL001", 2, 16, 26),
            ("MSL002", 3, 2, 29),
        ]
    );
}

#[test]
fn semantic_findings() {
    let source = "\
import stdout from \"@std/io.ms\"
fn main() Int:
    let unused = 1
    match some(1):
        some(v): return v
        none: return 0
    return 0
";
    assert_eq!(
        lint_of(source),
        vec!["1:8 MSL102", "3:9 MSL101", "4:5 MSL108", "7:5 MSL103"]
    );
}

#[test]
fn inspection_describes_entities_and_calls() {
    let source = "type P:\n    x: Int\nfn add(a: Int, b: Int) Int:\n    return a + b\nfn main() Int:\n    let p = P(x: 1)\n    return add(p.x, 2)\n";
    let program = check_source(source).expect("source checks");
    let inspection = inspect(&program);
    let ids: Vec<&str> = inspection.entities.iter().map(|e| e.id.as_str()).collect();
    assert_eq!(ids, ["r.ms#fn#add", "r.ms#fn#main", "r.ms#record#P"]);
    let calls: Vec<(&str, &str)> = inspection
        .calls
        .iter()
        .map(|c| (c.kind.as_str(), c.target.as_str()))
        .collect();
    assert_eq!(calls, [("function", "r.ms#fn#add"), ("construct", "P")]);
    assert_eq!(inspection.build_id.len(), 64);
}

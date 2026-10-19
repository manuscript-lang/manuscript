//! Differential tests against the Go `ms` oracle (`make build`). The Go
//! inspection supplies the entity and call rows (the inspector is ported
//! separately); everything downstream of them (facts, flow, views, diagrams,
//! reports, diffs) is Rust and must print the same bytes as Go.
//!
//! Set `MS_GO_ORACLE` to the Go binary (default `../../ms`); the tests skip
//! when it is absent. `MS_TOOLING_CORPUS` bounds the repository files used
//! (default 60).

use ms_check::{CheckOptions, ImportMap, Program};
use ms_cli::json::{Json, parse};
use ms_tooling::collect::{CallRow, EntityRow, InspectionRows, collect_facts};
use ms_tooling::diagram::diagram_ascii;
use ms_tooling::diff::{parse_diff, reverse_apply};
use ms_tooling::facts::Facts;
use ms_tooling::mark::{explain, mark_changes};
use ms_tooling::report::{ReviewOptions, diff_report, project_report};
use ms_tooling::review::{DiffInput, compare_facts};
use ms_tooling::views::build_view;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

fn oracle() -> Option<PathBuf> {
    let path = std::env::var_os("MS_GO_ORACLE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../ms"));
    path.exists().then_some(path)
}

struct Output {
    status: i32,
    stdout: String,
    stderr: String,
}

fn go(oracle: &Path, dir: &Path, args: &[&str]) -> Output {
    let out = Command::new(oracle)
        .args(args)
        .current_dir(dir)
        .output()
        .expect("run oracle");
    Output {
        status: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

fn field<'a>(json: &'a Json, key: &str) -> &'a Json {
    json.get(key)
        .unwrap_or_else(|| panic!("inspection lacks {key}"))
}

fn text(json: &Json, key: &str) -> String {
    json.get(key)
        .and_then(Json::as_str)
        .unwrap_or("")
        .to_string()
}

fn number(json: &Json, key: &str) -> usize {
    match json.get(key) {
        Some(Json::Num(n)) => n.parse().unwrap_or(0),
        _ => 0,
    }
}

/// Entity and call rows from the Go `ms inspect` document.
fn rows(document: &str) -> InspectionRows {
    let json = parse(document).expect("inspection is JSON");
    let mut rows = InspectionRows::default();
    for e in field(&json, "entities").as_array().unwrap_or(&[]) {
        let span = field(e, "span");
        rows.entities.push(EntityRow {
            id: text(e, "id"),
            kind: text(e, "kind"),
            name: text(e, "name"),
            ty: text(e, "type"),
            file: text(span, "file"),
            line: number(span, "line"),
            exported: matches!(e.get("exported"), Some(Json::Bool(true))),
            effects: e
                .get("effects")
                .and_then(Json::as_array)
                .map(|list| {
                    list.iter()
                        .filter_map(|s| s.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default(),
        });
    }
    for c in field(&json, "calls").as_array().unwrap_or(&[]) {
        rows.calls.push(CallRow {
            id: text(c, "id"),
            owner: text(c, "owner"),
            target: text(c, "target"),
            kind: text(c, "kind"),
        });
    }
    rows
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

struct Case {
    dir: PathBuf,
    inspection: InspectionRows,
    facts: Facts,
}

fn prepare(oracle: &Path, root: &Path, name: &str, source: &str) -> Option<Case> {
    let program = check_source(source)?;
    let dir = root.join(name);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("r.ms"), source).unwrap();
    let inspect = go(oracle, &dir, &["inspect", "r.ms"]);
    if inspect.status != 0 {
        return None;
    }
    let inspection = rows(&inspect.stdout);
    let facts = collect_facts(&inspection, &program);
    Some(Case {
        dir,
        inspection,
        facts,
    })
}

fn same(label: &str, go: &Output, rust_stdout: String) {
    assert_eq!(go.status, 0, "{label}: oracle failed: {}", go.stderr);
    assert_eq!(go.stdout, rust_stdout, "{label}: output differs");
}

fn compare_case(oracle: &Path, label: &str, case: &Case) {
    let dir = &case.dir;
    let facts = &case.facts;
    same(
        label,
        &go(oracle, dir, &["diagram", "r.ms"]),
        diagram_ascii(&case.inspection),
    );
    let project = project_report(facts, ReviewOptions::default());
    same(
        &format!("{label} review"),
        &go(oracle, dir, &["review", "r.ms"]),
        project.render("ascii"),
    );
    same(
        &format!("{label} review --all"),
        &go(oracle, dir, &["review", "r.ms", "--all"]),
        project_report(facts, ReviewOptions { all: true }).render("ascii"),
    );
    same(
        &format!("{label} review markdown"),
        &go(oracle, dir, &["review", "r.ms", "--format", "markdown"]),
        project.render("markdown"),
    );
    same(
        &format!("{label} review json"),
        &go(oracle, dir, &["review", "r.ms", "--json"]),
        project.render("json"),
    );
    for view in ["calls", "effects", "errors", "modules"] {
        for format in ["ascii", "mermaid"] {
            let output = go(
                oracle,
                dir,
                &["diagram", "r.ms", "--view", view, "--format", format],
            );
            let tree = build_view(facts, view, "", 0).expect("view");
            let rendered = if format == "mermaid" {
                tree.mermaid()
            } else {
                tree.ascii()
            };
            same(&format!("{label} {view} {format}"), &output, rendered);
        }
    }
    let deep = go(
        oracle,
        dir,
        &["diagram", "r.ms", "--view", "calls", "--depth", "6"],
    );
    same(
        &format!("{label} depth"),
        &deep,
        build_view(facts, "calls", "", 6).unwrap().ascii(),
    );
    for entity in facts
        .entities
        .values()
        .filter(|f| f.kind == "fn" || f.kind == "method" || f.kind == "test")
    {
        for (view, depth) in [
            ("flow", "1"),
            ("flow", "3"),
            ("scope", "2"),
            ("calls", "2"),
            ("effects", "2"),
            ("errors", "2"),
        ] {
            let args = [
                "diagram",
                "r.ms",
                "--view",
                view,
                "--entity",
                entity.name.as_str(),
                "--depth",
                depth,
            ];
            let output = go(oracle, dir, &args);
            let what = format!("{label} {view} {} depth {depth}", entity.name);
            match build_view(facts, view, &entity.name, depth.parse().unwrap()) {
                Ok(tree) => same(&what, &output, tree.ascii()),
                Err(message) => {
                    assert_eq!(output.status, 2, "{what}");
                    assert_eq!(output.stderr, format!("ms diagram: {message}\n"), "{what}");
                }
            }
        }
    }
}

const BASE: &str = "import stdout from \"@std/io.ms\"

fn say(text: String) Result[Unit, Error]:
    try stdout().write(\"{text}\\n\")
    return stdout().flush()

fn add(a: Int, b: Int) Int:
    return a + b

export fn run() Int:
    return add(1, 2)
";

const FLOW: &str = "import stdout from \"@std/io.ms\"

fn load(n: Int) Result[Int, Error]:
    if n > 3:
        return ok(0)
    return ok(n)

fn guarded(n: Int) Result[Int, Error]:
    with out = stdout():
        let v = try load(n)
        if v > 1:
            return ok(2)
    return ok(0)

export fn main() Int:
    match guarded(1):
        ok(_): return 0
        error(_): return 1
";

const MORE: &str = "import {expect_equal} from \"@std/testing.ms\"

type Shape:
    case Circle(r: Int)
    case Square(side: Int)

let limit = 10

fn area(s: Shape) Int:
    return match s:
        Circle(r): r * r * 3
        Square(side): side * side

fn total(items: List[Shape]) Int:
    var sum = 0
    for s in items:
        if area(s) > limit:
            sum += area(s)
        else:
            continue
    while sum > 100:
        sum -= 1
        if sum == 50:
            break
    return sum

test \"area works\":
    area(Circle(r: 1)) | try expect_equal(expected: 3)
";

fn workdir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-tooling-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn inline_programs_match_go() {
    let Some(oracle) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let root = workdir("inline");
    for (name, source) in [("base", BASE), ("flow", FLOW), ("more", MORE)] {
        let case =
            prepare(&oracle, &root, name, source).unwrap_or_else(|| panic!("{name} must check"));
        compare_case(&oracle, name, &case);
    }
    let _ = std::fs::remove_dir_all(&root);
}

fn collect_sources(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<_> = entries.flatten().map(|e| e.path()).collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            collect_sources(&path, out);
        } else if path.extension().is_some_and(|e| e == "ms") {
            out.push(path);
        }
    }
}

#[test]
fn repository_corpus_matches_go() {
    let Some(oracle) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut files = Vec::new();
    for sub in ["tests", "examples"] {
        collect_sources(&repo.join(sub), &mut files);
    }
    files.retain(|p| {
        std::fs::metadata(p)
            .map(|m| m.len() < 6000)
            .unwrap_or(false)
    });
    let limit: usize = std::env::var("MS_TOOLING_CORPUS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(60);
    let step = (files.len() / limit.max(1)).max(1);
    let root = workdir("corpus");
    let mut compared = 0;
    for (i, path) in files.iter().step_by(step).take(limit).enumerate() {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let Some(case) = prepare(&oracle, &root, &format!("c{i}"), &source) else {
            continue;
        };
        compare_case(&oracle, &path.display().to_string(), &case);
        compared += 1;
    }
    let _ = std::fs::remove_dir_all(&root);
    assert!(
        compared >= 10,
        "only {compared} corpus files could be compared"
    );
}

/// Writes a unified diff of two sources the way `git diff --no-index` would.
fn make_patch(dir: &Path, base: &str, head: &str) -> String {
    std::fs::write(dir.join("base.txt"), base).unwrap();
    std::fs::write(dir.join("head.txt"), head).unwrap();
    let out = Command::new("diff")
        .args([
            "-u", "--label", "a/r.ms", "--label", "b/r.ms", "base.txt", "head.txt",
        ])
        .current_dir(dir)
        .output()
        .expect("diff");
    String::from_utf8(out.stdout).unwrap()
}

fn change_input(files: &[ms_tooling::diff::DiffFile], base_checked: bool) -> DiffInput {
    let mut input = DiffInput {
        files: files.len(),
        base_checked,
        ..DiffInput::default()
    };
    for file in files {
        for hunk in &file.hunks {
            for line in &hunk.lines {
                match line.as_bytes()[0] {
                    b'+' => input.insertions += 1,
                    b'-' => input.deletions += 1,
                    _ => {}
                }
            }
        }
        input.sources += 1;
        input
            .touched
            .insert(file.path().to_string(), file.touched_lines());
    }
    input
}

#[test]
fn diff_reviews_match_go() {
    let Some(oracle) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let root = workdir("diff");
    let edits: &[(&str, &str, &str)] = &[
        (
            "effect",
            "    return a + b",
            "    say(\"adding\")\n    return a + b",
        ),
        ("body", "return a + b", "return b + a"),
        ("same", "return a + b", "return a + b"),
        (
            "type",
            "fn add(a: Int, b: Int) Int:\n    return a + b",
            "fn add(a: Int, b: Int) Float:\n    return 1.0",
        ),
        ("export", "fn add(", "export fn add("),
        (
            "removed",
            "fn add(a: Int, b: Int) Int:\n    return a + b\n\n",
            "",
        ),
    ];
    for (name, from, to) in edits {
        let base = BASE.replacen(from, to, 1);
        let head = BASE;
        // `base` here is the edited text; the head is the original, so the diff goes edited -> original.
        let head_case = prepare(&oracle, &root, &format!("{name}-head"), head);
        let base_case = prepare(&oracle, &root, &format!("{name}-base"), &base);
        let (Some(head_case), base_case) = (head_case, base_case) else {
            panic!("{name}: head must check")
        };
        let patch = make_patch(&head_case.dir, &base, head);
        std::fs::write(head_case.dir.join("change.patch"), &patch).unwrap();
        let files = parse_diff(&patch).unwrap();
        let input = change_input(&files, base_case.is_some());
        let empty = Facts::default();
        let base_facts = base_case.as_ref().map_or(&empty, |c| &c.facts);
        let expected = go(
            &oracle,
            &head_case.dir,
            &["review", "r.ms", "--diff", "change.patch"],
        );
        let report = diff_report(
            base_facts,
            &head_case.facts,
            &input,
            ReviewOptions::default(),
        );
        same(&format!("{name} review"), &expected, report.render("ascii"));
        let json = go(
            &oracle,
            &head_case.dir,
            &["review", "r.ms", "--diff", "change.patch", "--json"],
        );
        same(&format!("{name} json"), &json, report.render("json"));
        let markdown = go(
            &oracle,
            &head_case.dir,
            &[
                "review",
                "r.ms",
                "--diff",
                "change.patch",
                "--format",
                "markdown",
            ],
        );
        same(
            &format!("{name} markdown"),
            &markdown,
            report.render("markdown"),
        );
        let findings = compare_facts(base_facts, &head_case.facts, &input);
        for selector in ["1", "run", "add", "9"] {
            let out = go(
                &oracle,
                &head_case.dir,
                &[
                    "review",
                    "r.ms",
                    "--diff",
                    "change.patch",
                    "--explain",
                    selector,
                ],
            );
            match explain(&findings, &head_case.facts, selector) {
                Ok(text) => same(&format!("{name} explain {selector}"), &out, text),
                Err(message) => assert_eq!(
                    out.stderr,
                    format!("ms review: {message}\n"),
                    "{name} explain {selector}"
                ),
            }
        }
        for (view, entity) in [
            ("calls", ""),
            ("flow", "run"),
            ("flow", "add"),
            ("effects", ""),
        ] {
            let mut args = vec!["diagram", "r.ms", "--view", view, "--diff", "change.patch"];
            if !entity.is_empty() {
                args.extend(["--entity", entity]);
            }
            let out = go(&oracle, &head_case.dir, &args);
            if let Ok(mut tree) = build_view(&head_case.facts, view, entity, 0) {
                mark_changes(&mut tree, &findings, &input.touched);
                same(
                    &format!("{name} {view} {entity} marked"),
                    &out,
                    tree.ascii(),
                );
            }
        }
        // The reverse application the CLI performs must rebuild the base text.
        if let Some(file) = files.first() {
            assert_eq!(
                reverse_apply(head, &file.hunks).as_deref(),
                Ok(base.as_str()),
                "{name}: reverse apply"
            );
        }
    }
    let _ = std::fs::remove_dir_all(&root);
}

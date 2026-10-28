//! Review and diagram must be usable through the installed CLI surface.

use ms_json::Json;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-review-diagram-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn ms(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap()
}

fn json(output: &Output) -> Json {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap()
}

#[test]
fn diagram_json_preserves_source_navigation_and_recursion() {
    let dir = scratch("json");
    std::fs::write(
        dir.join("main.ms"),
        "fn recurse(n: Int) Int:\n    if n == 0: return 0\n    return recurse(n - 1)\n",
    )
    .unwrap();
    let output = ms(&dir, &["diagram", "main.ms", "--json"]);
    let doc = json(&output);
    assert_eq!(doc.get("view").unwrap().as_str(), Some("calls"));
    let root = &doc
        .get("tree")
        .unwrap()
        .get("children")
        .unwrap()
        .as_array()
        .unwrap()[0];
    assert_eq!(
        root.get("reference").unwrap().as_str(),
        Some("main.ms#fn#recurse")
    );
    assert_eq!(root.get("file").unwrap().as_str(), Some("main.ms"));
    assert!(root.get("line").unwrap().as_i64().unwrap() > 0);
    let text = ms(&dir, &["diagram", "main.ms", "--view", "calls"]);
    assert!(String::from_utf8_lossy(&text.stdout).contains("(cycle)"));
    let flow = json(&ms(
        &dir,
        &[
            "diagram", "main.ms", "--view", "flow", "--entity", "recurse", "--json",
        ],
    ));
    assert_eq!(flow.get("view").unwrap().as_str(), Some("flow"));
    let modules = json(&ms(
        &dir,
        &["diagram", "main.ms", "--view", "modules", "--json"],
    ));
    let nodes = modules
        .get("tree")
        .unwrap()
        .get("children")
        .unwrap()
        .as_array()
        .unwrap();
    assert_eq!(nodes[0].get("file").unwrap().as_str(), Some("main.ms"));
    assert_eq!(
        output.stdout,
        ms(&dir, &["diagram", "main.ms", "--json"]).stdout
    );
    let conflict = ms(
        &dir,
        &["diagram", "main.ms", "--json", "--format", "mermaid"],
    );
    assert_eq!(conflict.status.code(), Some(2));
    assert!(
        String::from_utf8_lossy(&conflict.stderr)
            .contains("--json and --format cannot be combined")
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_json_links_a_finding_to_its_diagram() {
    let dir = scratch("handoff");
    std::fs::write(
        dir.join("main.ms"),
        "export fn value() String:\n    return \"new\"\n",
    )
    .unwrap();
    std::fs::write(dir.join("change.patch"), "--- a/main.ms\n+++ b/main.ms\n@@ -1,2 +1,2 @@\n-export fn value() Int:\n-    return 1\n+export fn value() String:\n+    return \"new\"\n").unwrap();
    let report = json(&ms(
        &dir,
        &["review", "main.ms", "--diff", "change.patch", "--json"],
    ));
    assert_eq!(report.get("base_checked"), Some(&Json::Bool(true)));
    let findings = report.get("findings").unwrap().as_array().unwrap();
    assert_eq!(findings.len(), 1);
    assert_eq!(findings[0].get("number").unwrap().as_i64(), Some(1));
    let explanation = json(&ms(
        &dir,
        &[
            "review",
            "main.ms",
            "--diff",
            "change.patch",
            "--explain",
            "1",
            "--json",
        ],
    ));
    let diagram = explanation.get("diagram").unwrap();
    let view = diagram.get("view").unwrap().as_str().unwrap();
    let entity = diagram.get("entity").unwrap().as_str().unwrap();
    let tree = json(&ms(
        &dir,
        &[
            "diagram",
            "main.ms",
            "--view",
            view,
            "--entity",
            entity,
            "--diff",
            "change.patch",
            "--json",
        ],
    ));
    assert!(tree.pretty(ms_json::Escape::Plain).contains("CONTRACT #1"));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_preserves_source_and_reports_check_failures_as_json() {
    let dir = scratch("outputs");
    let source = "export fn value() Int:\n    return 1\n";
    std::fs::write(dir.join("main.ms"), source).unwrap();
    let output = ms(&dir, &["review", "main.ms", "-o", "main.ms"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("would overwrite"));
    assert_eq!(
        std::fs::read_to_string(dir.join("main.ms")).unwrap(),
        source
    );
    std::fs::write(
        dir.join("main.ms"),
        "fn value() Int:\n    return \"wrong\"\n",
    )
    .unwrap();
    for command in ["review", "diagram"] {
        let output = ms(&dir, &[command, "main.ms", "--json"]);
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stderr.is_empty());
        let doc = ms_json::parse(std::str::from_utf8(&output.stdout).unwrap()).unwrap();
        assert!(
            !doc.get("diagnostics")
                .unwrap()
                .as_array()
                .unwrap()
                .is_empty()
        );
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn json_project_reports_are_complete_while_text_stays_bounded() {
    let dir = scratch("complete");
    let source: String = (0..8)
        .map(|n| format!("export fn value{n}() Int:\n    return {n}\n\n"))
        .collect();
    std::fs::write(dir.join("main.ms"), source).unwrap();
    let report = json(&ms(&dir, &["review", "main.ms", "--json"]));
    assert_eq!(report.get("base_checked"), Some(&Json::Null));
    assert!(
        report
            .get("findings")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
    let sections = report.get("sections").unwrap().as_array().unwrap();
    let surface = sections
        .iter()
        .find(|s| s.get("title").unwrap().as_str() == Some("PUBLIC SURFACE"))
        .unwrap();
    assert_eq!(surface.get("rows").unwrap().as_array().unwrap().len(), 8);
    let text = ms(&dir, &["review", "main.ms"]);
    assert!(String::from_utf8_lossy(&text.stdout).contains("+3 more (use --all)"));
    let written = ms(
        &dir,
        &["diagram", "main.ms", "--json", "-o", "diagram.json"],
    );
    assert!(written.status.success());
    assert!(written.stdout.is_empty());
    ms_json::parse(std::fs::read_to_string(dir.join("diagram.json")).unwrap()).unwrap();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn standard_library_is_a_boundary_rather_than_the_project_surface() {
    let dir = scratch("boundaries");
    std::fs::write(dir.join("main.ms"), "import arguments from \"@std/process.ms\"\n\nexport fn main() Int:\n    return arguments().length()\n").unwrap();
    let report = json(&ms(&dir, &["review", "main.ms", "--json"]));
    assert_eq!(
        report.get("result").unwrap().as_str(),
        Some("1 modules, 1 entities")
    );
    let sections = report.get("sections").unwrap().as_array().unwrap();
    let surface = sections
        .iter()
        .find(|s| s.get("title").unwrap().as_str() == Some("PUBLIC SURFACE"))
        .unwrap();
    assert_eq!(surface.get("rows").unwrap().as_array().unwrap().len(), 1);
    let calls = json(&ms(&dir, &["diagram", "main.ms", "--json"]));
    let roots = calls
        .get("tree")
        .unwrap()
        .get("children")
        .unwrap()
        .as_array()
        .unwrap();
    assert_eq!(roots.len(), 1);
    assert!(
        calls
            .pretty(ms_json::Escape::Plain)
            .contains("@std/process.ms#fn#arguments")
    );
    let ascii = ms(&dir, &["diagram", "main.ms"]);
    let ascii = String::from_utf8_lossy(&ascii.stdout);
    assert_eq!(
        ascii.lines().filter(|line| line.ends_with("[fn]")).count(),
        1
    );
    assert!(ascii.contains("@std/process.ms#fn#arguments"));
    let mermaid = ms(&dir, &["diagram", "main.ms", "--format", "mermaid"]);
    let mermaid = String::from_utf8_lossy(&mermaid.stdout);
    assert!(mermaid.contains("arguments"));
    assert!(!mermaid.contains("HttpClient"));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn project_review_counts_discovered_test_files() {
    let dir = scratch("tests");
    std::fs::create_dir_all(dir.join("src")).unwrap();
    std::fs::write(
        dir.join("ms.toml"),
        "[project]\nname = \"p\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n",
    )
    .unwrap();
    std::fs::write(
        dir.join("src/main.ms"),
        "export fn main() Int:\n    return 0\n",
    )
    .unwrap();
    std::fs::write(dir.join("test.ms"), "test \"t\":\n    return unit\n").unwrap();
    let output = ms(&dir, &["review", "ms.toml"]);
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains("tests                 1"), "{text}");
}

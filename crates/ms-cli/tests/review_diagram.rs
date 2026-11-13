//! Review and diagram must be usable through the installed CLI surface.

use crate::common;

use common::scratch;
use ms_json::Json;
use std::path::Path;
use std::process::{Command, Output};

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
fn review_and_diagram_accept_metadata_only_git_sections() {
    let dir = scratch("metadata-only-diff");
    std::fs::write(dir.join("empty.ms"), "").unwrap();
    for path in ["main.ms", "name with spaces.ms", "café.ms"] {
        std::fs::write(dir.join(path), include_str!("review_quoted/head.ms")).unwrap();
        let patch = format!(
            "diff --git a/{path} b/{path}\nold mode 100644\nnew mode 100755\ndiff --git a/empty.ms b/empty.ms\nnew file mode 100644\nindex 0000000..e69de29\ndiff --git a/gone.ms b/gone.ms\ndeleted file mode 100644\nindex e69de29..0000000\n"
        );
        std::fs::write(dir.join("change.patch"), patch).unwrap();
        let report = json(&ms(
            &dir,
            &["review", path, "--diff", "change.patch", "--json"],
        ));
        assert_eq!(report.get("base_checked"), Some(&Json::Bool(true)));
        assert_eq!(
            report.get("input").and_then(Json::as_str),
            Some("diff (3 files, 3 source, +0 -0)")
        );
        assert!(
            report
                .get("findings")
                .unwrap()
                .as_array()
                .unwrap()
                .is_empty()
        );
        let _ = json(&ms(
            &dir,
            &[
                "diagram",
                path,
                "--view",
                "calls",
                "--diff",
                "change.patch",
                "--json",
            ],
        ));
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_reject_binary_source_diffs() {
    let dir = scratch("binary-source-diff");
    std::fs::write(dir.join("main.ms"), include_str!("review_quoted/head.ms")).unwrap();
    for metadata in [
        "Binary files a/main.ms and b/main.ms differ",
        "GIT binary patch",
    ] {
        std::fs::write(
            dir.join("change.patch"),
            format!("diff --git a/main.ms b/main.ms\nindex 1234567..7654321 100644\n{metadata}\n"),
        )
        .unwrap();
        for command in ["review", "diagram"] {
            let mut args = vec![command, "main.ms", "--diff", "change.patch", "--json"];
            if command == "diagram" {
                args.extend(["--view", "calls"]);
            }
            let output = ms(&dir, &args);
            assert_eq!(output.status.code(), Some(2), "{output:?}");
            assert!(output.stdout.is_empty());
            assert!(String::from_utf8_lossy(&output.stderr).contains("binary diff"));
        }
    }
    std::fs::write(dir.join("change.patch"), "diff --git a/image.png b/image.png\nindex 1234567..7654321 100644\nBinary files a/image.png and b/image.png differ\n").unwrap();
    let output = ms(
        &dir,
        &["review", "main.ms", "--diff", "change.patch", "--json"],
    );
    assert_eq!(output.status.code(), Some(2), "{output:?}");
    assert!(output.stdout.is_empty());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_reject_truncated_context_at_eof() {
    let dir = scratch("truncated-diff-context");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("review_diff_truncation/main.ms"),
    )
    .unwrap();
    for newline in ["\n", "\r\n"] {
        std::fs::write(
            dir.join("change.patch"),
            include_str!("review_diff_truncation/change.patch").replace('\n', newline),
        )
        .unwrap();
        for command in ["review", "diagram"] {
            let mut args = vec![command, "main.ms", "--diff", "change.patch", "--json"];
            if command == "diagram" {
                args.extend(["--view", "calls"]);
            }
            let output = ms(&dir, &args);
            assert_eq!(output.status.code(), Some(2));
            assert!(output.stdout.is_empty());
            assert!(
                String::from_utf8_lossy(&output.stderr)
                    .contains("hunk is shorter than its header declares")
            );
        }
    }
}

#[test]
fn review_and_diagram_reject_invalid_ranges_without_panicking() {
    let dir = scratch("invalid-diff-ranges");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("review_diff_truncation/main.ms"),
    )
    .unwrap();
    for range in ["-9223372036854775808", "9223372036854775807", "0", "1,-1"] {
        std::fs::write(
            dir.join("change.patch"),
            format!("--- a/main.ms\n+++ b/main.ms\n@@ -1 +{range} @@\n-old\n+new\n"),
        )
        .unwrap();
        for command in ["review", "diagram"] {
            let mut args = vec![command, "main.ms", "--diff", "change.patch", "--json"];
            if command == "diagram" {
                args.extend(["--view", "calls"]);
            }
            let output = ms(&dir, &args);
            assert_eq!(output.status.code(), Some(2), "{output:?}");
            assert!(output.stdout.is_empty());
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("malformed hunk range"),
                "{output:?}"
            );
        }
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_reject_inconsistent_hunk_structure() {
    let dir = scratch("inconsistent-hunk-structure");
    let head = include_str!("review_quoted/head.ms");
    std::fs::write(dir.join("main.ms"), head).unwrap();
    let old = head.replace("new", "old");
    let body = old
        .lines()
        .map(|line| format!("-{line}\n"))
        .chain(head.lines().map(|line| format!("+{line}\n")))
        .collect::<String>();
    for (old_start, hunk_body, reason) in [
        (1, format!("{body}+not in the file\n"), "hunk is longer"),
        (1, format!("{body}\n+not in the file\n"), "hunk is longer"),
        (5, body.clone(), "old hunk position"),
        (
            1,
            body.replacen('\n', "\n\\ No newline at end of file\n", 1),
            "no-newline marker",
        ),
    ] {
        std::fs::write(dir.join("change.patch"), format!("diff --git a/main.ms b/main.ms\n--- a/main.ms\n+++ b/main.ms\n@@ -{old_start},2 +1,2 @@\n{hunk_body}")).unwrap();
        for command in ["review", "diagram"] {
            let mut args = vec![command, "main.ms", "--diff", "change.patch", "--json"];
            if command == "diagram" {
                args.extend(["--view", "calls"]);
            }
            let output = ms(&dir, &args);
            assert_eq!(output.status.code(), Some(2), "{output:?}");
            assert!(output.stdout.is_empty());
            assert!(
                String::from_utf8_lossy(&output.stderr).contains(reason),
                "{output:?}"
            );
        }
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_validate_complete_deletion_hunks() {
    let dir = scratch("complete-deletion-hunks");
    std::fs::write(dir.join("main.ms"), include_str!("review_quoted/head.ms")).unwrap();
    for (hunk, valid) in [
        ("@@ -200 +0,0 @@\n-old\n", false),
        ("@@ -1 +4,0 @@\n-old\n", false),
        ("@@ -1 +1 @@\n-old\n+new\n", false),
        ("@@ -1 +0,0 @@\n-old\n", true),
        ("@@ -1 +0,0 @@\n-old\n\\ No newline at end of file\n", true),
        ("", true),
    ] {
        std::fs::write(dir.join("change.patch"), format!("diff --git a/gone.ms b/gone.ms\ndeleted file mode 100644\n--- a/gone.ms\n+++ /dev/null\n{hunk}")).unwrap();
        for command in ["review", "diagram"] {
            let mut args = vec![command, "main.ms", "--diff", "change.patch", "--json"];
            if command == "diagram" {
                args.extend(["--view", "calls"]);
            }
            let output = ms(&dir, &args);
            if valid {
                json(&output);
            } else {
                assert_eq!(output.status.code(), Some(2), "{hunk}: {output:?}");
                assert!(output.stdout.is_empty());
                assert!(String::from_utf8_lossy(&output.stderr).contains("gone.ms"));
            }
        }
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn diagram_ambiguous_entity_remedies_are_usable() {
    let dir = scratch("selectors");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("diagram_selectors/main.ms"),
    )
    .unwrap();
    std::fs::write(
        dir.join("other.ms"),
        include_str!("diagram_selectors/other.ms"),
    )
    .unwrap();
    for (name, expected) in [
        ("Box", vec!["main.ms#impl#Box", "main.ms#type#Box"]),
        ("main.ms::Box", vec!["main.ms#impl#Box", "main.ms#type#Box"]),
        ("Item", vec!["main.ms#type#Item", "other.ms#type#Item"]),
        ("Named", vec!["main.ms#type#Named", "other.ms#type#Named"]),
    ] {
        let args = [
            "diagram", "main.ms", "--view", "types", "--entity", name, "--json",
        ];
        let output = ms(&dir, &args);
        assert_eq!(output.status.code(), Some(2));
        assert!(output.stdout.is_empty());
        assert_eq!(output.stderr, ms(&dir, &args).stderr);
        let error = std::str::from_utf8(&output.stderr).unwrap().trim();
        let error = error.strip_prefix("ms diagram: ").unwrap();
        let (_, remedies) = error.split_once(": ").unwrap();
        let remedies = remedies.split("; ").next().unwrap();
        let selected: Vec<_> = remedies
            .split(", ")
            .map(|selector| {
                let doc = json(&ms(
                    &dir,
                    &[
                        "diagram", "main.ms", "--view", "types", "--entity", selector, "--json",
                    ],
                ));
                let children = doc
                    .get("tree")
                    .unwrap()
                    .get("children")
                    .unwrap()
                    .as_array()
                    .unwrap();
                assert_eq!(children.len(), 1);
                children[0]
                    .get("reference")
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .to_owned()
            })
            .collect();
        assert_eq!(selected, expected);
        if name == "Item" {
            assert_eq!(remedies, "main.ms::Item, other.ms::Item");
        }
    }
    for selector in ["unique", "main.ms::unique", "main.ms#fn#unique"] {
        let doc = json(&ms(
            &dir,
            &[
                "diagram", "main.ms", "--view", "calls", "--entity", selector, "--json",
            ],
        ));
        assert_eq!(
            doc.get("tree")
                .unwrap()
                .get("children")
                .unwrap()
                .as_array()
                .unwrap()[0]
                .get("reference")
                .unwrap()
                .as_str(),
            Some("main.ms#fn#unique")
        );
    }
    let missing = ms(
        &dir,
        &[
            "diagram",
            "main.ms",
            "--entity",
            "main.ms#type#Missing",
            "--json",
        ],
    );
    assert_eq!(missing.status.code(), Some(2));
    assert!(missing.stdout.is_empty());
    let error = String::from_utf8_lossy(&missing.stderr);
    assert!(error.contains("no entity named main.ms#type#Missing"));
    assert!(error.contains("file#kind#name"), "{error}");
    let _ = std::fs::remove_dir_all(dir);
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
    std::fs::write(dir.join("main.ms"), "import arguments from \"@std/os/env.ms\"\n\nexport fn main() Int:\n    return arguments().length()\n").unwrap();
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
            .contains("@std/os/env.ms#fn#arguments")
    );
    let ascii = ms(&dir, &["diagram", "main.ms"]);
    let ascii = String::from_utf8_lossy(&ascii.stdout);
    assert_eq!(
        ascii.lines().filter(|line| line.ends_with("[fn]")).count(),
        1
    );
    assert!(ascii.contains("@std/os/env.ms#fn#arguments"));
    let mermaid = ms(&dir, &["diagram", "main.ms", "--format", "mermaid"]);
    let mermaid = String::from_utf8_lossy(&mermaid.stdout);
    assert!(mermaid.contains("arguments"));
    assert!(!mermaid.contains("HttpClient"));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn standard_methods_are_named_not_numbered() {
    let dir = scratch("std-methods");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("diagram_std_methods/main.ms"),
    )
    .unwrap();
    let outputs = [
        vec!["diagram", "main.ms"],
        vec!["diagram", "main.ms", "--format", "mermaid"],
        vec!["diagram", "main.ms", "--view", "calls"],
    ];
    for args in outputs {
        let output = ms(&dir, &args);
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(text.contains("WriteStream.write"), "{args:?}: {text}");
        assert!(!text.contains("#method#"), "{args:?}: {text}");
    }
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

#[test]
fn types_and_ownership_views_render_in_ascii_and_mermaid() {
    let dir = scratch("types");
    std::fs::write(
        dir.join("main.ms"),
        "type Item:\n    name: String\n\ntype Order:\n    items: List[Item]\n\nfn add(var o: Order, i: Item) Order:\n    return o\n",
    )
    .unwrap();
    let text = |args: &[&str]| {
        let out = ms(&dir, args);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8(out.stdout).unwrap()
    };
    let types = text(&["diagram", "main.ms", "--view", "class"]);
    assert!(
        types.contains("| items: List[Item] |\n+-------------------+\n  <>-- items --> Item\n"),
        "{types}"
    );
    assert!(
        text(&[
            "diagram", "main.ms", "--view", "types", "--format", "mermaid"
        ])
        .starts_with("classDiagram\n")
    );
    let own = text(&["diagram", "main.ms", "--view", "mutability"]);
    assert!(own.contains("add(var o: Order, i: Item) Order\n"), "{own}");
    assert!(
        text(&[
            "diagram",
            "main.ms",
            "--view",
            "ownership",
            "--format",
            "mermaid"
        ])
        .starts_with("flowchart LR\n")
    );
}

#[test]
fn overview_shows_modules_effects_and_cross_module_calls() {
    let dir = scratch("overview");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("diagram_overview/main.ms"),
    )
    .unwrap();
    std::fs::write(
        dir.join("util.ms"),
        include_str!("diagram_overview/util.ms"),
    )
    .unwrap();
    let text = |args: &[&str]| {
        let out = ms(&dir, args);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8(out.stdout).unwrap()
    };
    let ascii = text(&["diagram", "main.ms", "--view", "overview"]);
    assert!(
        ascii.contains("main.ms  [entry]") && ascii.contains("-> util.ms  (1 calls)"),
        "{ascii}"
    );
    let mermaid = text(&[
        "diagram", "main.ms", "--view", "overview", "--format", "mermaid",
    ]);
    assert!(
        mermaid.starts_with("flowchart LR\n") && mermaid.contains("|1 calls|"),
        "{mermaid}"
    );
}

#[test]
fn html_page_embeds_the_program_and_escapes_script_text() {
    let dir = scratch("html");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("diagram_overview/main.ms"),
    )
    .unwrap();
    std::fs::write(
        dir.join("util.ms"),
        include_str!("diagram_overview/util.ms"),
    )
    .unwrap();
    let out = ms(&dir, &["diagram", "main.ms", "--format", "html"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let page = String::from_utf8(out.stdout).unwrap();
    assert!(
        page.starts_with("<!doctype html>") && page.contains("\"fn\",\"double\""),
        "{page}"
    );
    assert!(!page.contains("__DATA__"));
    assert!(
        page.contains("export fn double(n: Int) Int:"),
        "source is embedded"
    );
    assert!(
        page.contains("\"t\":[[") && page.contains("\"Int\""),
        "checked identifier types are embedded"
    );
    std::fs::write(
        dir.join("change.patch"),
        include_str!("diagram_overview/change.patch"),
    )
    .unwrap();
    let diff = ms(
        &dir,
        &[
            "diagram",
            "main.ms",
            "--format",
            "html",
            "--diff",
            "change.patch",
        ],
    );
    assert!(
        diff.status.success(),
        "{}",
        String::from_utf8_lossy(&diff.stderr)
    );
    assert!(
        String::from_utf8(diff.stdout)
            .unwrap()
            .contains("\"x\":[[1,\"double\"")
    );
    let bad = ms(
        &dir,
        &["diagram", "main.ms", "--format", "html", "--view", "calls"],
    );
    assert!(!bad.status.success());
}

#[test]
fn type_relationships_follow_checked_imports_and_generic_scope() {
    let dir = scratch("checked-types");
    for (name, source) in [
        ("main.ms", include_str!("diagram_types/main.ms")),
        ("a.ms", include_str!("diagram_types/a.ms")),
        ("b.ms", include_str!("diagram_types/b.ms")),
    ] {
        std::fs::write(dir.join(name), source).unwrap();
    }
    type ExpectedSlot<'a> = (&'a str, Option<&'a str>);
    let cases: &[(&str, &[ExpectedSlot])] = &[
        (
            "main.ms#type#Box",
            &[
                ("items:", Some("a.ms#type#Item")),
                ("callback:", Some("a.ms#type#Item")),
                ("maybe:", Some("a.ms#type#Item")),
            ],
        ),
        (
            "Pick",
            &[
                ("case missing", None),
                ("case found", Some("a.ms#type#Item")),
            ],
        ),
        (
            "Reader",
            &[("read:", Some("a.ms#type#Item")), ("generic:", None)],
        ),
        (
            "echo",
            &[
                ("item:", Some("a.ms#type#Item")),
                ("returns", Some("a.ms#type#Item")),
            ],
        ),
        ("Box.first", &[("returns", Some("a.ms#type#Item"))]),
        ("Generic", &[("value:", None)]),
        ("identity", &[("item:", None), ("returns", None)]),
    ];
    for (entity, expected) in cases {
        let out = ms(
            &dir,
            &[
                "diagram", "main.ms", "--view", "types", "--entity", entity, "--json",
            ],
        );
        let doc = json(&out);
        let root = &doc
            .get("tree")
            .unwrap()
            .get("children")
            .unwrap()
            .as_array()
            .unwrap()[0];
        let slots = root.get("children").unwrap().as_array().unwrap();
        for (prefix, target) in *expected {
            let slot = slots
                .iter()
                .find(|s| {
                    s.get("label")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .starts_with(prefix)
                })
                .unwrap();
            let refs: Vec<_> = slot
                .get("children")
                .unwrap()
                .as_array()
                .unwrap()
                .iter()
                .map(|s| s.get("reference").unwrap().as_str().unwrap())
                .collect();
            assert_eq!(
                refs,
                target.iter().copied().collect::<Vec<_>>(),
                "{entity}: {prefix}"
            );
        }
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn shared_default_type_arguments_keep_one_reference_per_declaration() {
    let dir = scratch("shared-type-defaults");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("diagram_types/shared-defaults.ms"),
    )
    .unwrap();
    let doc = json(&ms(
        &dir,
        &[
            "diagram", "main.ms", "--view", "types", "--entity", "Root", "--json",
        ],
    ));
    let root = &doc
        .get("tree")
        .unwrap()
        .get("children")
        .unwrap()
        .as_array()
        .unwrap()[0];
    let slot = &root.get("children").unwrap().as_array().unwrap()[0];
    let refs: Vec<_> = slot
        .get("children")
        .unwrap()
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s.get("reference").unwrap().as_str().unwrap())
        .collect();
    assert_eq!(refs, ["main.ms#type#Pair", "main.ms#type#Item"]);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn types_mermaid_keeps_same_named_module_types_and_their_edges_distinct() {
    let dir = scratch("class-identity");
    for (name, source) in [
        ("a.ms", include_str!("diagram_class_identity/a.ms")),
        ("b.ms", include_str!("diagram_class_identity/b.ms")),
        ("main.ms", include_str!("diagram_class_identity/main.ms")),
    ] {
        std::fs::write(dir.join(name), source).unwrap();
    }
    let args = [
        "diagram", "main.ms", "--view", "types", "--format", "mermaid",
    ];
    let output = ms(&dir, &args);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    assert_eq!(output.stdout, ms(&dir, &args).stdout);
    let diagram = String::from_utf8(output.stdout).unwrap();
    let id_for = |member: &str| {
        diagram
            .split("    class ")
            .skip(1)
            .find(|block| block.split("    }\n").next().unwrap().contains(member))
            .unwrap()
            .split([' ', '['])
            .next()
            .unwrap()
    };
    let named_item = id_for("+String name");
    let counted_item = id_for("+Int count");
    assert_ne!(named_item, counted_item, "{diagram}");
    assert!(
        diagram.contains(&format!("    ABox *-- {named_item} : item\n")),
        "{diagram}"
    );
    assert!(
        diagram.contains(&format!("    BBox *-- {counted_item} : item\n")),
        "{diagram}"
    );
    assert_eq!(
        diagram
            .lines()
            .filter(|line| line.starts_with("    class "))
            .count(),
        4,
        "{diagram}"
    );
    assert_eq!(
        diagram
            .lines()
            .filter(|line| line.contains(" *-- "))
            .count(),
        2,
        "{diagram}"
    );
    let focused = ms(
        &dir,
        &[
            "diagram", "main.ms", "--view", "types", "--entity", "ABox", "--format", "mermaid",
        ],
    );
    assert!(
        focused.status.success(),
        "{}",
        String::from_utf8_lossy(&focused.stderr)
    );
    let focused = String::from_utf8(focused.stdout).unwrap();
    assert!(
        focused.contains("class Item {") && focused.contains("ABox *-- Item : item"),
        "{focused}"
    );
    assert!(
        !focused.contains("+Int count") && !focused.contains("BBox"),
        "{focused}"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn ownership_labels_follow_checked_value_classes_and_return_borrows() {
    let dir = scratch("checked-ownership");
    std::fs::write(dir.join("main.ms"), include_str!("ownership_modes/main.ms")).unwrap();
    for (entity, expected) in [
        (
            "inputs",
            vec![
                "a: Int8  copy",
                "b: Int16  copy",
                "c: Int32  copy",
                "d: Int64  copy",
                "e: Float32  copy",
                "f: Float  copy",
                "g: Int  copy",
                "h: Bool  copy",
                "i: Unit  copy",
                "j: Flag  copy",
                "k: Number  copy",
                "item: Item  borrow",
                "count: Count  borrow",
                "changed: Int  var (exclusive borrow)",
            ],
        ),
        ("item_name", vec!["returns String  borrow"]),
        ("fresh_name", vec!["returns String  owned"]),
        ("generic", vec!["value: T  borrow", "returns T  borrow"]),
        (
            "hold",
            vec!["item: Item  move", "returns List[Item]  owned"],
        ),
        ("optional_name", vec!["returns Optional[String]  borrow"]),
        ("result_name", vec!["returns Result[String, Error]  borrow"]),
        (
            "maybe_name",
            vec!["returns Result[String, Error]  owned; borrowed ok"],
        ),
        ("either", vec!["returns Result[String, Error]  borrow"]),
        ("mixed_both", vec!["returns Result[String, Error]  owned"]),
        ("Item.borrowed", vec!["returns String  borrow"]),
        (
            "Item.copied",
            vec!["value: Int8  copy", "returns Int8  owned"],
        ),
        ("named", vec!["returns Named  owned view"]),
        // An interface operation fixes no passing mode, so none is claimed.
        ("Named", vec!["label() String  self borrow"]),
        (
            "maybe_count",
            vec!["returns Result[Int, Error]  owned; borrowed error"],
        ),
        (
            "Item.boxed",
            vec!["item: Item  move", "returns List[Item]  owned"],
        ),
        (
            "ms_ownership_scalar",
            vec!["value: Int8  copy", "returns Int8  owned"],
        ),
    ] {
        let doc = json(&ms(
            &dir,
            &[
                "diagram",
                "main.ms",
                "--view",
                "ownership",
                "--entity",
                entity,
                "--json",
            ],
        ));
        let root = &doc
            .get("tree")
            .unwrap()
            .get("children")
            .unwrap()
            .as_array()
            .unwrap()[0];
        let labels: Vec<_> = root
            .get("children")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n.get("label").unwrap().as_str().unwrap())
            .collect();
        for expected in expected {
            assert!(
                labels.contains(&expected),
                "{entity}: expected {expected:?}, got {labels:?}"
            );
        }
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn ownership_mermaid_uses_the_same_checked_modes_as_json() {
    let dir = scratch("ownership-mermaid");
    std::fs::write(dir.join("main.ms"), include_str!("ownership_modes/main.ms")).unwrap();
    for (entity, expected) in [
        (
            "inputs",
            vec![
                "|\"a copy\"|",
                "|\"j copy\"|",
                "|\"item borrow\"|",
                "|\"changed var\"|",
            ],
        ),
        ("hold", vec!["|\"item move\"|", "|\"owned\"|"]),
        ("item_name", vec!["|\"borrow\"|"]),
        ("fresh_name", vec!["|\"owned\"|"]),
        ("named", vec!["|\"owned view\"|"]),
        ("maybe_name", vec!["|\"owned; borrowed ok\"|"]),
        ("maybe_count", vec!["|\"owned; borrowed error\"|"]),
        ("either", vec!["|\"borrow\"|"]),
        ("mixed_both", vec!["|\"owned\"|"]),
        ("Item.boxed", vec!["|\"item move\"|"]),
    ] {
        let out = ms(
            &dir,
            &[
                "diagram",
                "main.ms",
                "--view",
                "ownership",
                "--entity",
                entity,
                "--format",
                "mermaid",
            ],
        );
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let diagram = String::from_utf8(out.stdout).unwrap();
        for expected in expected {
            assert!(
                diagram.contains(expected),
                "{entity}: expected {expected:?} in {diagram}"
            );
        }
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_accept_git_quoted_unicode_paths() {
    let dir = scratch("quoted-diff-path");
    std::fs::write(dir.join("café.ms"), include_str!("review_quoted/head.ms")).unwrap();
    std::fs::write(
        dir.join("change.patch"),
        include_str!("review_quoted/change.patch"),
    )
    .unwrap();
    let report = json(&ms(
        &dir,
        &["review", "café.ms", "--diff", "change.patch", "--json"],
    ));
    assert_eq!(report.get("base_checked"), Some(&Json::Bool(true)));
    let findings = report.get("findings").unwrap().as_array().unwrap();
    assert_eq!(findings.len(), 1);
    assert!(report.pretty(ms_json::Escape::Plain).contains("café.ms"));
    let diagram = json(&ms(
        &dir,
        &[
            "diagram",
            "café.ms",
            "--view",
            "flow",
            "--entity",
            "value",
            "--diff",
            "change.patch",
            "--json",
        ],
    ));
    assert!(
        diagram
            .pretty(ms_json::Escape::Plain)
            .contains("CONTRACT #1")
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_reject_mismatched_added_and_deleted_sources() {
    let dir = scratch("diff-after-state");
    let head = include_str!("review_quoted/head.ms");
    std::fs::write(dir.join("main.ms"), head).unwrap();
    let added = |body: &str, start: usize| {
        format!(
            "diff --git a/main.ms b/main.ms\nnew file mode 100644\n--- /dev/null\n+++ b/main.ms\n@@ -0,0 +{start},{} @@\n{}",
            body.lines().count(),
            body.lines()
                .map(|line| format!("+{line}\n"))
                .collect::<String>()
        )
    };
    let deleted = format!(
        "diff --git a/main.ms b/main.ms\ndeleted file mode 100644\n--- a/main.ms\n+++ /dev/null\n@@ -1,{} +0,0 @@\n{}",
        head.lines().count(),
        head.lines()
            .map(|line| format!("-{line}\n"))
            .collect::<String>()
    );
    for patch in [
        added(&head.replace("new", "old"), 1),
        added(head.lines().nth(1).unwrap(), 2),
        "diff --git a/main.ms b/main.ms\nnew file mode 100644\n--- /dev/null\n+++ b/main.ms\n"
            .to_string(),
        added(head, 1).replace("main.ms", "missing.ms"),
        deleted,
    ] {
        std::fs::write(dir.join("change.patch"), patch).unwrap();
        for command in ["review", "diagram"] {
            let mut args = vec![command, "main.ms", "--diff", "change.patch", "--json"];
            if command == "diagram" {
                args.extend(["--view", "calls"]);
            }
            let output = ms(&dir, &args);
            assert_eq!(output.status.code(), Some(2), "{output:?}");
            assert!(output.stdout.is_empty());
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("diff does not match the tree")
            );
        }
    }
    std::fs::write(dir.join("change.patch"), added(head, 1)).unwrap();
    let report = json(&ms(
        &dir,
        &["review", "main.ms", "--diff", "change.patch", "--json"],
    ));
    assert_eq!(report.get("base_checked"), Some(&Json::Bool(true)));
    assert_eq!(report.get("findings").unwrap().as_array().unwrap().len(), 1);
    let _ = json(&ms(
        &dir,
        &[
            "diagram",
            "main.ms",
            "--view",
            "calls",
            "--diff",
            "change.patch",
            "--json",
        ],
    ));
    std::fs::write(dir.join("empty.ms"), "").unwrap();
    std::fs::write(dir.join("change.patch"), "diff --git a/empty.ms b/empty.ms\nnew file mode 100644\n--- /dev/null\n+++ b/empty.ms\ndiff --git a/gone.ms b/gone.ms\ndeleted file mode 100644\n--- a/gone.ms\n+++ /dev/null\n").unwrap();
    let report = json(&ms(
        &dir,
        &["review", "main.ms", "--diff", "change.patch", "--json"],
    ));
    assert_eq!(report.get("base_checked"), Some(&Json::Bool(true)));
    let _ = json(&ms(
        &dir,
        &[
            "diagram",
            "main.ms",
            "--view",
            "calls",
            "--diff",
            "change.patch",
            "--json",
        ],
    ));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn review_and_diagram_keep_in_root_two_dot_source_names() {
    let dir = scratch("review-dot-paths");
    let root = dir.join("checkout");
    std::fs::create_dir(&root).unwrap();
    for path in ["normal.ms", ".hidden.ms", "..hidden.ms", "..pkg/part.ms"] {
        let source = root.join(path);
        std::fs::create_dir_all(source.parent().unwrap()).unwrap();
        std::fs::write(&source, include_str!("review_quoted/head.ms")).unwrap();
        std::fs::write(
            root.join("main.ms"),
            include_str!("review_dot_paths/main.ms").replace("./module.ms", &format!("./{path}")),
        )
        .unwrap();
        let patch = include_str!("review_dot_paths/change.patch").replace("module.ms", path);
        std::fs::write(root.join("change.patch"), &patch).unwrap();
        let report = json(&ms(
            &root,
            &["review", "main.ms", "--diff", "change.patch", "--json"],
        ));
        assert_eq!(
            report.get("input").and_then(Json::as_str),
            Some("diff (1 files, 1 source, +2 -2)"),
            "{path}"
        );
        assert_eq!(
            report.get("findings").unwrap().as_array().unwrap().len(),
            1,
            "{path}"
        );
        let diagram = json(&ms(
            &root,
            &[
                "diagram",
                "main.ms",
                "--diff",
                "change.patch",
                "--view",
                "calls",
                "--json",
            ],
        ));
        assert!(
            diagram
                .pretty(ms_json::Escape::Plain)
                .contains("CONTRACT #1"),
            "{path}: {diagram:?}"
        );
        std::fs::write(
            root.join("change.patch"),
            patch.replace("return \"new\"", "return \"absent\""),
        )
        .unwrap();
        for command in ["review", "diagram"] {
            let output = ms(
                &root,
                &[command, "main.ms", "--diff", "change.patch", "--json"],
            );
            assert_eq!(output.status.code(), Some(2), "{path}: {output:?}");
            assert!(output.stdout.is_empty());
        }
    }
    std::fs::write(dir.join("outside.ms"), "outside tree control\n").unwrap();
    std::fs::write(
        root.join("change.patch"),
        "--- a/../outside.ms\n+++ b/../outside.ms\n@@ -1 +1 @@\n-old\n+unmatched\n",
    )
    .unwrap();
    let report = json(&ms(
        &root,
        &["review", "main.ms", "--diff", "change.patch", "--json"],
    ));
    assert_eq!(
        report.get("input").and_then(Json::as_str),
        Some("diff (1 files, 0 source, +1 -1)")
    );
    assert!(
        report
            .get("findings")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
    let diagram = json(&ms(
        &root,
        &[
            "diagram",
            "main.ms",
            "--diff",
            "change.patch",
            "--view",
            "calls",
            "--json",
        ],
    ));
    assert!(
        !diagram
            .pretty(ms_json::Escape::Plain)
            .contains("CONTRACT #1")
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn ownership_view_shows_receiver_modes_and_interface_operations() {
    let dir = scratch("ownership-receivers");
    std::fs::write(
        dir.join("main.ms"),
        include_str!("ownership_receivers/main.ms"),
    )
    .unwrap();
    for (entity, expected) in [
        ("Counter.bump", "self  var (exclusive borrow)"),
        ("Counter.read", "self  borrow"),
        ("Shape", "area() Int  self borrow"),
        ("Shape", "grow(by: Int) Unit  self var (exclusive borrow)"),
    ] {
        let doc = json(&ms(
            &dir,
            &[
                "diagram",
                "main.ms",
                "--view",
                "ownership",
                "--entity",
                entity,
                "--json",
            ],
        ));
        let root = &doc
            .get("tree")
            .unwrap()
            .get("children")
            .unwrap()
            .as_array()
            .unwrap()[0];
        let labels: Vec<_> = root
            .get("children")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n.get("label").unwrap().as_str().unwrap())
            .collect();
        assert!(
            labels.contains(&expected),
            "{entity}: expected {expected:?}, got {labels:?}"
        );
    }
    let out = ms(
        &dir,
        &[
            "diagram",
            "main.ms",
            "--view",
            "ownership",
            "--entity",
            "Counter.bump",
        ],
    );
    assert!(
        String::from_utf8(out.stdout)
            .unwrap()
            .contains("bump(var self)")
    );
    let _ = std::fs::remove_dir_all(dir);
}

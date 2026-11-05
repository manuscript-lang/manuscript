//! Review and diagram must be usable through the installed CLI surface.

mod common;

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
        ("Box", vec!["main.ms#impl#Box", "main.ms#record#Box"]),
        (
            "main.ms::Box",
            vec!["main.ms#impl#Box", "main.ms#record#Box"],
        ),
        ("Item", vec!["main.ms#record#Item", "other.ms#record#Item"]),
        (
            "Named",
            vec!["main.ms#record#Named", "other.ms#record#Named"],
        ),
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
            "main.ms#record#Missing",
            "--json",
        ],
    );
    assert_eq!(missing.status.code(), Some(2));
    assert!(missing.stdout.is_empty());
    let error = String::from_utf8_lossy(&missing.stderr);
    assert!(error.contains("no entity named main.ms#record#Missing"));
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
    std::fs::write(dir.join("main.ms"), "import arguments from \"@std/os/process.ms\"\n\nexport fn main() Int:\n    return arguments().length()\n").unwrap();
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
            .contains("@std/os/process.ms#fn#arguments")
    );
    let ascii = ms(&dir, &["diagram", "main.ms"]);
    let ascii = String::from_utf8_lossy(&ascii.stdout);
    assert_eq!(
        ascii.lines().filter(|line| line.ends_with("[fn]")).count(),
        1
    );
    assert!(ascii.contains("@std/os/process.ms#fn#arguments"));
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
            "main.ms#record#Box",
            &[
                ("items:", Some("a.ms#record#Item")),
                ("callback:", Some("a.ms#record#Item")),
                ("maybe:", Some("a.ms#record#Item")),
            ],
        ),
        (
            "Pick",
            &[
                ("case missing", None),
                ("case found", Some("a.ms#record#Item")),
            ],
        ),
        (
            "Reader",
            &[("read:", Some("a.ms#record#Item")), ("generic:", None)],
        ),
        (
            "echo",
            &[
                ("item:", Some("a.ms#record#Item")),
                ("returns", Some("a.ms#record#Item")),
            ],
        ),
        ("Box.first", &[("returns", Some("a.ms#record#Item"))]),
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
    assert_eq!(refs, ["main.ms#record#Pair", "main.ms#record#Item"]);
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

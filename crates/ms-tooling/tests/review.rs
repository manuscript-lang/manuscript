//! Behavior of the diff parser, review ranking, report rendering and views
//! over hand-built fact models. Differential coverage against `ms`
//! lives in `tests/differential.rs`.

use ms_tooling::diff::{parse_diff, removed_content, reverse_apply};
use ms_tooling::facts::{Fact, Facts, fact_key};
use ms_tooling::mark::{explain, explain_json, mark_changes};
use ms_tooling::report::{ReviewOptions, diff_report, project_report};
use ms_tooling::review::{DiffInput, TIER_EFFECT, compare_facts};
use ms_tooling::tree::Node;
use ms_tooling::views::build_view;
use std::collections::BTreeMap;

const SAMPLE_DIFF: &str = "diff --git a/src/a.ms b/src/a.ms
index 111..222 100644
--- a/src/a.ms
+++ b/src/a.ms
@@ -1,4 +1,5 @@
 def one() -> Int:
-    return 1
+    let x = 1
+    return x
 
 def two() -> Int:
diff --git a/new.ms b/new.ms
new file mode 100644
--- /dev/null
+++ b/new.ms
@@ -0,0 +1,2 @@
+def n() -> Int:
+    return 0
";

#[test]
fn parse_diff_and_reverse_apply() {
    let files = parse_diff(SAMPLE_DIFF).unwrap();
    assert_eq!(files.len(), 2);
    assert_eq!(files[0].path(), "src/a.ms");
    assert!(files[1].old.is_empty() && files[1].new == "new.ms");
    let head =
        "def one() -> Int:\n    let x = 1\n    return x\n\ndef two() -> Int:\n    return 2\n";
    let base = reverse_apply(head, &files[0].hunks).unwrap();
    assert_eq!(
        base,
        "def one() -> Int:\n    return 1\n\ndef two() -> Int:\n    return 2\n"
    );
    assert_eq!(files[0].touched_lines(), vec![2, 2, 3]);
    let wrong = head.replacen("let x = 1", "let x = 9", 1);
    assert!(reverse_apply(&wrong, &files[0].hunks).is_err());
}

#[test]
fn parse_diff_rejects_renames() {
    let err = parse_diff(
        "diff --git a/a.ms b/b.ms\nsimilarity index 100%\nrename from a.ms\nrename to b.ms\n",
    )
    .unwrap_err();
    assert!(err.contains("--no-renames"), "{err}");
}

#[test]
fn parse_diff_rejects_text_that_is_not_a_diff() {
    let err = parse_diff("garbage\n").unwrap_err();
    assert!(err.contains("not a unified diff"), "{err}");
    assert!(parse_diff("").unwrap().is_empty());
}

#[test]
fn removed_content_is_base_text() {
    let files = parse_diff(
        "--- a/gone.ms\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-def a() -> Int:\n-    return 0\n",
    )
    .unwrap();
    assert!(files[0].new.is_empty());
    assert_eq!(
        removed_content(&files[0].hunks),
        "def a() -> Int:\n    return 0\n"
    );
}

#[test]
fn malformed_hunks_are_reported_with_lines() {
    assert_eq!(
        parse_diff("--- a\n+++ b\n@@ -x +1 @@\n").unwrap_err(),
        "diff line 3: malformed hunk range \"x\""
    );
    assert_eq!(
        parse_diff("--- a\n+++ a\n@@ -1 +1\n").unwrap_err(),
        "diff line 3: malformed hunk header"
    );
    assert_eq!(
        parse_diff("--- a\n+++ a\n@@ -1,2 +1,2 @@\n x").unwrap_err(),
        "diff line 3: hunk is shorter than its header declares"
    );
    assert_eq!(
        parse_diff("@@ -1 +1 @@\n").unwrap_err(),
        "diff line 1: hunk before any file header"
    );
}

fn fact(file: &str, kind: &str, name: &str, line: usize) -> Fact {
    Fact {
        key: fact_key(file, kind, name),
        file: file.into(),
        kind: kind.into(),
        name: name.into(),
        ty: "fn() Int".into(),
        line,
        first: line,
        last: line + 1,
        ..Fact::default()
    }
}

fn facts_of(list: Vec<Fact>) -> Facts {
    let mut facts = Facts::default();
    for f in list {
        facts.entities.insert(f.key.clone(), f);
    }
    facts
}

fn program(add_effect: bool) -> Facts {
    let mut say = fact("r.ms", "fn", "say", 3);
    say.effects = vec!["io".into()];
    say.external = vec!["@std/io.ms#stdout".into()];
    let mut add = fact("r.ms", "fn", "add", 7);
    let mut run = fact("r.ms", "fn", "run", 10);
    run.exported = true;
    run.calls = vec![add.key.clone()];
    if add_effect {
        add.effects = vec!["io".into()];
        add.calls = vec![say.key.clone()];
        run.effects = vec!["io".into()];
    }
    facts_of(vec![say, add, run])
}

fn input(touched: &[i64]) -> DiffInput {
    DiffInput {
        files: 1,
        sources: 1,
        touched: BTreeMap::from([("r.ms".to_string(), touched.to_vec())]),
        base_checked: true,
        ..DiffInput::default()
    }
}

#[test]
fn effect_gain_ranks_through_callers() {
    let (base, head) = (program(false), program(true));
    let findings = compare_facts(&base, &head, &input(&[8]));
    assert_eq!(findings[0].tier, TIER_EFFECT);
    assert_eq!(findings.len(), 2);
    let text = diff_report(&base, &head, &input(&[8]), ReviewOptions::default()).render("ascii");
    for want in [
        "EFFECT+",
        "effects: none -> io",
        "path: add -> say -> @std/io.ms#stdout",
    ] {
        assert!(text.contains(want), "lacks {want:?}:\n{text}");
    }
}

#[test]
fn review_reach_counts_distinct_callers_across_cycles() {
    let mut entry = fact("r.ms", "fn", "entry", 1);
    let mut left = fact("r.ms", "fn", "left", 3);
    let mut right = fact("r.ms", "fn", "right", 5);
    let mut target = fact("r.ms", "fn", "target", 7);
    let unrelated = fact("r.ms", "fn", "unrelated", 9);
    entry.calls = vec![left.key.clone(), right.key.clone()];
    left.calls = vec![target.key.clone(), target.key.clone()];
    right.calls = vec![target.key.clone()];
    target.calls = vec![left.key.clone(), target.key.clone()];
    target.exported = true;
    let base = facts_of(vec![entry, left, right, target, unrelated]);
    let mut head = base.clone();
    head.entities
        .get_mut(&fact_key("r.ms", "fn", "target"))
        .unwrap()
        .ty = "fn() String".into();
    head.entities
        .get_mut(&fact_key("r.ms", "fn", "left"))
        .unwrap()
        .scopes = 1;

    // The right branch has one caller, but a body-only edit gets no reach bonus.
    let findings = compare_facts(&base, &head, &input(&[6]));
    let scores: Vec<_> = findings
        .iter()
        .map(|f| {
            (
                f.entity.as_str(),
                f.tier.as_str(),
                f.reach,
                f.score,
                f.terms.iter().map(String::as_str).collect::<Vec<_>>(),
            )
        })
        .collect();
    assert_eq!(
        scores,
        vec![
            (
                "target",
                "CONTRACT",
                3,
                15,
                vec!["contract +8", "reach(3) +4", "exported +3"],
            ),
            ("left", "RESOURCE", 3, 8, vec!["resource +4", "reach(3) +4"]),
            ("right", "INTERNAL", 0, 0, vec![]),
        ]
    );
}

#[test]
fn body_edit_is_internal_only() {
    let base = program(false);
    let report = diff_report(&base, &base, &input(&[8]), ReviewOptions::default());
    assert_eq!(report.result, "0 need attention, 1 internal");
    let none = diff_report(&base, &base, &input(&[]), ReviewOptions::default());
    assert_eq!(none.result, "no tracked semantic changes");
}

#[test]
fn report_is_stable_and_capped() {
    let mut base = Facts::default();
    let mut head = Facts::default();
    for i in 0..8 {
        let name = format!("f{i}");
        let mut b = fact("r.ms", "fn", &name, i + 1);
        b.exported = true;
        let mut h = b.clone();
        h.ty = "fn() String".into();
        base.entities.insert(b.key.clone(), b);
        head.entities.insert(h.key.clone(), h);
    }
    let input = input(&[]);
    let capped = diff_report(&base, &head, &input, ReviewOptions::default());
    assert!(capped.render("ascii").contains("+3 more (use --all)"));
    let all = diff_report(&base, &head, &input, ReviewOptions { all: true });
    assert!(!all.render("ascii").contains("more (use --all)"));
    for format in ["ascii", "markdown", "json"] {
        assert_eq!(
            capped.render(format),
            diff_report(&base, &head, &input, ReviewOptions::default()).render(format)
        );
    }
    assert!(capped.digest.starts_with("sha256:") && capped.digest.len() == 71);
}

#[test]
fn project_report_maps_surface() {
    let text = project_report(&program(true), ReviewOptions::default()).render("ascii");
    assert!(
        text.contains("PUBLIC SURFACE") && text.contains("run") && text.contains("1. SUMMARY"),
        "{text}"
    );
}

#[test]
fn views_answer_one_question_each() {
    let facts = program(true);
    let effects = build_view(&facts, "effects", "say", 0).unwrap().ascii();
    assert!(
        effects.contains("EFFECTS VIEW") && effects.contains("`- say  effects: io"),
        "{effects}"
    );
    assert!(effects.contains("@std/io.ms#stdout"));
    let calls = build_view(&facts, "calls", "run", 0).unwrap().ascii();
    assert!(
        calls.contains("run  [fn] r.ms:10") && calls.contains("add  [fn]"),
        "{calls}"
    );
    assert!(
        build_view(&facts, "calls", "missing", 0)
            .unwrap_err()
            .contains("no entity named missing")
    );
}

#[test]
fn cycle_and_depth() {
    let mut a = fact("r.ms", "fn", "a", 1);
    let mut b = fact("r.ms", "fn", "b", 4);
    a.calls = vec![b.key.clone()];
    b.calls = vec![a.key.clone()];
    let facts = facts_of(vec![a, b]);
    let unscoped = build_view(&facts, "calls", "", 5).unwrap().ascii();
    assert!(unscoped.contains("a  (cycle)"), "{unscoped}");
    let deep = build_view(&facts, "calls", "a", 5).unwrap();
    assert!(deep.ascii().contains("a  (cycle)"));
    assert!(deep.mermaid().starts_with("flowchart TD\n    n0[\""));
    let shallow = build_view(&facts, "calls", "a", 1).unwrap().ascii();
    assert!(!shallow.contains("(cycle)") && shallow.contains("b  [fn]"));
}

#[test]
fn unscoped_views_include_disconnected_cycles_and_test_entrypoints() {
    let main = fact("r.ms", "fn", "main", 1);
    let mut recursive = fact("r.ms", "fn", "recursive", 4);
    recursive.calls = vec![recursive.key.clone()];
    let test = fact("r.ms", "test", "works", 8);
    let facts = facts_of(vec![main, recursive, test]);
    let tree = build_view(&facts, "calls", "", 3).unwrap();
    let text = tree.ascii();
    for name in [
        "main  [fn]",
        "recursive  [fn]",
        "recursive  (cycle)",
        "works  [test]",
    ] {
        assert!(text.contains(name), "{text}");
    }
}

#[test]
fn view_cap_includes_roots_and_cycle_leaves() {
    let facts = facts_of(
        (0..250)
            .map(|n| fact("r.ms", "fn", &format!("f{n:03}"), n + 1))
            .collect(),
    );
    let tree = build_view(&facts, "calls", "", 3).unwrap();
    assert_eq!(tree.children.len(), 201);
    assert!(
        tree.ascii()
            .contains("+50 more (output capped at 200 nodes)")
    );
    assert_eq!(tree.omitted, 50);
    let mut root = fact("r.ms", "fn", "a", 1);
    let mut children: Vec<Fact> = (0..250)
        .map(|n| {
            let mut f = fact("r.ms", "fn", &format!("f{n:03}"), n + 2);
            f.calls = vec![root.key.clone()];
            f
        })
        .collect();
    root.calls = children.iter().map(|f| f.key.clone()).collect();
    children.push(root);
    let tree = build_view(&facts_of(children), "calls", "a", 3).unwrap();
    fn nodes(n: &Node) -> usize {
        1 + n.children.iter().map(nodes).sum::<usize>()
    }
    assert_eq!(nodes(&tree), 202); // title, 200 nodes, omitted summary
}

#[test]
fn modules_include_leaf_files_and_bound_large_projects() {
    let facts = Facts {
        imports: (0..250)
            .map(|n| (format!("src/f{n:03}.ms"), vec![]))
            .collect(),
        ..Facts::default()
    };
    let tree = build_view(&facts, "modules", "", 0).unwrap();
    assert_eq!(tree.omitted, 50);
    assert_eq!(tree.children[0].file, "src/f000.ms");
    let leaf = build_view(&facts, "modules", "src/f249.ms", 0).unwrap();
    assert!(leaf.ascii().contains("src/f249.ms"));
    assert_eq!(leaf.omitted, 0);
}

#[test]
fn explanation_uses_stable_identity_and_handles_removed_entities() {
    let (base, head) = (program(false), program(true));
    let findings = compare_facts(&base, &head, &input(&[8]));
    let json = explain_json(&findings, &head, "1").unwrap();
    let id = json
        .get("finding")
        .unwrap()
        .get("id")
        .unwrap()
        .as_str()
        .unwrap();
    assert_eq!(
        json.get("diagram").unwrap().get("entity").unwrap().as_str(),
        Some(id)
    );
    assert!(
        explain(&findings, &head, "1")
            .unwrap()
            .contains(&format!("--entity '{id}'"))
    );

    let removed = compare_facts(&head, &Facts::default(), &input(&[]));
    let explanation = explain_json(&removed, &Facts::default(), "1").unwrap();
    assert_eq!(explanation.get("diagram"), Some(&ms_json::Json::Null));
    assert!(
        !explain(&removed, &Facts::default(), "1")
            .unwrap()
            .contains("ms diagram")
    );
}

#[test]
fn ambiguous_finding_names_need_a_number_or_id() {
    let facts = facts_of(vec![
        fact("a.ms", "fn", "same", 1),
        fact("b.ms", "fn", "same", 1),
    ]);
    let findings = compare_facts(&Facts::default(), &facts, &input(&[]));
    assert!(
        explain(&findings, &facts, "same")
            .unwrap_err()
            .contains("ambiguous")
    );
    assert!(explain(&findings, &facts, "a.ms#fn#same").is_ok());
}

#[test]
fn flow_view_expands_calls_and_scope_prunes() {
    let mut main = fact("r.ms", "fn", "main", 15);
    let mut guarded = fact("r.ms", "fn", "guarded", 8);
    let call = Node {
        kind: "call".into(),
        label: "call guarded".into(),
        reference: guarded.key.clone(),
        ..Node::default()
    };
    let with = Node {
        kind: "scope".into(),
        label: "let out = stdout()  [closed on exit]".into(),
        children: vec![
            Node {
                kind: "native".into(),
                label: "native @std/io.ms#stdout".into(),
                ..Node::default()
            },
            Node {
                kind: "try".into(),
                label: "try call load".into(),
                ..Node::default()
            },
        ],
        ..Node::default()
    };
    main.calls = vec![guarded.key.clone()];
    guarded.scopes = 1;
    let mut facts = facts_of(vec![main.clone(), guarded.clone()]);
    facts.flows.insert(main.key.clone(), vec![call]);
    facts.flows.insert(guarded.key.clone(), vec![with]);
    let flow = build_view(&facts, "flow", "main", 2).unwrap().ascii();
    let want = "FLOW VIEW\n`- main  [fn] r.ms:15\n   `- call guarded\n      `- let out = stdout()  [closed on exit]\n         |- native @std/io.ms#stdout\n         `- try call load\n";
    assert_eq!(flow, want);
    let scope = build_view(&facts, "scope", "guarded", 0).unwrap().ascii();
    assert_eq!(
        scope,
        "SCOPE VIEW\n`- guarded  [fn] r.ms:8\n   `- let out = stdout()  [closed on exit]\n      `- try call load\n"
    );
    assert!(
        build_view(&facts, "flow", "", 0)
            .unwrap_err()
            .contains("needs --entity")
    );
}

#[test]
fn tasks_view_keeps_groups_and_spawned_work() {
    let load = fact("r.ms", "fn", "load", 3);
    let spawn = Node {
        kind: "spawn".into(),
        label: "spawn  group.spawn(lambda: fetch(1))".into(),
        children: vec![Node {
            kind: "call".into(),
            label: "call fetch".into(),
            ..Node::default()
        }],
        ..Node::default()
    };
    let with = Node {
        kind: "scope".into(),
        label: "let group = TaskGroup[Int]()  [closed on exit]".into(),
        children: vec![
            spawn,
            Node {
                kind: "call".into(),
                label: "call TaskGroup.results".into(),
                ..Node::default()
            },
        ],
        ..Node::default()
    };
    let other = Node {
        kind: "call".into(),
        label: "call unrelated".into(),
        ..Node::default()
    };
    let mut facts = facts_of(vec![load.clone()]);
    facts.flows.insert(load.key.clone(), vec![other, with]);
    let tasks = build_view(&facts, "tasks", "load", 0).unwrap().ascii();
    assert_eq!(
        tasks,
        "TASKS VIEW\n`- load  [fn] r.ms:3\n   `- let group = TaskGroup[Int]()  [closed on exit]\n      `- spawn  group.spawn(lambda: fetch(1))\n         `- call fetch\n"
    );
}

#[test]
fn mark_and_explain() {
    let (base, head) = (program(false), program(true));
    let findings = compare_facts(&base, &head, &input(&[8]));
    let mut tree = build_view(&head, "calls", "run", 0).unwrap();
    mark_changes(&mut tree, &findings, &BTreeMap::new());
    assert!(tree.ascii().contains("<- EFFECT+ #"), "{}", tree.ascii());
    let text = explain(&findings, &head, "1").unwrap();
    assert!(
        text.starts_with("EXPLAIN #1 ") && text.contains("\nCALLERS\n"),
        "{text}"
    );
    assert!(
        explain(&findings, &head, "9")
            .unwrap_err()
            .starts_with("no finding 9;")
    );
}

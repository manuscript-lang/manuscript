//! Behavior of the diff parser, review ranking, report rendering and views
//! over hand-built fact models. Differential coverage against `ms`
//! lives in `tests/differential.rs`.

use ms_tooling::diff::{parse_diff, removed_content, reverse_apply};
use ms_tooling::facts::{Fact, Facts, fact_key};
use ms_tooling::mark::{explain, explain_json, mark_changes};
use ms_tooling::report::{ReviewOptions, diff_report, project_report};
use ms_tooling::review::{DiffInput, TIER_EFFECT, compare_facts};
use ms_tooling::tree::Node;
use ms_tooling::views::{NODE_CAP, build_view, find_entity, mermaid_view};
use std::collections::BTreeMap;

const SAMPLE_DIFF: &str = "diff --git a/src/a.ms b/src/a.ms\nindex 111..222 100644\n--- a/src/a.ms\n+++ b/src/a.ms\n@@ -1,4 +1,5 @@\n fn one() Int:\n-    return 1\n+    x := 1\n+    return x\n \n fn two() Int:\ndiff --git a/new.ms b/new.ms\nnew file mode 100644\n--- /dev/null\n+++ b/new.ms\n@@ -0,0 +1,2 @@\n+fn n() Int:\n+    return 0\n";

#[test]
fn git_metadata_only_sections_preserve_path_identity() {
    for (old, new, path) in [
        ("a/main.ms", "b/main.ms", "main.ms"),
        ("a/a b/name .ms", "b/a b/name .ms", "a b/name .ms"),
        ("a/café.ms", "b/café.ms", "café.ms"),
        (r#""a/caf\303\251.ms""#, r#""b/caf\303\251.ms""#, "café.ms"),
        (
            r#""a/quote\"tab\t.ms""#,
            r#""b/quote\"tab\t.ms""#,
            "quote\"tab\t.ms",
        ),
    ] {
        let patch = format!("diff --git {old} {new}\nold mode 100644\nnew mode 100755\n");
        let files = parse_diff(&patch).unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].old, path);
        assert_eq!(files[0].new, path);
        assert!(files[0].hunks.is_empty());
        assert!(files[0].touched_lines().is_empty());
        assert_eq!(
            reverse_apply("unchanged\n", &files[0].hunks).unwrap(),
            "unchanged\n"
        );
    }
}

#[test]
fn git_metadata_only_empty_files_keep_the_absent_side() {
    let patch = "diff --git a/empty.ms b/empty.ms\nnew file mode 100644\nindex 0000000..e69de29\ndiff --git a/gone.ms b/gone.ms\ndeleted file mode 100644\nindex e69de29..0000000\n";
    let files = parse_diff(patch).unwrap();
    assert_eq!(files.len(), 2);
    assert!(files[0].old.is_empty());
    assert_eq!(files[0].new, "empty.ms");
    assert_eq!(files[1].old, "gone.ms");
    assert!(files[1].new.is_empty());
    assert_eq!(removed_content(&files[1].hunks), "");
}

#[test]
fn git_text_headers_still_override_section_fallback_paths() {
    let patch = "diff --git a/ignored.ms b/ignored.ms\nold mode 100644\nnew mode 100755\n--- a/actual.ms\n+++ b/actual.ms\n@@ -1 +1 @@\n-old\n+new\n";
    let files = parse_diff(patch).unwrap();
    assert_eq!(files[0].path(), "actual.ms");
    assert_eq!(reverse_apply("new\n", &files[0].hunks).unwrap(), "old\n");
}

#[test]
fn git_binary_metadata_stays_rejected_without_inventing_text_changes() {
    for metadata in [
        "Binary files a/image.png and b/image.png differ",
        "GIT binary patch",
    ] {
        let patch =
            format!("diff --git a/image.png b/image.png\nnew file mode 100644\n{metadata}\n");
        assert!(
            parse_diff(&patch)
                .unwrap_err()
                .contains("git diff --text --no-renames")
        );
    }
    assert!(parse_diff("diff --git a/x.ms b/x.ms\n").is_err());
    assert!(parse_diff("diff --git a/x.ms b/x.ms\n+missing hunk header\n").is_err());
}

#[test]
fn parse_diff_and_reverse_apply() {
    let files = parse_diff(SAMPLE_DIFF).unwrap();
    assert_eq!(files.len(), 2);
    assert_eq!(files[0].path(), "src/a.ms");
    assert!(files[1].old.is_empty() && files[1].new == "new.ms");
    let head = "fn one() Int:\n    x := 1\n    return x\n\nfn two() Int:\n    return 2\n";
    let base = reverse_apply(head, &files[0].hunks).unwrap();
    assert_eq!(
        base,
        "fn one() Int:\n    return 1\n\nfn two() Int:\n    return 2\n"
    );
    assert_eq!(files[0].touched_lines(), vec![2, 2, 3]);
    let wrong = head.replacen("x := 1", "x := 9", 1);
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
    let files =
        parse_diff("--- a/gone.ms\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-fn a() Int:\n-    return 0\n")
            .unwrap();
    assert!(files[0].new.is_empty());
    assert_eq!(
        removed_content(&files[0].hunks),
        "fn a() Int:\n    return 0\n"
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

#[test]
fn hunk_ranges_reject_signed_impossible_and_overflowing_coordinates() {
    for range in [
        "-1",
        "+1",
        "1,-1",
        "1,+1",
        "0",
        "0,1",
        "-9223372036854775808",
        "9223372036854775807",
        "9223372036854775807,0",
        "9223372036854775806,2",
    ] {
        for (old, new) in [(range, "1"), ("1", range)] {
            let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -{old} +{new} @@\n-old\n+new\n");
            let error = parse_diff(&patch).expect_err(&patch);
            assert!(
                error.starts_with("diff line 3: malformed hunk range"),
                "{error}"
            );
        }
    }
}

#[test]
fn hunk_ranges_keep_zero_length_and_safe_extreme_boundaries() {
    for (old, new, body, head, base, touched) in [
        ("0,0", "1", "+new\n", "new\n", "", vec![1]),
        ("1", "0,0", "-old\n", "", "old\n", vec![1]),
        ("1,0", "2", "+new\n", "same\nnew\n", "same\n", vec![2]),
    ] {
        let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -{old} +{new} @@\n{body}");
        let files = parse_diff(&patch).unwrap();
        assert_eq!(files[0].touched_lines(), touched);
        assert_eq!(reverse_apply(head, &files[0].hunks).unwrap(), base);
    }
    for (old, new, body) in [
        ("9223372036854775806", "9223372036854775806", "-old\n+new\n"),
        ("9223372036854775806,0", "9223372036854775806,0", ""),
    ] {
        let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -{old} +{new} @@\n{body}");
        let files = parse_diff(&patch).unwrap();
        let _ = files[0].touched_lines();
        let _ = reverse_apply("new\n", &files[0].hunks);
    }
}

#[test]
fn hunk_structure_rejects_surplus_body_lines() {
    for extra in ["+extra\n", "-extra\n", " extra\n", "\n+extra\n"] {
        let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n{extra}");
        assert!(parse_diff(&patch).is_err(), "{patch}");
    }
    let repeated = "diff --git a/x.ms b/x.ms\n--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n--- a/x.ms\n+++ b/x.ms\n";
    assert!(parse_diff(repeated).is_err());
}

#[test]
fn hunk_structure_checks_old_coordinates_and_keeps_patch_boundaries() {
    for (old, new, body, head) in [
        ("5", "1", "-old\n+new\n", "new\n"),
        ("200", "0,0", "-old\n", ""),
        ("1", "4,0", "-old\n", ""),
        ("1,0", "1", "+new\n", "new\n"),
        ("1", "2", "-old\n+new\n", "keep\nnew\n"),
    ] {
        let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -{old} +{new} @@\n{body}");
        let files = parse_diff(&patch).unwrap();
        assert!(reverse_apply(head, &files[0].hunks).is_err(), "{patch}");
    }
    let first = "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n";
    let second = "--- a/y.ms\n+++ b/y.ms\n@@ -1 +1 @@\n-before\n+after\n";
    assert_eq!(parse_diff(&format!("{first}{second}")).unwrap().len(), 2);
    let files = parse_diff(&format!("{first}-- \n2.51.0\n")).unwrap();
    assert_eq!(reverse_apply("new\n", &files[0].hunks).unwrap(), "old\n");
    let mail_stream = format!(
        "{first}-- \n+signature\n signer\n-next\nFrom next-message\nSubject: another change\ndiff --git a/y.ms b/y.ms\n{second}-- \n+second signature\n"
    );
    let files = parse_diff(&mail_stream).unwrap();
    assert_eq!(files.len(), 2);
    assert_eq!(reverse_apply("new\n", &files[0].hunks).unwrap(), "old\n");
    assert_eq!(
        reverse_apply("after\n", &files[1].hunks).unwrap(),
        "before\n"
    );
    let files = parse_diff(include_str!("review_diff/mail_without_signatures.patch")).unwrap();
    assert_eq!(files.len(), 2);
    assert_eq!((files[0].path(), files[1].path()), ("x.ms", "y.ms"));
    let multiple =
        "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old_a\n+new_a\n@@ -3 +3 @@\n-old_b\n+new_b\n";
    let files = parse_diff(multiple).unwrap();
    assert_eq!(
        reverse_apply("new_a\nkeep\nnew_b\n", &files[0].hunks).unwrap(),
        "old_a\nkeep\nold_b\n"
    );
    let grows = "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1,2 @@\n-old_a\n+new_a\n+extra\n@@ -3 +4 @@\n-old_b\n+new_b\n";
    let files = parse_diff(grows).unwrap();
    assert_eq!(
        reverse_apply("new_a\nextra\nkeep\nnew_b\n", &files[0].hunks).unwrap(),
        "old_a\nkeep\nold_b\n"
    );
}

#[test]
fn hunk_structure_retains_each_sides_eof_across_split_hunks() {
    let split = "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n@@ -1,0 +2 @@\n+extra\n";
    let files = parse_diff(split).unwrap();
    assert_eq!(
        reverse_apply("new\nextra\n", &files[0].hunks).unwrap(),
        "old"
    );
    let split = "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n@@ -2 +1,0 @@\n-extra\n";
    let files = parse_diff(split).unwrap();
    assert_eq!(
        reverse_apply("new", &files[0].hunks).unwrap(),
        "old\nextra\n"
    );
    let premature = "--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n-old_a\n\\ No newline at end of file\n-old_b\n+new_a\n+new_b\n";
    assert!(parse_diff(premature).is_err());
    let before_tail =
        "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n";
    let files = parse_diff(before_tail).unwrap();
    assert!(reverse_apply("new\nuntouched\n", &files[0].hunks).is_err());
}

#[test]
fn diff_eof_terminators_are_not_context_lines() {
    for newline in ["\n", "\r\n"] {
        for ending in ["", "\n"] {
            let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n same{ending}")
                .replace('\n', newline);
            assert_eq!(
                parse_diff(&patch).unwrap_err(),
                "diff line 3: hunk is shorter than its header declares"
            );
        }
        // A genuine empty context line still exists, with or without its
        // conventional space prefix. Do not trim it along with the terminator.
        for blank in [" \n", "\n"] {
            let patch = format!("--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n same\n{blank}")
                .replace('\n', newline);
            let files = parse_diff(&patch).unwrap();
            assert_eq!(files[0].hunks[0].lines, [" same", " "]);
            assert_eq!(
                reverse_apply("same\n\n", &files[0].hunks).unwrap(),
                "same\n\n"
            );
        }
    }
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
    say.external = vec!["@std/io/io.ms#stdout".into()];
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
        "path: add -> say -> @std/io/io.ms#stdout",
    ] {
        assert!(text.contains(want), "lacks {want:?}:\n{text}");
    }
}

fn declared_program(permit: bool, reach: bool) -> Facts {
    let mut connect = fact("r.ms", "fn", "connect", 3);
    let mut save = fact("r.ms", "fn", "save", 7);
    save.calls = vec![connect.key.clone()];
    if reach {
        connect.reach = vec!["std.net.connect".into()];
        save.reach = vec!["std.net.connect".into()];
    }
    if permit {
        save.permits = vec!["std.net.*".into()];
    }
    facts_of(vec![connect, save])
}

#[test]
fn new_permission_and_new_reach_are_effect_findings_and_permission_ranks_first() {
    let base = declared_program(false, false);
    let head = declared_program(true, true);
    let findings = compare_facts(&base, &head, &input(&[8]));
    let save = findings
        .iter()
        .find(|f| f.changes.iter().any(|c| c.starts_with("permits:")))
        .expect("permission finding");
    assert_eq!(save.tier, TIER_EFFECT);
    assert_eq!(save.changes[0], "permits: + std.net.*");
    assert!(
        save.changes
            .iter()
            .any(|c| c == "reaches: + std.net.connect")
    );
    assert!(
        save.evidence.iter().any(|e| e == "path: save -> connect"),
        "{:?}",
        save.evidence
    );
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
    let all = diff_report(
        &base,
        &head,
        &input,
        ReviewOptions {
            all: true,
            ..ReviewOptions::default()
        },
    );
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
    assert!(effects.contains("@std/io/io.ms#stdout"));
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
fn ambiguous_entity_remedies_select_distinct_declarations() {
    let facts = facts_of(vec![
        fact("main.ms", "type", "Box", 1),
        fact("main.ms", "impl", "Box", 4),
        fact("other.ms", "type", "Box", 1),
    ]);
    for name in ["Box", "main.ms::Box"] {
        let error = find_entity(&facts, name).unwrap_err();
        let (_, remedies) = error.split_once(": ").unwrap();
        let remedies = remedies.split("; ").next().unwrap();
        let selected: Vec<_> = remedies
            .split(", ")
            .map(|selector| {
                find_entity(&facts, selector)
                    .unwrap_or_else(|error| panic!("unusable remedy {selector}: {error}"))
                    .key
                    .as_str()
            })
            .collect();
        let expected = if name == "Box" {
            vec!["main.ms#impl#Box", "main.ms#type#Box", "other.ms#type#Box"]
        } else {
            vec!["main.ms#impl#Box", "main.ms#type#Box"]
        };
        assert_eq!(selected, expected);
    }
    assert_eq!(
        find_entity(&facts, "main.ms#type#Box").unwrap().kind,
        "type"
    );
    assert_eq!(
        find_entity(&facts, "Box").unwrap_err(),
        find_entity(&facts, "Box").unwrap_err()
    );
}

#[test]
fn cross_module_entity_remedies_keep_file_qualification() {
    let facts = facts_of(vec![
        fact("a.ms", "type", "Item", 1),
        fact("b.ms", "type", "Item", 1),
        fact("a.ms", "fn", "unique", 4),
    ]);
    let error = find_entity(&facts, "Item").unwrap_err();
    assert_eq!(
        error,
        "Item is ambiguous; use one of: a.ms::Item, b.ms::Item"
    );
    for selector in ["a.ms::Item", "b.ms::Item", "a.ms#type#Item"] {
        assert_eq!(find_entity(&facts, selector).unwrap().name, "Item");
    }
    assert_eq!(find_entity(&facts, "unique").unwrap().file, "a.ms");
    let missing = find_entity(&facts, "a.ms#type#Missing").unwrap_err();
    assert!(missing.contains("a.ms#type#Missing"));
    assert!(missing.contains("file#kind#name"), "{missing}");
}

#[test]
fn full_entity_ids_take_precedence_over_display_names() {
    let record = fact("main.ms", "type", "Box", 1);
    let named_test = fact("main.ms", "test", &record.key, 7);
    let facts = facts_of(vec![
        record.clone(),
        fact("main.ms", "impl", "Box", 4),
        named_test.clone(),
    ]);
    assert_eq!(find_entity(&facts, &record.key).unwrap(), &record);
    assert_eq!(find_entity(&facts, &named_test.key).unwrap(), &named_test);
    assert_eq!(
        find_entity(&facts, &format!("{}::{}", named_test.file, named_test.name)).unwrap(),
        &named_test
    );
    let error = find_entity(&facts, "Box").unwrap_err();
    let (_, remedies) = error.split_once("; use one of: ").unwrap();
    for selector in remedies.split(", ") {
        assert_ne!(find_entity(&facts, selector).unwrap().kind, "test");
    }
}

#[test]
fn entity_remedies_account_for_other_declarations_display_names() {
    let facts = facts_of(vec![
        fact("main.ms", "type", "Item", 1),
        fact("other.ms", "type", "Item", 1),
        fact("main.ms", "test", "other.ms::Item", 7),
    ]);
    let error = find_entity(&facts, "Item").unwrap_err();
    let (_, remedies) = error.split_once("; use one of: ").unwrap();
    assert_eq!(remedies, "main.ms#type#Item, other.ms#type#Item");
    for selector in remedies.split(", ") {
        assert_eq!(find_entity(&facts, selector).unwrap().kind, "type");
    }
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
        label: "out := stdout()  [closed on exit]".into(),
        children: vec![
            Node {
                kind: "native".into(),
                label: "native @std/io/io.ms#stdout".into(),
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
    let want = "FLOW VIEW\n`- main  [fn] r.ms:15\n   `- call guarded\n      `- out := stdout()  [closed on exit]\n         |- native @std/io/io.ms#stdout\n         `- try call load\n";
    assert_eq!(flow, want);
    let scope = build_view(&facts, "scope", "guarded", 0).unwrap().ascii();
    assert_eq!(
        scope,
        "SCOPE VIEW\n`- guarded  [fn] r.ms:8\n   `- out := stdout()  [closed on exit]\n      `- try call load\n"
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
        label: "spawn  promise(fn: fetch(1))".into(),
        children: vec![Node {
            kind: "call".into(),
            label: "call fetch".into(),
            ..Node::default()
        }],
        ..Node::default()
    };
    let with = Node {
        kind: "scope".into(),
        label: "work := promise(fn: fetch(1))  [closed on exit]".into(),
        children: vec![
            spawn,
            Node {
                kind: "call".into(),
                label: "call work.wait".into(),
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
        "TASKS VIEW\n`- load  [fn] r.ms:3\n   `- work := promise(fn: fetch(1))  [closed on exit]\n      `- spawn  promise(fn: fetch(1))\n         `- call fetch\n"
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

fn slot(name: &str, ty: &str, var: bool, refs: &[&str]) -> ms_tooling::facts::Slot {
    ms_tooling::facts::Slot {
        name: name.into(),
        ty: ty.into(),
        var,
        ownership: Default::default(),
        refs: refs.iter().map(|r| r.to_string()).collect(),
    }
}

#[test]
fn types_view_expands_held_types_and_marks_cycles() {
    let mut order = fact("t.ms", "type", "Order", 1);
    let mut item = fact("t.ms", "type", "Item", 5);
    order.slots = vec![slot("items", "List[Item]", false, &[&item.key])];
    item.slots = vec![slot("order", "Order", false, &[&order.key])];
    let mut facts = facts_of(vec![order, item]);
    let tree = build_view(&facts, "types", "Order", 0).unwrap().ascii();
    assert_eq!(
        tree,
        "TYPES VIEW\n`- Order  [type] t.ms:1\n   `- items: List[Item]\n      `- Item  [type] t.ms:5\n         `- order: Order\n            `- Order  (cycle)\n"
    );
    // Without --entity a type nothing holds is the root; a pure cycle falls back to all types.
    let all = build_view(&facts, "types", "", 1).unwrap().ascii();
    assert!(all.contains("Order") && all.contains("Item"), "{all}");
    facts.entities.clear();
    assert_eq!(
        build_view(&facts, "types", "", 0).unwrap().ascii(),
        "TYPES VIEW\n`- none\n"
    );
}

#[test]
fn ownership_view_names_each_borrow_mode() {
    let mut save = fact("o.ms", "fn", "save", 2);
    save.slots = vec![
        slot("db", "Db", true, &[]),
        slot("name", "String", false, &[]),
    ];
    save.result = Some(slot("", "Int", false, &[]));
    save.scopes = 1;
    let facts = facts_of(vec![save]);
    let tree = build_view(&facts, "ownership", "", 0).unwrap().ascii();
    assert_eq!(
        tree,
        "OWNERSHIP VIEW\n`- save  [fn] o.ms:2\n   |- db: Db  var (exclusive borrow)\n   |- name: String  borrow\n   |- returns Int  owned\n   `- closes 1 resource scope(s)\n"
    );
}

// Read a class's declared ID using a distinguishing member, independently of its label.
fn class_with_member<'a>(diagram: &'a str, member: &str) -> &'a str {
    let block = diagram
        .split("    class ")
        .skip(1)
        .find(|block| block.split("    }\n").next().unwrap().contains(member))
        .unwrap();
    block.split([' ', '[']).next().unwrap()
}

#[test]
fn types_mermaid_preserves_distinct_declaration_identities() {
    let mut first = fact("a.ms", "type", "Item", 1);
    let mut second = fact("b.ms", "type", "Item", 1);
    let mut sanitized = fact("c.ms", "interface", "Box[Item]", 1);
    let mut literal = fact("d.ms", "alternative", "Box_Item_", 1);
    let reserved = fact("e.ms", "type", "__ms_type_0", 1);
    first.slots = vec![slot("first", "Item", false, &[&second.key])];
    second.slots = vec![slot("second", "Item", false, &[&first.key])];
    sanitized.slots = vec![slot("sanitized", "", false, &[&literal.key])];
    literal.slots = vec![slot("literal", "", false, &[&reserved.key])];
    let facts = facts_of(vec![literal, second, reserved, first, sanitized]);
    let diagram = mermaid_view(&facts, "types", "", 1).unwrap();
    let ids: Vec<_> = diagram
        .lines()
        .filter_map(|line| {
            line.strip_prefix("    class ")
                .map(|rest| rest.split([' ', '[']).next().unwrap())
        })
        .collect();
    assert_eq!(ids.len(), 5, "{diagram}");
    assert_eq!(
        ids.iter().collect::<std::collections::HashSet<_>>().len(),
        5,
        "{diagram}"
    );
    let first = class_with_member(&diagram, "+Item first");
    let second = class_with_member(&diagram, "+Item second");
    let sanitized = class_with_member(&diagram, "        sanitized");
    let literal = class_with_member(&diagram, "        literal");
    assert!(
        diagram.contains(&format!("    {first} *-- {second} : first\n")),
        "{diagram}"
    );
    assert!(
        diagram.contains(&format!("    {second} *-- {first} : second\n")),
        "{diagram}"
    );
    assert!(
        diagram.contains(&format!("    {sanitized} *-- {literal} : sanitized\n")),
        "{diagram}"
    );
    assert!(
        diagram.contains(&format!("    {literal} *-- __ms_type_0 : literal\n")),
        "{diagram}"
    );
    assert!(
        diagram.contains(&format!("class {second}[\"Item\"]")),
        "{diagram}"
    );
    assert!(
        diagram.contains(&format!("class {literal}[\"Box_Item_\"]")),
        "{diagram}"
    );
    assert_eq!(diagram, mermaid_view(&facts, "types", "", 1).unwrap());
}

#[test]
fn types_mermaid_only_links_declared_nodes_at_the_cap() {
    let mut types: Vec<_> = (0..=NODE_CAP)
        .map(|i| fact(&format!("{i:03}.ms"), "type", "Item", 1))
        .collect();
    let included = types[NODE_CAP - 1].key.clone();
    let excluded = types[NODE_CAP].key.clone();
    types[0].slots = vec![
        slot("included", "Item", false, &[&included]),
        slot("excluded", "Item", false, &[&excluded]),
    ];
    let facts = facts_of(types);
    let diagram = mermaid_view(&facts, "types", "", 1).unwrap();
    let ids: std::collections::HashSet<_> = diagram
        .lines()
        .filter_map(|line| {
            line.strip_prefix("    class ")
                .map(|rest| rest.split([' ', '[']).next().unwrap())
        })
        .collect();
    assert_eq!(ids.len(), NODE_CAP, "{diagram}");
    let edges: Vec<_> = diagram
        .lines()
        .filter(|line| line.contains(" *-- "))
        .collect();
    assert_eq!(edges.len(), 1, "{diagram}");
    assert!(edges[0].ends_with(" : included"), "{diagram}");
    let endpoints: Vec<_> = edges[0].split_whitespace().collect();
    assert!(
        ids.contains(endpoints[0]) && ids.contains(endpoints[2]),
        "{diagram}"
    );
}

#[test]
fn git_quoted_diff_paths_preserve_exact_filename_bytes() {
    for (quoted, expected) in [
        (r"caf\303\251.ms", "café.ms"),
        (r"\360\237\246\200.ms", "🦀.ms"),
        (r#"a\"b\\c\td\ne.ms"#, "a\"b\\c\td\ne.ms"),
        (r"\a\b\v\f\r.ms", "\x07\x08\x0b\x0c\r.ms"),
        ("café.ms", "café.ms"),
        (" with spaces .ms ", " with spaces .ms "),
    ] {
        let diff = format!(
            "diff --git \"a/{quoted}\" \"b/{quoted}\"\n--- \"a/{quoted}\"\n+++ \"b/{quoted}\"\n@@ -1 +1 @@\n-old\n+new\n"
        );
        let files = parse_diff(&diff).unwrap();
        assert_eq!(files[0].old, expected);
        assert_eq!(files[0].new, expected);
        assert_eq!(reverse_apply("new\n", &files[0].hunks).unwrap(), "old\n");
    }
}

#[test]
fn git_quoted_paths_preserve_additions_deletions_and_rename_rejection() {
    let added = parse_diff(
        "diff --git \"a/caf\\303\\251.ms\" \"b/caf\\303\\251.ms\"\n--- /dev/null\n+++ \"b/caf\\303\\251.ms\"\n@@ -0,0 +1 @@\n+new\n"
    ).unwrap();
    assert!(added[0].old.is_empty());
    assert_eq!(added[0].new, "café.ms");
    let removed = parse_diff(
        "diff --git \"a/caf\\303\\251.ms\" \"b/caf\\303\\251.ms\"\n--- \"a/caf\\303\\251.ms\"\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n"
    ).unwrap();
    assert!(removed[0].new.is_empty());
    assert_eq!(removed[0].old, "café.ms");
    let renamed =
        parse_diff("diff --git \"a/old.ms\" \"b/new.ms\"\n--- \"a/old.ms\"\n+++ \"b/new.ms\"\n")
            .unwrap_err();
    assert!(renamed.contains("renamed files are not supported"));
}

#[test]
fn malformed_git_quoted_paths_are_errors_not_guessed_names() {
    for path in [
        r#""a/unterminated"#,
        r#""a/embedded"quote.ms""#,
        r#""a/bad\q.ms""#,
        r#""a/short\30.ms""#,
        r#""a/high\400.ms""#,
        r#""a/invalid\377.ms""#,
        r#""a/nul\000.ms""#,
    ] {
        let error = parse_diff(&format!("diff --git a/x b/x\n--- {path}\n+++ b/x\n")).unwrap_err();
        assert!(error.starts_with("diff line 2:"), "{error}");
    }
}

#[test]
fn unquoted_git_and_plain_diff_paths_keep_existing_spelling() {
    for header in ["diff --git a/café.ms b/café.ms\n", ""] {
        let files = parse_diff(&format!("{header}--- a/café.ms\n+++ b/café.ms\n")).unwrap();
        assert_eq!(files[0].path(), "café.ms");
    }
    let files =
        parse_diff("--- \"literal.ms\"\told timestamp\n+++ \"literal.ms\"\tnew timestamp\n")
            .unwrap();
    assert_eq!(files[0].path(), "\"literal.ms\"");
}

#[test]
fn unquoted_git_paths_preserve_spaces_before_the_header_tab() {
    for path in [" space.ms", "space.ms ", "sp ace.ms"] {
        let files = parse_diff(&format!(
            "diff --git a/{path} b/{path}\n--- a/{path}\t\n+++ b/{path}\t\n"
        ))
        .unwrap();
        assert_eq!(files[0].old, path);
        assert_eq!(files[0].new, path);
    }
}

#[test]
fn reverse_diff_preserves_final_newline_on_each_side() {
    for old_newline in [false, true] {
        for new_newline in [false, true] {
            let marker = |present| {
                if present {
                    ""
                } else {
                    "\\ No newline at end of file\n"
                }
            };
            let patch = format!(
                "--- a/example.ms\n+++ b/example.ms\n@@ -1 +1 @@\n-old\n{}+new\n{}",
                marker(old_newline),
                marker(new_newline)
            );
            let files = parse_diff(&patch).unwrap();
            let head = if new_newline { "new\n" } else { "new" };
            let base = if old_newline { "old\n" } else { "old" };
            assert_eq!(reverse_apply(head, &files[0].hunks).unwrap(), base);
            let wrong_head = if new_newline { "new" } else { "new\n" };
            assert!(reverse_apply(wrong_head, &files[0].hunks).is_err());
            if !new_newline {
                assert!(reverse_apply("new\ntail", &files[0].hunks).is_err());
            }
        }
    }
}

#[test]
fn reverse_diff_keeps_unterminated_context_and_untouched_tail() {
    let files = parse_diff("--- a/x.ms\n+++ b/x.ms\n@@ -1,2 +1,2 @@\n-old\n+new\n tail\n\\ No newline at end of file\n").unwrap();
    assert_eq!(
        reverse_apply("new\ntail", &files[0].hunks).unwrap(),
        "old\ntail"
    );
    let files = parse_diff("--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n+new\n").unwrap();
    assert_eq!(
        reverse_apply("new\ntail", &files[0].hunks).unwrap(),
        "old\ntail"
    );
    assert_eq!(
        reverse_apply("new\ntail\n\n", &files[0].hunks).unwrap(),
        "old\ntail\n\n"
    );
}

#[test]
fn added_and_deleted_files_keep_empty_and_unterminated_content() {
    for newline in [false, true] {
        let marker = if newline {
            ""
        } else {
            "\\ No newline at end of file\n"
        };
        let removed = parse_diff(&format!(
            "--- a/x.ms\n+++ /dev/null\n@@ -1 +0,0 @@\n-old\n{marker}"
        ))
        .unwrap();
        let base = if newline { "old\n" } else { "old" };
        assert_eq!(removed_content(&removed[0].hunks), base);
        assert_eq!(reverse_apply("", &removed[0].hunks).unwrap(), base);
        let added = parse_diff(&format!(
            "--- /dev/null\n+++ b/x.ms\n@@ -0,0 +1 @@\n+new\n{marker}"
        ))
        .unwrap();
        let head = if newline { "new\n" } else { "new" };
        assert_eq!(reverse_apply(head, &added[0].hunks).unwrap(), "");
    }
    assert_eq!(removed_content(&[]), "");
    assert_eq!(reverse_apply("", &[]).unwrap(), "");
}

#[test]
fn localized_no_newline_notes_keep_the_same_structural_meaning() {
    let patch = "--- a/x.ms\n+++ b/x.ms\n@@ -1 +1 @@\n-old\n\\ Sin salto de línea al final del archivo\n+new\n";
    let files = parse_diff(patch).unwrap();
    assert_eq!(reverse_apply("new\n", &files[0].hunks).unwrap(), "old");
}

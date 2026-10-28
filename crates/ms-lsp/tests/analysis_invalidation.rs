//! Analysis reuse is checked by semantic lint invocations, not wall time.
use ms_lsp::json::{Json, obj};
use ms_lsp::lint::{Lint, LintFinding, Tooling};
use std::cell::Cell;
mod support;
use support::{Script, Workspace};

#[derive(Default)]
struct CountChecks(Cell<usize>);
impl Lint for CountChecks {
    fn source(&self, filename: &str, source: &str) -> Vec<LintFinding> {
        Tooling.source(filename, source)
    }
    fn program(&self, program: &ms_check::Program) -> Vec<LintFinding> {
        self.0.set(self.0.get() + 1);
        Tooling.program(program)
    }
}

fn change(s: &mut Script, uri: &str, source: &str, version: i64) {
    s.notify(
        "textDocument/didChange",
        obj([
            (
                "textDocument",
                obj([("uri", uri.into()), ("version", version.into())]),
            ),
            (
                "contentChanges",
                Json::Arr(vec![obj([("text", source.into())])]),
            ),
        ]),
    );
    s.at("textDocument/hover", uri, 0, 5);
}

fn publications(messages: &[Json], uri: &str) -> Vec<Json> {
    messages
        .iter()
        .filter_map(|m| {
            if m.get("method").and_then(|m| m.as_str()) != Some("textDocument/publishDiagnostics") {
                return None;
            }
            let p = m.get("params")?;
            (p.get("uri").and_then(|v| v.as_str()) == Some(uri)).then(|| p.clone())
        })
        .collect()
}

#[test]
fn editing_independent_documents_reuses_checked_analyses() {
    for count in [1, 8, 32] {
        let ws = Workspace::new("independent-edits");
        let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
        let source = include_str!("analysis_invalidation/independent.ms");
        for i in 0..count {
            let uri = ws.uri(&format!("tab_{i}.ms"));
            s.open(&uri, source, 1);
            s.at("textDocument/hover", &uri, 0, 5);
        }
        let edited = ws.uri("tab_0.ms");
        change(&mut s, &edited, &source.replace("+ 1", "+ 2"), 2);
        let lint = CountChecks::default();
        let output = s.rust_with(&lint);
        assert_eq!(
            lint.0.get(),
            count + 1,
            "only the edited graph needs fresh semantic analysis"
        );
        assert_eq!(publications(&output, &edited).len(), 2);
        for i in 1..count {
            assert_eq!(
                publications(&output, &ws.uri(&format!("tab_{i}.ms"))).len(),
                1
            );
        }
    }
}

const CONSUMER: &str = include_str!("analysis_invalidation/consumer.ms");
const MIDDLE: &str = include_str!("analysis_invalidation/middle.ms");
const LEAF: &str = include_str!("analysis_invalidation/leaf.ms");

#[test]
fn transitive_importers_refresh_and_match_a_fresh_session() {
    for project in [false, true] {
        let ws = Workspace::new("transitive-edits");
        let dir = if project { "project/" } else { "" };
        for (name, source) in [
            ("main.ms", CONSUMER),
            ("middle.ms", MIDDLE),
            ("leaf.ms", LEAF),
        ] {
            std::fs::write(ws.path(&format!("{dir}{name}")), source).unwrap();
        }
        let main = ws.uri(&format!("{dir}main.ms"));
        let leaf = ws.uri(&format!("{dir}leaf.ms"));
        let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
        s.open(&main, CONSUMER, 1);
        s.at("textDocument/hover", &main, 3, 13);
        s.open(&leaf, LEAF, 1);
        s.at("textDocument/hover", &leaf, 0, 12);
        // A changed export breaks the middle module across two import edges.
        let broken = LEAF.replace("leaf", "renamed");
        change(&mut s, &leaf, &broken, 2);
        let output = s.rust();
        let actual = publications(&output, &main).pop().unwrap();
        let mut fresh = Script::initialize(&ws.root.to_string_lossy(), false);
        fresh.open(&leaf, &broken, 2);
        fresh.open(&main, CONSUMER, 1);
        let expected = publications(&fresh.rust(), &main).pop().unwrap();
        assert_eq!(actual, expected);
        // Restore the export; a graph with errors must not retain stale errors.
        change(&mut s, &leaf, LEAF, 3);
        let restored = publications(&s.rust(), &main).pop().unwrap();
        assert_eq!(
            restored
                .get("diagnostics")
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            0
        );
        assert_eq!(publications(&output, &main).len(), 3);
    }
}

#[test]
fn opening_a_previously_missing_import_repairs_failed_graphs() {
    let ws = Workspace::new("missing-import");
    std::fs::write(ws.path("middle.ms"), MIDDLE).unwrap();
    let main = ws.uri("middle.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.open(&main, MIDDLE, 1);
    s.at("textDocument/hover", &main, 3, 13);
    // The file exists only in the editor overlay.
    s.open(&ws.uri("leaf.ms"), LEAF, 1);
    let output = s.rust();
    let notes = publications(&output, &main);
    assert_eq!(notes.len(), 2);
    assert!(
        !notes[0]
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert!(
        notes[1]
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[cfg(unix)]
#[test]
fn divergent_symlink_overlays_invalidate_even_unrelated_graphs() {
    let ws = Workspace::new("overlay-conflict");
    std::fs::write(ws.path("leaf.ms"), LEAF).unwrap();
    std::os::unix::fs::symlink("leaf.ms", ws.path("alias.ms")).unwrap();
    let main = ws.uri("independent.ms");
    let source = include_str!("analysis_invalidation/independent.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.open(&main, source, 1);
    s.at("textDocument/hover", &main, 0, 5);
    s.open(&ws.uri("leaf.ms"), LEAF, 1);
    s.open(&ws.uri("alias.ms"), &LEAF.replace("+ 1", "+ 2"), 1);
    let output = s.rust();
    let actual = publications(&output, &main).pop().unwrap();
    let mut fresh = Script::initialize(&ws.root.to_string_lossy(), false);
    fresh.open(&ws.uri("leaf.ms"), LEAF, 1);
    fresh.open(&ws.uri("alias.ms"), &LEAF.replace("+ 1", "+ 2"), 1);
    fresh.open(&main, source, 1);
    assert_eq!(actual, publications(&fresh.rust(), &main).pop().unwrap());
}

#[test]
fn changed_import_edges_are_tracked_and_close_restores_disk_sources() {
    let ws = Workspace::new("new-import-edge");
    for (name, source) in [("middle.ms", MIDDLE), ("leaf.ms", LEAF), ("other.ms", LEAF)] {
        std::fs::write(ws.path(name), source).unwrap();
    }
    let main = ws.uri("consumer.ms");
    let middle = ws.uri("middle.ms");
    let other = ws.uri("other.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.open(&main, CONSUMER, 1);
    s.at("textDocument/hover", &main, 3, 13);
    s.open(&middle, MIDDLE, 1);
    change(
        &mut s,
        &middle,
        &MIDDLE.replace("./leaf.ms", "./other.ms"),
        2,
    );
    s.open(&other, LEAF, 1);
    change(&mut s, &other, &LEAF.replace("leaf", "renamed"), 2);
    let output = s.rust();
    let notes = publications(&output, &middle);
    assert!(
        !notes
            .last()
            .unwrap()
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
    s.notify(
        "textDocument/didClose",
        obj([("textDocument", obj([("uri", other.into())]))]),
    );
    let restored = publications(&s.rust(), &middle).pop().unwrap();
    assert!(
        restored
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(std::fs::read_to_string(ws.path("other.ms")).unwrap(), LEAF);
}

#[test]
fn manifest_and_source_watch_events_clear_cached_graphs() {
    for filename in ["ms.toml", "closed.ms"] {
        let ws = Workspace::new("watched-cache");
        let main = ws.uri("main.ms");
        let source = include_str!("analysis_invalidation/independent.ms");
        let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
        s.open(&main, source, 1);
        s.at("textDocument/hover", &main, 0, 5);
        s.notify(
            "workspace/didChangeWatchedFiles",
            obj([(
                "changes",
                Json::Arr(vec![obj([
                    ("uri", ws.uri(filename).into()),
                    ("type", 2_i64.into()),
                ])]),
            )]),
        );
        let lint = CountChecks::default();
        let output = s.rust_with(&lint);
        assert_eq!(lint.0.get(), 2);
        assert_eq!(publications(&output, &main).len(), 2);
    }
}

#[test]
fn divergent_percent_encoded_overlays_match_uncached_analysis() {
    let ws = Workspace::new("encoded-overlay-conflict");
    std::fs::write(ws.path("leaf.ms"), LEAF).unwrap();
    let alias = ws.uri("%6ceaf.ms");
    let main = ws.uri("independent.ms");
    let source = include_str!("analysis_invalidation/independent.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.open(&main, source, 1);
    s.open(&ws.uri("leaf.ms"), LEAF, 1);
    s.open(&alias, LEAF, 1);
    change(&mut s, &alias, &LEAF.replace("+ 1", "+ 2"), 2);
    let actual = publications(&s.rust(), &main).pop().unwrap();
    let mut fresh = Script::initialize(&ws.root.to_string_lossy(), false);
    fresh.open(&ws.uri("leaf.ms"), LEAF, 1);
    fresh.open(&alias, &LEAF.replace("+ 1", "+ 2"), 2);
    fresh.open(&main, source, 1);
    assert_eq!(actual, publications(&fresh.rust(), &main).pop().unwrap());
}

#[cfg(unix)]
#[test]
fn unsaved_dependency_under_a_symlinked_directory_refreshes_importers() {
    let ws = Workspace::new("new-symlink-source");
    std::fs::create_dir(ws.path("real")).unwrap();
    std::os::unix::fs::symlink("real", ws.path("alias")).unwrap();
    std::fs::write(ws.path("real/middle.ms"), MIDDLE).unwrap();
    let middle = ws.uri("real/middle.ms");
    let leaf = ws.uri("alias/leaf.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.open(&middle, MIDDLE, 1);
    s.at("textDocument/hover", &middle, 0, 25);
    s.open(&leaf, LEAF, 1);
    s.at("textDocument/hover", &middle, 0, 25);
    change(&mut s, &leaf, &LEAF.replace("leaf", "renamed"), 2);
    let notes = publications(&s.rust(), &middle);
    assert_eq!(notes.len(), 3);
    assert!(
        notes[1]
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert!(
        !notes[2]
            .get("diagnostics")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
}

//! Module graph loading and checking over real files.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_rt as _;
use std::path::{Path, PathBuf};

use ms_driver::{
    CheckRequest, EditorOptions, LoadOptions, check_graph, load_editor_file, load_file,
};

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-driver-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn write(dir: &Path, name: &str, text: &str) -> String {
    let path = dir.join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, text).unwrap();
    path.to_string_lossy().into_owned()
}

#[test]
fn imports_are_loaded_before_their_importers() {
    let dir = scratch("order");
    write(&dir, "lib.ms", "export def one() -> Int:\n    return 1\n");
    let entry = write(
        &dir,
        "main.ms",
        "from \"./lib.ms\" import one\n\nexport def main() -> Int:\n    return one()\n",
    );
    let graph = load_file(&entry, LoadOptions::default());
    assert!(graph.diagnostics.is_empty());
    assert_eq!(graph.entry, "main.ms");
    assert_eq!(graph.modules.len(), 2);
    let checked = check_graph(graph, CheckRequest { entry: true });
    assert!(checked.success(), "{:?}", checked.diagnostics);
}

#[test]
fn cycles_are_reported_at_the_closing_import() {
    let dir = scratch("cycle");
    write(
        &dir,
        "b.ms",
        "from \"./a.ms\" import x\nexport def y() -> Int:\n    return 0\n",
    );
    let entry = write(
        &dir,
        "a.ms",
        "from \"./b.ms\" import y\n\nexport def main() -> Int:\n    return 0\n",
    );
    let graph = load_file(&entry, LoadOptions::default());
    assert!(graph.modules.is_empty());
    let issue = &graph.diagnostics[0];
    assert_eq!(&*issue.file, "b.ms");
    assert!(
        issue
            .message
            .starts_with("cyclic module dependency at a.ms;"),
        "{issue}"
    );
}

#[test]
fn imported_parse_diagnostics_keep_their_source_in_strict_and_recovery_loads() {
    let dir = scratch("import-diagnostic");
    write(&dir, "broken.ms", "\n\nfn broken(:\n");
    let entry = write(&dir, "main.ms", "from \"./broken.ms\" import broken\n");
    let strict = load_file(&entry, LoadOptions::default());
    let recovered = load_editor_file(
        &entry,
        LoadOptions::default(),
        &EditorOptions {
            recover: true,
            ..EditorOptions::default()
        },
    );
    assert!(strict.modules.is_empty());
    assert!(!recovered.modules.is_empty());
    assert_eq!(strict.diagnostics.len(), 1);
    assert_eq!(recovered.diagnostics.len(), 1);
    let issue = &strict.diagnostics[0];
    assert_eq!(&*issue.file, "broken.ms");
    assert!(issue.pos.line >= 3);
    assert_eq!(issue.phase, ms_syntax::Phase::Parse);
    assert_eq!(strict.diagnostics, recovered.diagnostics);
}

#[test]
fn project_aliases_and_discovered_tests() {
    let dir = scratch("project");
    write(
        &dir,
        "ms.toml",
        "[project]\nname = \"p\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n[aliases]\n@lib = \"src/lib\"\n",
    );
    write(
        &dir,
        "src/lib/util.ms",
        "export def two() -> Int:\n    return 2\n",
    );
    write(
        &dir,
        "src/main.ms",
        "from \"@lib/util.ms\" import two\n\nexport def main() -> Int:\n    return two()\n",
    );
    write(&dir, "main_test.ms", "test \"always\":\n    return\n");
    let manifest = dir.join("ms.toml");
    let manifest = manifest.to_str().unwrap();

    let plain = load_file(manifest, LoadOptions::default());
    assert!(plain.diagnostics.is_empty(), "{:?}", plain.diagnostics);
    assert_eq!(plain.modules.len(), 2);
    assert!(!plain.library);

    let with_tests = load_file(manifest, LoadOptions { tests: true });
    assert!(
        with_tests.diagnostics.is_empty(),
        "{:?}",
        with_tests.diagnostics
    );
    assert_eq!(with_tests.modules.len(), 3, "main_test.ms joins the graph");
}

#[test]
fn entry_diagnostics_keep_go_wording() {
    let dir = scratch("entry");
    let entry = write(
        &dir,
        "main.ms",
        "export def main() -> String:\n    return \"a\"\n",
    );
    let checked = check_graph(
        load_file(&entry, LoadOptions::default()),
        CheckRequest { entry: true },
    );
    let issue = &checked.diagnostics[0];
    assert_eq!(
        issue.message,
        "entry must export fn main() Int; main returns String, so declare its result type Int and return an exit status, e.g. 'return 0'"
    );
    // Without the entry requirement the same file checks.
    let fine = check_graph(
        load_file(&entry, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert!(fine.success());
}

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
    let syms = ms_syntax::Names::global();
    let dir = scratch("order");
    write(&dir, "lib.ms", "export fn one() Int:\n    return 1\n");
    let entry = write(
        &dir,
        "main.ms",
        "import one from \"./lib.ms\"\n\nexport fn main() Int:\n    return one()\n",
    );
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.diagnostics.is_empty());
    assert_eq!(graph.entry, "main.ms");
    assert_eq!(graph.modules.len(), 2);
    let checked = check_graph(
        syms,
        graph,
        CheckRequest {
            entry: true,
            ..CheckRequest::default()
        },
    );
    assert!(checked.success(), "{:?}", checked.diagnostics);
}

#[test]
fn embedded_and_imported_inputs_keep_first_seen_order_without_duplicates() {
    let syms = ms_syntax::Names::global();
    let dir = crate::common::TempDir::new();
    let manifest = crate::common::write(
        dir.path(),
        "ms.toml",
        include_str!("fixtures/input_order/ms.toml"),
    );
    let main = crate::common::write(
        dir.path(),
        "main.ms",
        include_str!("fixtures/input_order/main.ms"),
    );
    let dep = crate::common::write(
        dir.path(),
        "assets/dep.ms",
        include_str!("fixtures/input_order/assets/dep.ms"),
    );
    let generated = crate::common::join(dir.path(), ".ms-embed/assets.ms");
    // The embedded project root includes the manifest, entry and imported file too.
    // Each must keep the position of its first encounter across all input sources.
    let mut expected = vec![manifest.clone(), main.clone(), generated, dir.path().into()];
    let native = Path::new(dir.path());
    // Embedded entries keep native PathBuf spellings; imported modules use canonical `/`
    // paths. Preserve the existing exact-string deduplication contract on every host.
    for input in [
        native.join("assets").to_string_lossy().into_owned(),
        native
            .join("assets")
            .join("dep.ms")
            .to_string_lossy()
            .into_owned(),
        native.join("main.ms").to_string_lossy().into_owned(),
        native.join("ms.toml").to_string_lossy().into_owned(),
        dep,
    ] {
        if !expected.contains(&input) {
            expected.push(input);
        }
    }
    for entry in [&manifest, &main] {
        let graph = load_file(syms, entry, LoadOptions::default());
        assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
        assert_eq!(graph.modules.len(), 3);
        assert_eq!(graph.inputs, expected);
        let checked = check_graph(
            syms,
            graph,
            CheckRequest {
                entry: true,
                ..CheckRequest::default()
            },
        );
        assert!(checked.success(), "{:?}", checked.diagnostics);
        assert_eq!(checked.inputs, expected);
    }
}

#[test]
fn cycles_are_reported_at_the_closing_import() {
    let syms = ms_syntax::Names::global();
    let dir = scratch("cycle");
    write(
        &dir,
        "b.ms",
        "import x from \"./a.ms\"\nexport fn y() Int:\n    return 0\n",
    );
    let entry = write(
        &dir,
        "a.ms",
        "import y from \"./b.ms\"\n\nexport fn main() Int:\n    return 0\n",
    );
    let graph = load_file(syms, &entry, LoadOptions::default());
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
    let syms = ms_syntax::Names::global();
    let dir = scratch("import-diagnostic");
    write(&dir, "broken.ms", "\n\nfn broken(:\n");
    let entry = write(&dir, "main.ms", "import broken from \"./broken.ms\"\n");
    let strict = load_file(syms, &entry, LoadOptions::default());
    let recovered = load_editor_file(
        syms,
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
    let syms = ms_syntax::Names::global();
    let dir = scratch("project");
    write(
        &dir,
        "ms.toml",
        "[project]\nname = \"p\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n[aliases]\n@lib = \"src/lib\"\n",
    );
    write(
        &dir,
        "src/lib/util.ms",
        "export fn two() Int:\n    return 2\n",
    );
    write(
        &dir,
        "src/main.ms",
        "import two from \"@lib/util.ms\"\n\nexport fn main() Int:\n    return two()\n",
    );
    write(&dir, "main_test.ms", "test \"always\":\n    return\n");
    let manifest = dir.join("ms.toml");
    let manifest = manifest.to_str().unwrap();

    let plain = load_file(syms, manifest, LoadOptions::default());
    assert!(plain.diagnostics.is_empty(), "{:?}", plain.diagnostics);
    assert_eq!(plain.modules.len(), 2);
    assert!(!plain.library);

    let with_tests = load_file(syms, manifest, LoadOptions { tests: true });
    assert!(
        with_tests.diagnostics.is_empty(),
        "{:?}",
        with_tests.diagnostics
    );
    assert_eq!(with_tests.modules.len(), 3, "main_test.ms joins the graph");
}

#[test]
fn entry_diagnostics_name_the_required_signature() {
    let syms = ms_syntax::Names::global();
    let dir = scratch("entry");
    let entry = write(
        &dir,
        "main.ms",
        "export fn main() String:\n    return \"a\"\n",
    );
    let checked = check_graph(
        syms,
        load_file(syms, &entry, LoadOptions::default()),
        CheckRequest {
            entry: true,
            ..CheckRequest::default()
        },
    );
    let issue = &checked.diagnostics[0];
    assert_eq!(
        issue.message,
        "entry must declare fn main; main returns String, so return Unit, Unit! (an error prints and exits 1), Int?!, or an Int exit status"
    );
    // Without the entry requirement the same file checks.
    let fine = check_graph(
        syms,
        load_file(syms, &entry, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert!(fine.success());
}

#[test]
fn file_entries_share_a_library_under_the_enclosing_manifest() {
    let syms = ms_syntax::Names::global();
    let dir = scratch("enclosing");
    write(&dir, "ms.toml", include_str!("fixtures/enclosing/ms.toml"));
    write(&dir, "lib.ms", include_str!("fixtures/enclosing/lib.ms"));
    let entry = write(
        &dir,
        "suite/driver.ms",
        include_str!("fixtures/enclosing/suite/driver.ms"),
    );
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
    assert_eq!(graph.entry, "suite/driver.ms");
    let checked = check_graph(
        syms,
        graph,
        CheckRequest {
            entry: true,
            ..CheckRequest::default()
        },
    );
    assert!(checked.success(), "{:?}", checked.diagnostics);
}

#[test]
fn nested_project_editor_buffers_do_not_contaminate_parent_graphs() {
    let syms = ms_syntax::Names::global();
    let dir = scratch("nested-overlay-discovery");
    let manifest = write(
        &dir,
        "ms.toml",
        "[project]\nname = \"parent\"\nsource = \"src\"\n",
    );
    write(&dir, "src/value.ms", "export fn value() Int: 1\n");
    write(&dir, "src/child/ms.toml", "invalid configuration");
    let child = write(&dir, "src/child/broken.ms", "not valid Manuscript");
    let new_child = dir.join("src/child/new.ms").to_str().unwrap().to_string();
    for path in [child, new_child] {
        let graph = load_editor_file(
            syms,
            &manifest,
            LoadOptions::default(),
            &EditorOptions {
                overlay: [(path, "not valid Manuscript".to_string())].into(),
                ..EditorOptions::default()
            },
        );
        assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
        assert_eq!(graph.modules.len(), 1);
    }
}

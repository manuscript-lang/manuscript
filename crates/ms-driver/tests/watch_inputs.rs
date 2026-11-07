//! Watch provenance keeps failed local sources and ancestor configuration lookups.

use std::path::Path;

use crate::common::{TempDir, join, write};
use ms_driver::{CheckRequest, LoadOptions, check_graph, load_file};

const MAIN: &str = include_str!("watch_inputs/main.ms");
const DEP: &str = include_str!("watch_inputs/dep.ms");

fn non_manifest_inputs(graph: &ms_driver::Graph) -> Vec<String> {
    graph
        .input_paths
        .iter()
        .filter(|path| ms_driver::project::pathops::base(path) != "ms.toml")
        .cloned()
        .collect()
}

#[test]
fn initially_missing_import_is_retained_without_a_program() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let entry = write(dir.path(), "main.ms", MAIN);
    let dep = join(dir.path(), "dep.ms");
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.modules.is_empty());
    assert!(!graph.diagnostics.is_empty());
    assert_eq!(non_manifest_inputs(&graph).len(), 2);
    assert!(graph.input_paths.contains(&entry));
    assert!(graph.input_paths.contains(&dep));
    let checked = check_graph(syms, graph, CheckRequest::default());
    assert!(checked.program.is_none());
    assert!(checked.input_paths.contains(&dep));

    write(dir.path(), "dep.ms", DEP);
    let graph = load_file(syms, &entry, LoadOptions::default());
    let checked = check_graph(syms, graph, CheckRequest::default());
    assert!(checked.success(), "{:?}", checked.diagnostics);
}

#[test]
fn initially_broken_import_is_retained_without_a_program() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let entry = write(dir.path(), "main.ms", MAIN);
    let dep = write(dir.path(), "dep.ms", include_str!("watch_inputs/broken.ms"));
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.modules.is_empty());
    assert!(!graph.diagnostics.is_empty());
    assert!(graph.input_paths.contains(&dep));
    let checked = check_graph(syms, graph, CheckRequest::default());
    assert!(checked.program.is_none());
    assert!(checked.input_paths.contains(&dep));
}

#[test]
fn missing_directories_advance_to_the_missing_file() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let entry = write(
        dir.path(),
        "main.ms",
        include_str!("watch_inputs/nested.ms"),
    );
    let nested = join(dir.path(), "nested");
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.input_paths.contains(&nested));
    std::fs::create_dir(&nested).unwrap();
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.input_paths.contains(&join(&nested, "dep.ms")));
}

#[test]
fn missing_import_outside_root_is_not_a_watch_input() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let root = join(dir.path(), "project");
    let entry = write(&root, "main.ms", include_str!("watch_inputs/outside.ms"));
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(!graph.diagnostics.is_empty());
    assert_eq!(non_manifest_inputs(&graph), [entry]);
}

fn symlink_dir(from: &Path, to: &Path) {
    #[cfg(unix)]
    std::os::unix::fs::symlink(from, to).unwrap();
    #[cfg(windows)]
    std::os::windows::fs::symlink_dir(from, to).unwrap();
}

fn symlink_file(from: &Path, to: &Path) {
    #[cfg(unix)]
    std::os::unix::fs::symlink(from, to).unwrap();
    #[cfg(windows)]
    std::os::windows::fs::symlink_file(from, to).unwrap();
}

#[test]
fn missing_import_through_external_directory_link_is_not_a_watch_input() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let root = join(dir.path(), "project");
    let outside = join(dir.path(), "outside");
    let entry = write(&root, "main.ms", include_str!("watch_inputs/nested.ms"));
    std::fs::create_dir(&outside).unwrap();
    symlink_dir(Path::new(&outside), Path::new(&join(&root, "nested")));
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(!graph.diagnostics.is_empty());
    assert_eq!(non_manifest_inputs(&graph), [entry]);
}

#[test]
fn dangling_external_file_link_is_not_a_watch_input() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let root = join(dir.path(), "project");
    let entry = write(&root, "main.ms", MAIN);
    let outside = join(dir.path(), "absent.ms");
    symlink_file(Path::new(&outside), Path::new(&join(&root, "dep.ms")));
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(!graph.diagnostics.is_empty());
    assert_eq!(non_manifest_inputs(&graph), [entry]);
}

#[test]
fn dangling_in_root_import_links_retain_the_missing_target() {
    let syms = ms_syntax::Names::global();
    for directory in [false, true] {
        let dir = TempDir::new();
        let entry = write(
            dir.path(),
            "main.ms",
            if directory {
                include_str!("watch_inputs/nested.ms")
            } else {
                MAIN
            },
        );
        let missing = join(dir.path(), "target");
        if directory {
            symlink_dir(Path::new(&missing), Path::new(&join(dir.path(), "nested")));
        } else {
            symlink_file(Path::new(&missing), Path::new(&join(dir.path(), "dep.ms")));
        }
        let graph = load_file(syms, &entry, LoadOptions::default());
        assert!(graph.input_paths.contains(&missing));
        if directory {
            write(&missing, "dep.ms", DEP);
        } else {
            std::fs::write(&missing, DEP).unwrap();
        }
        let graph = load_file(syms, &entry, LoadOptions::default());
        let checked = check_graph(syms, graph, CheckRequest::default());
        assert!(checked.success(), "{:?}", checked.diagnostics);
    }
}

#[test]
fn missing_alias_target_is_retained_when_manifest_loading_fails() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    write(dir.path(), "main.ms", include_str!("watch_inputs/alias.ms"));
    let manifest = write(
        dir.path(),
        "ms.toml",
        &format!(
            "{}\n[aliases]\n\"@dep\" = \"dep.ms\"\n",
            include_str!("watch_inputs/manifest.toml")
        ),
    );
    let dep = join(dir.path(), "dep.ms");
    let graph = load_file(syms, &manifest, LoadOptions::default());
    assert!(!graph.diagnostics.is_empty());
    assert!(graph.input_paths.contains(&manifest));
    assert!(graph.input_paths.contains(&dep));
    let checked = check_graph(syms, graph, CheckRequest::default());
    assert!(checked.program.is_none());
    assert!(checked.input_paths.contains(&dep));
    write(dir.path(), "dep.ms", DEP);
    let graph = load_file(syms, &manifest, LoadOptions::default());
    let checked = check_graph(syms, graph, CheckRequest::default());
    assert!(checked.success(), "{:?}", checked.diagnostics);
}

#[test]
fn bare_file_retains_its_enclosing_manifest_even_when_invalid() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let entry = write(dir.path(), "src/main.ms", MAIN);
    write(dir.path(), "src/dep.ms", DEP);
    let manifest = write(
        dir.path(),
        "ms.toml",
        include_str!("watch_inputs/manifest.toml"),
    );
    // The manifest's declared entry must exist, but a bare-file command still
    // selects src/main.ms, not this entry.
    write(dir.path(), "main.ms", DEP);
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
    assert!(graph.project_root.is_empty());
    assert!(graph.input_paths.contains(&manifest));
    std::fs::write(&manifest, "[project]\nname\n").unwrap();
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(!graph.diagnostics.is_empty());
    let checked = check_graph(syms, graph, CheckRequest::default());
    assert!(checked.program.is_none());
    assert!(checked.input_paths.contains(&manifest));
}

#[test]
fn missing_external_alias_target_is_not_a_watch_input() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let root = join(dir.path(), "project");
    write(&root, "main.ms", include_str!("watch_inputs/alias.ms"));
    let manifest = write(
        &root,
        "ms.toml",
        &format!(
            "{}\n[aliases]\n\"@dep\" = \"../outside.ms\"\n",
            include_str!("watch_inputs/manifest.toml")
        ),
    );
    let graph = load_file(syms, &manifest, LoadOptions::default());
    assert!(!graph.diagnostics.is_empty());
    assert_eq!(
        graph.input_paths.into_iter().collect::<Vec<_>>(),
        [manifest]
    );
}

#[test]
fn missing_nearer_manifests_are_retained_until_the_selected_ancestor() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let entry = write(dir.path(), "project/src/main.ms", MAIN);
    write(dir.path(), "project/src/dep.ms", DEP);
    write(dir.path(), "main.ms", DEP);
    let selected = write(
        dir.path(),
        "ms.toml",
        include_str!("watch_inputs/manifest.toml"),
    );
    let nearer = join(dir.path(), "project/ms.toml");
    let nearest = join(dir.path(), "project/src/ms.toml");
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
    for path in [&nearest, &nearer, &selected] {
        assert!(graph.input_paths.contains(path), "missing {path}");
    }
    let parent = ms_driver::project::pathops::dir(dir.path());
    assert!(!graph.input_paths.contains(&join(&parent, "ms.toml")));
    write(dir.path(), "project/main.ms", DEP);
    write(
        dir.path(),
        "project/ms.toml",
        include_str!("watch_inputs/manifest.toml"),
    );
    let graph = load_file(syms, &entry, LoadOptions::default());
    assert!(graph.diagnostics.is_empty(), "{:?}", graph.diagnostics);
    assert_eq!(graph.source_root, join(dir.path(), "project"));
    assert!(graph.input_paths.contains(&nearest));
    assert!(graph.input_paths.contains(&nearer));
    assert!(!graph.input_paths.contains(&selected));
}

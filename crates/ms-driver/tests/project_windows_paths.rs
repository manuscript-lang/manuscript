#![cfg(windows)]

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use ms_driver::project::{
    Overlay, canonical_overlay, gopath, read_project, resolve_import, source_path,
};

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "ms-project-windows-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn native(path: &Path) -> &str {
    path.to_str().unwrap()
}

#[test]
fn drive_and_unc_roots_bound_lexical_paths() {
    assert!(gopath::is_abs(r"C:\repo\main.ms"));
    assert!(gopath::is_abs("C:/repo/main.ms"));
    assert!(gopath::is_abs(r"\\server\share\main.ms"));
    assert!(!gopath::is_abs(r"C:repo\main.ms"));
    assert!(!gopath::is_abs(r"\repo\main.ms"));
    assert_eq!(gopath::clean(r"C:\repo\..\.."), "C:/");
    assert_eq!(gopath::clean(r"C:repo\..\.."), "C:..");
    assert_eq!(gopath::dir(r"C:\"), "C:/");
    assert_eq!(gopath::dir("C:/"), "C:/");
    assert_eq!(gopath::dir(r"\\server\share"), "//server/share");
    assert_eq!(gopath::clean(r"\\server\share"), "//server/share");
    assert_eq!(gopath::clean(r"\\server\share\a\..\.."), "//server/share/");
    assert_eq!(gopath::base(r"C:\repo\main.ms"), "main.ms");
    assert_eq!(gopath::base(r"\\server\share"), "/");
    assert_eq!(gopath::ext(r"C:\dir.ms\file"), "");
    assert_eq!(gopath::rel("c:/root", "C:/root").unwrap(), ".");
    assert_eq!(
        gopath::rel("//server/share", "//server/share/a").unwrap(),
        "a"
    );
    assert!(gopath::rel("C:/root", "D:/root").is_err());
    assert!(gopath::rel("//server/share", "//server/other").is_err());
    assert!(gopath::rel("C:/root", "C:root").is_err());
    assert_eq!(gopath::abs("").unwrap(), gopath::abs(".").unwrap());
}

#[test]
fn native_absolute_project_paths_resolve_without_repeating_the_drive() {
    let temp = TempDir::new();
    let manifest = temp.0.join("ms.toml");
    let entry = temp.0.join("main.ms");
    let value = temp.0.join("value.ms");
    std::fs::write(
        &manifest,
        "[project]\nname = \"windows\"\nsource = \".\"\nentry = \"main.ms\"\n",
    )
    .unwrap();
    std::fs::write(&entry, "").unwrap();
    std::fs::write(&value, "").unwrap();
    let project = read_project(native(&manifest)).unwrap();
    let canonical_manifest = std::fs::canonicalize(&manifest).unwrap();
    assert_eq!(
        gopath::clean(native(&canonical_manifest)),
        native(&canonical_manifest)
    );
    assert_eq!(
        gopath::abs(native(&canonical_manifest)).unwrap(),
        gopath::join(&[&project.root, "ms.toml"])
    );
    assert_eq!(read_project(native(&canonical_manifest)).unwrap(), project);
    assert_eq!(project.source, project.root);
    assert_eq!(
        gopath::abs(native(&manifest)).unwrap(),
        gopath::clean(native(&manifest))
    );
    assert_eq!(
        ms_driver::project::find_manifest(&project.entry).unwrap(),
        gopath::join(&[&project.root, "ms.toml"])
    );
    assert_eq!(
        source_path(&project.root, native(&entry), &Overlay::new()).unwrap(),
        project.entry
    );
    assert_eq!(
        resolve_import(&project, &project.entry, "./value.ms", &Overlay::new()).unwrap(),
        gopath::eval_symlinks(native(&value)).unwrap()
    );
}

#[test]
fn native_overlay_spellings_keep_conflicts_and_root_confinement() {
    let temp = TempDir::new();
    let root = temp.0.join("project");
    std::fs::create_dir(&root).unwrap();
    let canonical_root = gopath::eval_symlinks(native(&root)).unwrap();
    let unsaved = root.join("new.ms");
    let raw = native(&unsaved).to_string();
    let mixed = format!("{}/new.ms", native(&root));
    let canonical = gopath::join(&[&canonical_root, "new.ms"]);
    let mut overlay = Overlay::new();
    overlay.insert(raw.clone(), "first".to_string());
    assert_eq!(
        source_path(&canonical_root, &raw, &overlay).unwrap(),
        canonical
    );
    assert_eq!(
        canonical_overlay(&canonical_root, &overlay).unwrap()[&canonical],
        "first"
    );
    overlay.insert(mixed.clone(), "second".to_string());
    assert_eq!(
        source_path(&canonical_root, &mixed, &overlay).unwrap(),
        canonical
    );
    assert!(
        canonical_overlay(&canonical_root, &overlay)
            .unwrap_err()
            .to_string()
            .contains("conflicting editor overlays")
    );

    let outside = temp.0.join("outside.ms");
    std::fs::write(&outside, "").unwrap();
    assert!(
        source_path(&canonical_root, native(&outside), &Overlay::new())
            .unwrap_err()
            .to_string()
            .contains("path escapes project root")
    );
    let outside_new = temp.0.join("outside-new.ms");
    overlay.insert(native(&outside_new).to_string(), "outside".to_string());
    assert!(
        source_path(&canonical_root, native(&outside_new), &overlay)
            .unwrap_err()
            .to_string()
            .contains("path escapes project root")
    );
}

#[test]
fn verbatim_names_that_lose_identity_are_rejected() {
    let temp = TempDir::new();
    let verbatim = std::fs::canonicalize(&temp.0).unwrap().join("trailing.");
    std::fs::write(&verbatim, "literal dot").unwrap();
    assert_eq!(gopath::clean(native(&verbatim)), native(&verbatim));
    assert!(gopath::abs(native(&verbatim)).is_err());
    assert!(gopath::eval_symlinks(native(&verbatim)).is_err());
}

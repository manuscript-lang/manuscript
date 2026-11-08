use crate::common;

use common::*;
use ms_driver::project::{Overlay, Project, discover_modules, discover_modules_with_overlay};

fn sorted(mut v: Vec<String>) -> Vec<String> {
    v.sort();
    v
}

#[test]
fn discovery_preserves_explicit_source_roots() {
    for source in [".", "src", ".hidden/src", "vendor/src", "node_modules/src"] {
        let dir = TempDir::new();
        let root = dir.path().to_string();
        let src = join(&root, source);
        let p = Project {
            root: root.clone(),
            source: src.clone(),
            ..Default::default()
        };
        for name in [
            "value.ms",
            "value_test.ms",
            "test.ms",
            "nested/value.ms",
            ".hidden/bad_test.ms",
            "vendor/bad_test.ms",
            "node_modules/bad_test.ms",
        ] {
            write(&src, name, "");
        }
        let outside_test = write(&root, "other/outside_test.ms", "");
        write(&root, "other/unrelated.ms", "");
        for all in [false, true] {
            let mut want = vec![outside_test.clone()];
            if all || source == "." || source == "src" {
                want.push(join(&src, "test.ms"));
                want.push(join(&src, "value_test.ms"));
            }
            if all {
                want.push(join(&src, "value.ms"));
                want.push(join(&src, "nested/value.ms"));
                if source == "." {
                    want.push(join(&root, "other/unrelated.ms"));
                }
            }
            let want = sorted(want);
            let changed = Overlay::from([(join(&src, "value_test.ms"), "changed".to_string())]);
            for overlay in [Overlay::new(), changed] {
                let got = discover_modules_with_overlay(&p, all, &overlay).unwrap();
                assert_eq!(got, want, "source={source} all={all}");
            }
        }
    }
}

#[cfg(unix)]
#[test]
fn discovery_does_not_follow_directory_symlinks() {
    let dir = TempDir::new();
    let root = dir.path().to_string();
    write(&root, "src/value.ms", "");
    let test = write(&root, "src/value_test.ms", "");
    std::os::unix::fs::symlink(join(&root, "src"), join(&root, "linked")).unwrap();
    let mut p = Project {
        root: root.clone(),
        source: join(&root, "linked"),
        ..Default::default()
    };
    assert_eq!(discover_modules(&p, true).unwrap(), vec![test.clone()]);
    p.source = write(&root, "a.ms", "");
    assert_eq!(
        discover_modules(&p, true).unwrap(),
        vec![p.source.clone(), test]
    );
}

#[cfg(unix)]
#[test]
fn discovery_reports_traversal_errors() {
    let dir = TempDir::new();
    let root = dir.path().to_string();
    let mut config = Project {
        root: root.clone(),
        source: join(&root, "missing"),
        ..Default::default()
    };
    assert!(
        discover_modules(&config, true).is_err(),
        "missing source directory was silently accepted"
    );
    let blocked = join(&root, "blocked");
    std::fs::create_dir(&blocked).unwrap();
    std::fs::set_permissions(
        &blocked,
        std::os::unix::fs::PermissionsExt::from_mode(0o000),
    )
    .unwrap();
    if std::fs::read_dir(&blocked).is_ok() {
        std::fs::set_permissions(
            &blocked,
            std::os::unix::fs::PermissionsExt::from_mode(0o700),
        )
        .unwrap();
        eprintln!("directory permissions not enforced (running as root?); skipping");
        return;
    }
    config.source = root.clone();
    for all in [false, true] {
        assert!(
            discover_modules(&config, all).is_err(),
            "unreadable directory was silently accepted"
        );
    }
    std::fs::set_permissions(
        &blocked,
        std::os::unix::fs::PermissionsExt::from_mode(0o700),
    )
    .unwrap();
}

#[test]
fn overlay_discovery_uses_source_and_test_exclusions() {
    let (_dir, p) = fixture(MANIFEST);
    let mut overlay = Overlay::new();
    for name in [
        "src/new.ms",
        "tests/new_test.ms",
        "src/.hidden/new.ms",
        "src/vendor/new.ms",
        "src/node_modules/new.ms",
        "scratch/new.ms",
        ".hidden/new_test.ms",
    ] {
        overlay.insert(join(&p.root, name), String::new());
    }
    let files = discover_modules_with_overlay(&p, true, &overlay).unwrap();
    assert_eq!(files.len(), 4, "overlay exclusions lost: {files:?}");
    assert!(
        files.windows(2).all(|w| w[0] < w[1]),
        "not sorted: {files:?}"
    );
}

#[test]
fn discovery_skips_nested_projects() {
    let dir = TempDir::new();
    let root = dir.path().to_string();
    let src = join(&root, "src");
    let own = write(&root, "test.ms", "");
    let own_src = write(&src, "value.ms", "");
    write(&root, "examples/demo/ms.toml", "");
    write(&root, "examples/demo/test.ms", "");
    write(&src, "inner/ms.toml", "");
    write(&src, "inner/value.ms", "");
    write(&src, "inner/value_test.ms", "");
    let p = Project {
        root: root.clone(),
        source: src,
        ..Default::default()
    };
    assert_eq!(discover_modules(&p, false).unwrap(), vec![own.clone()]);
    assert_eq!(
        sorted(discover_modules(&p, true).unwrap()),
        sorted(vec![own, own_src])
    );
}

#[test]
fn overlay_discovery_keeps_nested_projects_isolated() {
    let dir = TempDir::new();
    let root = dir.path().to_string();
    let source = join(&root, "src");
    write(&root, "src/inner/ms.toml", "");
    write(&root, "examples/demo/ms.toml", "invalid manifest");
    let saved = write(&root, "src/inner/saved_test.ms", "");
    let p = Project {
        root: root.clone(),
        source,
        ..Default::default()
    };
    let overlay = Overlay::from([
        (saved, String::new()),
        (join(&root, "src/inner/new.ms"), String::new()),
        (
            join(&root, "src/inner/new/deeper/new_test.ms"),
            String::new(),
        ),
        (join(&root, "examples/demo/new_test.ms"), String::new()),
        (join(&root, "src/ordinary/new_test.ms"), String::new()),
        (join(&root, "tests/new/deeper/bench.ms"), String::new()),
    ]);
    for all in [false, true] {
        assert_eq!(
            discover_modules_with_overlay(&p, all, &overlay).unwrap(),
            sorted(vec![
                join(&root, "src/ordinary/new_test.ms"),
                join(&root, "tests/new/deeper/bench.ms")
            ])
        );
    }

    // An explicitly selected source directory remains eligible, even if its
    // parent has a manifest or would normally be skipped during a root walk.
    for source in ["src/inner", "examples/demo", ".hidden", "vendor"] {
        write(&root, &format!("{source}/ms.toml"), "invalid manifest");
        let p = Project {
            root: root.clone(),
            source: join(&root, source),
            ..Default::default()
        };
        let file = join(&p.source, "new/deeper/value_test.ms");
        let overlay = Overlay::from([(file.clone(), String::new())]);
        assert!(
            discover_modules_with_overlay(&p, true, &overlay)
                .unwrap()
                .contains(&file)
        );
        assert!(
            !discover_modules_with_overlay(&p, false, &overlay)
                .unwrap()
                .contains(&file)
        );
    }
}

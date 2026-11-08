use crate::common;

use common::*;
use ms_driver::project::{Overlay, find_manifest, read_project, resolve_import, source_path};

#[test]
fn manifest_canonical_paths_and_comments() {
    let source = MANIFEST.replacen("sample", r#"sample # \"quoted\""#, 1)
        + "[aliases]\n\"@values\" = \"src\" # directory\n\"@one\" = \"src/value.ms\"\n";
    let (_dir, p) = fixture(&source);
    assert_eq!(p.name, r#"sample # "quoted""#);
    assert_eq!(p.configuration, source);
    assert_eq!(p.source, join(&p.root, "src"));
    assert_eq!(p.entry, join(&p.source, "main.ms"));
    for path in ["./value.ms", "@values/value.ms", "@one"] {
        let got = resolve_import(&p, &p.entry, path, &Overlay::new())
            .unwrap_or_else(|e| panic!("{path}: {e}"));
        assert_eq!(got, join(&p.source, "value.ms"), "{path}");
    }
}

#[test]
fn malformed_manifests() {
    let m = MANIFEST;
    let cases: Vec<(&str, String, &str)> = vec![
        (
            "no table",
            "name = \"sample\"\n".into(),
            "invalid manifest assignment",
        ),
        (
            "missing assignment",
            "[project]\nname\n".into(),
            "invalid manifest assignment",
        ),
        (
            "unknown table",
            format!("{m}[adapters]\n"),
            "unsupported manifest table",
        ),
        (
            "duplicate table",
            format!("{m}[project]\n"),
            "duplicate manifest table",
        ),
        (
            "duplicate key",
            format!("{m}name = \"other\"\n"),
            "duplicate manifest key",
        ),
        (
            "unknown key",
            format!("{m}version = \"1\"\n"),
            "unknown project key",
        ),
        (
            "missing required key",
            m.replacen("name = \"sample\"\n", "", 1),
            "requires name and source",
        ),
        (
            "unquoted value",
            m.replacen("\"sample\"", "sample", 1),
            "double-quoted",
        ),
        (
            "raw Go literal",
            m.replacen("\"sample\"", "`sample`", 1),
            "double-quoted",
        ),
        (
            "broken quote",
            m.replacen("\"sample\"", "\"sample", 1),
            "double-quoted",
        ),
        (
            "bad escape",
            m.replacen("sample", r"\q", 1),
            "quoted strings",
        ),
        (
            "source is file",
            m.replacen("\"src\"", "\"src/main.ms\"", 1),
            "existing directory",
        ),
        (
            "missing source",
            m.replacen("\"src\"", "\"missing\"", 1),
            "missing",
        ),
        (
            "entry extension",
            m.replacen("src/main.ms", "src/main.txt", 1),
            ".ms extension",
        ),
        (
            "entry is directory",
            m.replacen("src/main.ms", "src/directory.ms", 1),
            "regular file",
        ),
        (
            "reserved alias",
            format!("{m}[aliases]\n\"@std\" = \"src\"\n"),
            "invalid or reserved alias",
        ),
        (
            "invalid alias",
            format!("{m}[aliases]\n\"@2bad\" = \"src\"\n"),
            "invalid or reserved alias",
        ),
        (
            "alias chaining",
            format!("{m}[aliases]\n\"@one\" = \"@two\"\n"),
            "invalid alias target",
        ),
        (
            "duplicate alias",
            format!("{m}[aliases]\n\"@one\" = \"src\"\n\"@one\" = \"src\"\n"),
            "duplicate manifest key",
        ),
        (
            "reserved embed name",
            format!("{m}[embed]\n\"@std\" = \"src\"\n"),
            "invalid or reserved embed name",
        ),
        (
            "embed target is a file",
            format!("{m}[embed]\n\"@assets\" = \"src/main.ms\"\n"),
            "must name an existing directory",
        ),
        (
            "embed target is missing",
            format!("{m}[embed]\n\"@assets\" = \"missing\"\n"),
            "cannot be resolved",
        ),
        (
            "embed target outside the project",
            format!("{m}[embed]\n\"@assets\" = \"../outside\"\n"),
            "cannot be resolved",
        ),
        (
            "embed and alias share a name",
            format!("{m}[aliases]\n\"@both\" = \"src\"\n[embed]\n\"@both\" = \"src\"\n"),
            "both [aliases] and [embed]",
        ),
        (
            "unterminated quoted key",
            "[project]\n\"nam = \"x\"\n".into(),
            "ms.toml:2:1: invalid manifest assignment",
        ),
        (
            "unterminated quoted key line",
            "[project]\n\"nam\n".into(),
            "ms.toml:2:1: unterminated quoted key",
        ),
        (
            "NUL in value",
            m.replacen("src/main.ms", "src/ma\\u0000in.ms", 1),
            "ms.toml:4:9: manifest value for entry contains a NUL",
        ),
        (
            "line too long",
            format!("{m}# {}\n", "x".repeat(70000)),
            "ms.toml:5:1: line too long",
        ),
    ];
    for (name, source, want) in cases {
        let dir = TempDir::new();
        write(dir.path(), "src/main.ms", "");
        write(dir.path(), "src/main.txt", "");
        std::fs::create_dir(format!("{}/src/directory.ms", dir.path())).unwrap();
        let manifest = write(dir.path(), "ms.toml", &source);
        let error = read_project(&manifest).expect_err(name).to_string();
        assert!(error.contains(want), "{name}: got {error:?}, want {want:?}");
    }
}

#[test]
fn manifest_tolerates_bom_and_spaced_headers() {
    let source = "\u{feff}[ project ]\nname = \"sample\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[ aliases ]\n\"@a\" = \"src\"\n";
    let (_dir, p) = fixture(source);
    assert_eq!(p.name, "sample");
    assert!(!p.aliases["@a"].is_empty());
}

#[test]
fn import_forms_and_confinement() {
    let (_dir, p) = fixture(&format!(
        "{MANIFEST}[aliases]\n\"@dir\" = \"src\"\n\"@file\" = \"src/value.ms\"\n"
    ));
    for path in [
        "value.ms",
        "/value.ms",
        r".\dir\value.ms",
        "./value",
        "@missing/value.ms",
        "@dir_extra/value.ms",
        "@dir",
        "@dir/value",
        "@file/suffix.ms",
        "@std/value.ms",
    ] {
        assert!(
            resolve_import(&p, &p.entry, path, &Overlay::new()).is_err(),
            "accepted invalid import {path}"
        );
    }
    let outside_dir = TempDir::new();
    let outside = write(outside_dir.path(), "outside.ms", "");
    let rel = ms_driver::project::pathops::rel(&p.source, &outside).unwrap();
    let error = resolve_import(&p, &p.entry, &rel, &Overlay::new())
        .unwrap_err()
        .to_string();
    assert!(error.contains("escapes project root"), "{error}");
    for key in ["source", "entry", "@escape"] {
        let source = if key == "@escape" {
            format!("{MANIFEST}[aliases]\n\"@escape\" = \"{outside}\"\n")
        } else {
            let old = if key == "entry" { "src/main.ms" } else { "src" };
            MANIFEST.replacen(
                &format!("{key} = \"{old}\""),
                &format!("{key} = \"{outside}\""),
                1,
            )
        };
        let manifest = write(&p.root, "ms.toml", &source);
        let error = read_project(&manifest).expect_err(key).to_string();
        assert!(error.contains("escapes project root"), "{key}: {error}");
    }
}

#[test]
fn unsaved_source_paths() {
    let (_dir, p) = fixture(MANIFEST);
    let new_file = join(&p.source, "new.ms");
    let none = Overlay::new();
    assert!(source_path(&p.root, &new_file, &none).is_err());
    let with = |path: &str| Overlay::from([(path.to_string(), String::new())]);
    assert_eq!(
        source_path(&p.root, &new_file, &with(&new_file)).unwrap(),
        new_file
    );
    let missing_parent = join(&join(&p.root, "missing"), "new.ms");
    assert!(source_path(&p.root, &missing_parent, &with(&missing_parent)).is_err());
    let outside_dir = TempDir::new();
    let outside = join(outside_dir.path(), "new.ms");
    assert!(source_path(&p.root, &outside, &with(&outside)).is_err());
}

#[cfg(unix)]
#[test]
fn symlink_source_identity() {
    let (_dir, p) = fixture(MANIFEST);
    let link = join(&p.source, "link.ms");
    std::os::unix::fs::symlink(join(&p.source, "value.ms"), &link).unwrap();
    assert_eq!(
        source_path(&p.root, &link, &Overlay::new()).unwrap(),
        join(&p.source, "value.ms")
    );
    let outside = TempDir::new();
    for name in ["existing.ms", "unsaved.ms"] {
        if name == "existing.ms" {
            write(outside.path(), name, "");
        }
        let link = join(&p.source, name);
        std::os::unix::fs::symlink(join(outside.path(), name), &link).unwrap();
        let overlay = Overlay::from([(link.clone(), String::new())]);
        assert!(
            source_path(&p.root, &link, &overlay).is_err(),
            "overlay hid a symlink escape"
        );
    }
    let parent = join(&p.root, "linked");
    std::os::unix::fs::symlink(outside.path(), &parent).unwrap();
    let new_file = join(&parent, "new.ms");
    let overlay = Overlay::from([(new_file.clone(), String::new())]);
    assert!(
        source_path(&p.root, &new_file, &overlay).is_err(),
        "overlay escaped through its parent"
    );
}

#[test]
fn manifest_discovery_keeps_the_closest_project() {
    let dir = TempDir::new();
    let outer = write(dir.path(), "ms.toml", MANIFEST);
    let file = write(dir.path(), "nested/src/main.ms", "");
    assert_eq!(find_manifest(&file), Some(outer));
    let inner = write(dir.path(), "nested/ms.toml", "invalid configuration");
    assert_eq!(find_manifest(&file), Some(inner));
}

#[test]
fn absolute_import_diagnostic_is_not_a_relative_suggestion() {
    let (_dir, p) = fixture(MANIFEST);
    let error = resolve_import(&p, &p.entry, "/abs/money.ms", &Overlay::new())
        .unwrap_err()
        .to_string();
    assert!(
        error.contains("absolute import paths are not supported") && !error.contains(".//"),
        "{error}"
    );
}

#[test]
fn reserved_std_alias_is_not_suggested() {
    let dir = TempDir::new();
    write(dir.path(), "src/main.ms", "");
    let manifest = write(
        dir.path(),
        "ms.toml",
        "[project]\nname = \"sample\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[aliases]\nstd = \"src\"\n",
    );
    let error = read_project(&manifest).expect_err("std alias").to_string();
    assert!(error.contains("invalid or reserved alias std"), "{error}");
    assert!(!error.contains("did you mean"), "{error}");
}

#[test]
fn embed_names_resolve_to_generated_modules() {
    let source = MANIFEST.to_string() + "[embed]\n\"@assets\" = \"src\"\n";
    let (_dir, p) = fixture(&source);
    let got = resolve_import(&p, &p.entry, "@assets", &Overlay::new()).unwrap();
    assert_eq!(got, join(&join(&p.root, ".ms-embed"), "assets.ms"));
    let error = resolve_import(&p, &p.entry, "@assets/x.ms", &Overlay::new())
        .unwrap_err()
        .to_string();
    assert!(error.contains("import it as"), "{error}");
}

/// A link target that is not UTF-8 must not resolve to the file its lossy spelling names.
#[cfg(unix)]
#[test]
fn non_utf8_link_target_is_rejected() {
    use std::os::unix::ffi::OsStrExt;
    let (_dir, p) = fixture(MANIFEST);
    let raw = std::ffi::OsStr::from_bytes(b"\xff.ms");
    // The target need not exist: it must be rejected before traversal. APFS
    // rejects a non-UTF-8 filename, while a symlink can store its target bytes.
    write(&p.source, "\u{fffd}.ms", "export fn value() Int: 99\n");
    let link = join(&p.source, "dep.ms");
    std::os::unix::fs::symlink(raw, &link).unwrap();
    let error = source_path(&p.root, &link, &Overlay::new())
        .unwrap_err()
        .to_string();
    assert!(error.contains("not valid UTF-8"), "{error}");
}

/// Retargeting a link inside a chain changes the import, so every link the lookup passes through
/// is reported, and a loop of links ends the walk.
#[cfg(unix)]
#[test]
fn link_components_follow_link_chains_and_stop_on_loops() {
    use ms_driver::project::link_components;
    let (_dir, p) = fixture(MANIFEST);
    write(&p.source, "a.ms", "export fn value() Int: 7\n");
    let (mid, dep) = (join(&p.source, "mid.ms"), join(&p.source, "dep.ms"));
    std::os::unix::fs::symlink("a.ms", &mid).unwrap();
    std::os::unix::fs::symlink("mid.ms", &dep).unwrap();
    assert_eq!(
        link_components(&p.root, &dep),
        vec![dep.clone(), mid.clone()]
    );

    let (left, right) = (join(&p.source, "left.ms"), join(&p.source, "right.ms"));
    std::os::unix::fs::symlink("right.ms", &left).unwrap();
    std::os::unix::fs::symlink("left.ms", &right).unwrap();
    assert_eq!(
        link_components(&p.root, &left),
        vec![left.clone(), right.clone()]
    );
}

mod common;

use common::*;
use ms_project::read_project;

#[test]
fn library_entry_is_omitted_not_defaulted() {
    let source = MANIFEST.replacen("entry = \"src/main.ms\"\n", "", 1);
    let (dir, p) = fixture(&source);
    assert_eq!(p.entry, "");
    assert_eq!(p.source, join(&p.root, "src"));
    for entry in ["", "src", "src/missing.ms", "../outside.ms"] {
        let manifest = write(
            dir.path(),
            "ms.toml",
            &format!("{source}entry = \"{entry}\"\n"),
        );
        let error = read_project(&manifest).unwrap_err();
        let located = error
            .manifest_error()
            .unwrap_or_else(|| panic!("explicit bad entry {entry:?}: {error}"));
        assert_eq!(
            (located.location.line, located.location.column),
            (4, 9),
            "{entry:?}: {error}"
        );
    }
}

#[test]
fn alias_diagnostic_key_and_value_locations() {
    let prefix =
        "\u{feff}# café\r\n  [project]\r\nname = \"library\"\r\nsource = \"src\"\r\n[aliases]\r\n";
    let cases = [
        ("  \"@std\" = \"src\" # invalid key\r\n", "\"@std\"", 3),
        ("\u{2003}\"@std\" = \"src\"\r\n", "\"@std\"", 4),
        (
            "  \"@bad\" = \"@other\" # invalid value\r\n",
            "\"@other\"",
            12,
        ),
        (
            "  \"@bad\" = \"missing\" # unresolved target\r\n",
            "\"missing\"",
            12,
        ),
        (
            "  \"@bad\" = \"src\"\r\n  \"@bad\" = \"src\"\r\n",
            "\"@bad\"",
            3,
        ),
    ];
    for (line_text, token, column) in cases {
        let dir = TempDir::new();
        write(dir.path(), "src/value.ms", "");
        let source = format!("{prefix}{line_text}");
        let manifest = write(dir.path(), "ms.toml", &source);
        let error = read_project(&manifest).unwrap_err();
        let (line, offset) = if line_text.matches('\n').count() == 2 {
            (7, source.rfind(token).unwrap())
        } else {
            (6, source.find(token).unwrap())
        };
        let located = error.manifest_error().unwrap_or_else(|| panic!("{error}"));
        assert_eq!(located.location.file, "ms.toml");
        assert_eq!(
            (
                located.location.line,
                located.location.column,
                located.location.offset
            ),
            (line, column, offset),
            "{token}{line_text:?}: {error}"
        );
    }
}

#[cfg(unix)]
#[test]
fn alias_validation_is_sorted_and_confined() {
    let dir = TempDir::new();
    let root = dir.path();
    write(root, "src/value.ms", "");
    let outside_dir = TempDir::new();
    let outside = write(outside_dir.path(), "value.ms", "");
    let rel = ms_project::gopath::rel(root, &outside).unwrap();
    let prefix = "[project]\nname = \"library\"\nsource = \"src\"\n[aliases]\n";
    let source = format!("{prefix}\"@z\" = \"missing\"\n  \"@a\" = \"{rel}\"\n");
    for _ in 0..20 {
        let manifest = write(root, "ms.toml", &source);
        let error = read_project(&manifest).unwrap_err();
        let located = error.manifest_error().unwrap();
        assert_eq!(
            (located.location.line, located.location.column),
            (6, 10),
            "{error}"
        );
        let text = error.to_string();
        assert!(
            text.contains("escapes project root")
                && text.contains("copy the sources inside this project root"),
            "{text}"
        );
    }
    let link = join(&join(root, "src"), "external");
    std::os::unix::fs::symlink(outside_dir.path(), &link).unwrap();
    let manifest = write(
        root,
        "ms.toml",
        &format!("{prefix}\"@a\" = \"src/external\"\n"),
    );
    let error = read_project(&manifest).unwrap_err();
    let located = error.manifest_error().unwrap();
    assert_eq!((located.location.line, located.location.column), (5, 8));
    assert!(error.to_string().contains("escapes project root"));
}

#[cfg(unix)]
#[test]
fn explicit_entry_keeps_canonical_symlink_extension() {
    let (dir, p) = fixture(MANIFEST);
    std::os::unix::fs::symlink(&p.entry, join(&p.root, "launcher")).unwrap();
    let manifest = write(
        dir.path(),
        "ms.toml",
        &MANIFEST.replacen("src/main.ms", "launcher", 1),
    );
    let got = read_project(&manifest).unwrap();
    assert_eq!(got.entry, p.entry);
}

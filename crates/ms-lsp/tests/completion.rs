//! Source inserted by completion must remain valid Manuscript.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::text::{Position, Range};
use ms_rt as _;
use std::path::Path;

mod support;
use support::Workspace;

#[test]
fn numeric_imports_preserve_main_fuzzy_completions() {
    let workspace = Workspace::new("completion-numeric");
    let source = include_str!("completion/numeric-imports.ms");
    let document = Document::new(workspace.uri("numeric.ms"), source.to_string());
    for snippets in [false, true] {
        let items: Vec<_> = completion_at(
            &document,
            &Documents::new(),
            Position {
                line: 0,
                character: 14,
            },
            snippets,
        )
        .expect("completion")
        .into_iter()
        .map(|item| item.json())
        .collect();
        for (name, kind, detail, module, arguments) in [
            (
                "NormalizationForm",
                7,
                "NormalizationForm — @std/string.ms",
                "@std/string.ms",
                None,
            ),
            (
                "machine",
                3,
                "fn() Result[String, SystemError] — @std/os/process.ms",
                "@std/os/process.ms",
                Some(""),
            ),
            (
                "max_int",
                21,
                "Int — @std/math/math.ms",
                "@std/math/math.ms",
                None,
            ),
            (
                "max_safe_integer",
                21,
                "Int — @std/math/math.ms",
                "@std/math/math.ms",
                None,
            ),
            (
                "min_safe_integer",
                21,
                "Int — @std/math/math.ms",
                "@std/math/math.ms",
                None,
            ),
            (
                "remainder",
                3,
                "fn(Float, Float) Float — @std/math/math.ms",
                "@std/math/math.ms",
                Some("left: ${1:left}, right: ${2:right}"),
            ),
            (
                "ieee_remainder",
                3,
                "fn(Float, Float) Float — @std/math/math.ms",
                "@std/math/math.ms",
                Some("left: ${1:left}, right: ${2:right}"),
            ),
            (
                "remainder_wide",
                3,
                "fn(UInt64, UInt64, UInt64) Result[UInt64, NumberError] — @std/math/math.ms",
                "@std/math/math.ms",
                Some("high: ${1:high}, low: ${2:low}, divisor: ${3:divisor}"),
            ),
        ] {
            let matches: Vec<_> = items
                .iter()
                .filter(|item| item.get("label").and_then(|j| j.as_str()) == Some(name))
                .collect();
            assert_eq!(matches.len(), 1, "{name}: {items:?}");
            let item = matches[0];
            assert_eq!(
                item.get("kind").and_then(|j| j.as_i64()),
                Some(kind),
                "{name}"
            );
            assert_eq!(
                item.get("detail").and_then(|j| j.as_str()),
                Some(detail),
                "{name}"
            );
            let insertion = if snippets {
                arguments
                    .map(|args| format!("{name}({args})$0"))
                    .unwrap_or_else(|| name.to_string())
            } else {
                name.to_string()
            };
            assert_eq!(
                item.get("insertTextFormat").and_then(|j| j.as_i64()),
                Some(if snippets && arguments.is_some() {
                    2
                } else {
                    1
                }),
                "{name}"
            );
            let edit = item.get("textEdit").expect("text edit");
            assert_eq!(
                edit.get("newText").and_then(|j| j.as_str()),
                Some(insertion.as_str()),
                "{name}"
            );
            let range = Range::from_json(edit.get("range").unwrap()).unwrap();
            let start = ms_lsp::text::offset(source, range.start).unwrap();
            let end = ms_lsp::text::offset(source, range.end).unwrap();
            assert_eq!(&source[start..end], "main", "{name}");
            let imports = item
                .get("additionalTextEdits")
                .and_then(|j| j.as_array())
                .expect("auto import");
            assert_eq!(imports.len(), 1, "{name}");
            assert_eq!(
                imports[0].get("newText").and_then(|j| j.as_str()),
                Some(format!("import {name} from \"{module}\"\n").as_str()),
                "{name}"
            );
            let range = Range::from_json(imports[0].get("range").unwrap()).unwrap();
            assert_eq!(
                range.start,
                Position {
                    line: 0,
                    character: 0
                },
                "{name}"
            );
            assert_eq!(range.end, range.start, "{name}");
        }
    }
}

#[test]
fn checksum_imports_preserve_numeric_fuzzy_completions() {
    let workspace = Workspace::new("completion-checksum");
    let source = include_str!("completion/checksum-imports.ms");
    let document = Document::new(workspace.uri("checksum.ms"), source.to_string());
    for snippets in [false, true] {
        let items: Vec<_> = completion_at(
            &document,
            &Documents::new(),
            Position {
                line: 1,
                character: 12,
            },
            snippets,
        )
        .expect("completion")
        .into_iter()
        .map(|item| item.json())
        .collect();
        for (name, kind, detail, module, arguments) in [
            ("Float32", 7, "Float32", None, None),
            ("Int32", 7, "Int32", None, None),
            ("UInt32", 7, "UInt32", None, None),
            (
                "sha384",
                3,
                "fn(Bytes) Bytes — @std/crypto.ms",
                Some("@std/crypto.ms"),
                Some("${1:data}"),
            ),
            (
                "win32",
                3,
                "fn() PathOperations — @std/os/fs.ms",
                Some("@std/os/fs.ms"),
                Some(""),
            ),
            (
                "Crc32",
                7,
                "Crc32 — @std/data/checksum.ms",
                Some("@std/data/checksum.ms"),
                None,
            ),
            (
                "Adler32",
                7,
                "Adler32 — @std/data/checksum.ms",
                Some("@std/data/checksum.ms"),
                None,
            ),
            (
                "crc32",
                3,
                "fn(Bytes) UInt32 — @std/data/checksum.ms",
                Some("@std/data/checksum.ms"),
                Some("${1:data}"),
            ),
            (
                "adler32",
                3,
                "fn(Bytes) UInt32 — @std/data/checksum.ms",
                Some("@std/data/checksum.ms"),
                Some("${1:data}"),
            ),
            (
                "base32_encode",
                3,
                "fn(Bytes, Bool, Bool) String — @std/data/encoding.ms",
                Some("@std/data/encoding.ms"),
                Some("data: ${1:data}"),
            ),
            (
                "base32_decode",
                3,
                "fn(String, Bool, Bool, Int?) Result[Bytes, EncodingError] — @std/data/encoding.ms",
                Some("@std/data/encoding.ms"),
                Some("text: ${1:text}"),
            ),
        ] {
            let matches: Vec<_> = items
                .iter()
                .filter(|item| item.get("label").and_then(|j| j.as_str()) == Some(name))
                .collect();
            assert_eq!(matches.len(), 1, "{name}: {items:?}");
            let item = matches[0];
            assert_eq!(
                item.get("kind").and_then(|j| j.as_i64()),
                Some(kind),
                "{name}"
            );
            assert_eq!(
                item.get("detail").and_then(|j| j.as_str()),
                Some(detail),
                "{name}"
            );
            assert_eq!(
                item.get("insertTextFormat").and_then(|j| j.as_i64()),
                Some(if snippets && arguments.is_some() {
                    2
                } else {
                    1
                }),
                "{name}"
            );
            let insertion = if snippets {
                arguments
                    .map(|args| format!("{name}({args})$0"))
                    .unwrap_or_else(|| name.to_string())
            } else {
                name.to_string()
            };
            let edit = item.get("textEdit").expect("text edit");
            assert_eq!(
                edit.get("newText").and_then(|j| j.as_str()),
                Some(insertion.as_str()),
                "{name}"
            );
            let range = Range::from_json(edit.get("range").unwrap()).unwrap();
            let start = ms_lsp::text::offset(source, range.start).unwrap();
            let end = ms_lsp::text::offset(source, range.end).unwrap();
            assert_eq!(&source[start..end], "3", "{name}");
            if let Some(module) = module {
                let edits = item
                    .get("additionalTextEdits")
                    .and_then(|j| j.as_array())
                    .expect("auto import");
                assert_eq!(edits.len(), 1, "{name}");
                assert_eq!(
                    edits[0].get("newText").and_then(|j| j.as_str()),
                    Some(format!("import {name} from \"{module}\"\n").as_str())
                );
                let range = Range::from_json(edits[0].get("range").unwrap()).unwrap();
                assert_eq!(
                    range.start,
                    Position {
                        line: 0,
                        character: 0
                    }
                );
                assert_eq!(range.end, range.start);
            } else {
                assert!(item.get("additionalTextEdits").is_none(), "{name}");
            }
        }
    }
}

#[test]
fn for_snippet_inserts_a_checked_loop() {
    let workspace = Workspace::new("completion-snippet");
    let source = include_str!("completion/for-snippet-inserts-a-checked-loop.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        let mut document = Document::new(workspace.uri("completion.ms"), source);
        assert!(Path::new(&document.path()).is_absolute());
        assert!(!Path::new(&document.path()).exists(), "unsaved document");
        let at = Position {
            line: 1,
            character: 6,
        };
        let item = completion_at(&document, &Documents::new(), at, true)
            .expect("completion")
            .into_iter()
            .map(|item| item.json())
            .find(|item| item.get("label").and_then(|j| j.as_str()) == Some("for"))
            .expect("for snippet");
        assert_eq!(
            item.get("insertTextFormat").and_then(|j| j.as_i64()),
            Some(2)
        );
        let edit = item.get("textEdit").expect("text edit");
        let range = Range::from_json(edit.get("range").expect("range")).expect("valid range");
        let start = ms_lsp::text::offset(&document.text, range.start).expect("start");
        let end = ms_lsp::text::offset(&document.text, range.end).expect("end");
        assert_eq!(&document.text[start..end], "fo");
        // Fill by placeholder name even if the tab order changes.
        let insertion = edit
            .get("newText")
            .and_then(|j| j.as_str())
            .expect("snippet")
            .replace("${1:item}", "item")
            .replace("${2:items}", "[1, 2]")
            .replace("$0", "return unit")
            .replace('\n', "\n    ");
        document.text.replace_range(start..end, &insertion);
        let checked = analyze(&document, &Documents::new());
        assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        assert!(checked.program.is_some(), "inserted source must check");
        assert_eq!(Path::new(&checked.source_root), workspace.root.as_path());
    }
}

#[test]
fn a_native_document_uri_checks_unsaved_text_instead_of_disk() {
    let workspace = Workspace::new("completion-overlay");
    let name = "edited é #%.ms";
    let path = workspace.path(name);
    let stale = "not valid Manuscript\n";
    std::fs::write(&path, stale).expect("disk source");
    let source = "fn value() Int:\n    return 7\n";
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        let document = Document::new(workspace.uri(name), source);
        assert!(Path::new(&document.path()).is_absolute());
        assert_eq!(std::fs::read_to_string(document.path()).unwrap(), stale);
        let checked = analyze(&document, &Documents::new());
        assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
        assert!(checked.program.is_some(), "unsaved source must check");
        assert_eq!(Path::new(&checked.source_root), workspace.root.as_path());
        let module = checked.module(&document).expect("checked document");
        assert_eq!(&*module.source, document.text.as_str());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), stale);
    }
}

#[test]
fn an_opaque_record_offers_no_fields_outside_its_file() {
    let workspace = Workspace::new("completion-opaque");
    std::fs::write(
        workspace.path("gate.ms"),
        include_str!("completion/opaque-gate.ms"),
    )
    .expect("gate source");
    let labels = |name: &str, source: &str, line: usize, character: usize| {
        let document = Document::new(workspace.uri(name), source.to_string());
        completion_at(
            &document,
            &Documents::new(),
            Position { line, character },
            false,
        )
        .expect("completion")
        .into_iter()
        .filter_map(|item| {
            item.json()
                .get("label")
                .and_then(|j| j.as_str())
                .map(str::to_string)
        })
        .collect::<Vec<_>>()
    };
    let outside = labels(
        "main.ms",
        include_str!("completion/opaque-outside.ms"),
        4,
        14,
    );
    assert!(outside.contains(&"show".to_string()), "{outside:?}");
    assert!(!outside.contains(&"id".to_string()), "{outside:?}");
    let inside = labels(
        "gate.ms",
        include_str!("completion/opaque-inside.ms"),
        5,
        20,
    );
    assert!(inside.contains(&"id".to_string()), "{inside:?}");
}

#[test]
fn alternative_cases_complete_bare_unless_opaque_elsewhere() {
    let workspace = Workspace::new("completion-cases");
    std::fs::write(
        workspace.path("shapes.ms"),
        "export type Shape:\n    case Circle(r: Float)\n    case Sq(s: Float)\n\nexport opaque type Hidden:\n    case Secret\n    case Other\n",
    )
    .expect("shapes source");
    let labels = |source: &str, line: usize, character: usize| {
        let document = Document::new(workspace.uri("main.ms"), source.to_string());
        completion_at(
            &document,
            &Documents::new(),
            Position { line, character },
            false,
        )
        .expect("completion")
        .into_iter()
        .filter_map(|item| {
            item.json()
                .get("label")
                .and_then(|j| j.as_str())
                .map(str::to_string)
        })
        .collect::<Vec<_>>()
    };
    let source = "import Shape, Hidden from \"./shapes.ms\"\n\nfn f() Int:\n    let _a = Cir\n    return 0\n";
    let found = labels(source, 3, 16);
    assert!(found.contains(&"Circle".to_string()), "{found:?}");
    let source = "import Shape, Hidden from \"./shapes.ms\"\n\nfn f() Int:\n    let _a = Sec\n    return 0\n";
    let found = labels(source, 3, 16);
    assert!(!found.contains(&"Secret".to_string()), "{found:?}");
    let source =
        "import Hidden from \"./shapes.ms\"\n\nfn f() Int:\n    let _a = Hidden.\n    return 0\n";
    let found = labels(source, 3, 19);
    assert!(!found.contains(&"Secret".to_string()), "{found:?}");
}

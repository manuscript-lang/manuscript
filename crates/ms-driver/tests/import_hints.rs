//! Import suggestions use the checked graph's source root, including their fixes.

use crate::common;

use common::*;
use ms_driver::{CheckRequest, LoadOptions, check_graph, load_file};
use ms_rt as _;
use ms_syntax::{Phase, Pos};

#[test]
fn type_import_fixes_skip_functions_with_the_same_name() {
    for export in [
        include_str!("import_hints/function-export.ms"),
        include_str!("import_hints/constant-export.ms"),
    ] {
        type_import_fix_skips_value(export);
    }
}

fn type_import_fix_skips_value(export: &str) {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let source = include_str!("import_hints/type-use.ms");
    let path = write(dir.path(), "main.ms", source);
    write(dir.path(), "values.ms", export);
    let checked = check_graph(
        syms,
        load_file(syms, &path, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert_eq!(checked.diagnostics.len(), 1, "{:?}", checked.diagnostics);
    let issue = &checked.diagnostics[0];
    assert_eq!(
        issue.message,
        "unknown type Bytes; add: import Bytes from \"@std/bytes.ms\""
    );
    let fix = issue.fix.as_ref().expect("type import fix");
    let mut repaired = source.to_string();
    repaired.insert_str(fix.pos.offset as usize, &fix.replacement);
    write(dir.path(), "main.ms", &repaired);
    let checked = check_graph(
        syms,
        load_file(syms, &path, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert!(checked.success(), "{:?}", checked.diagnostics);
}

#[test]
fn value_import_fixes_still_offer_functions_and_constants() {
    let syms = ms_syntax::Names::global();
    for (export, source) in [
        (
            include_str!("import_hints/function-export.ms"),
            include_str!("import_hints/function-use.ms"),
        ),
        (
            include_str!("import_hints/constant-export.ms"),
            include_str!("import_hints/constant-use.ms"),
        ),
    ] {
        let dir = TempDir::new();
        let path = write(dir.path(), "main.ms", source);
        write(dir.path(), "values.ms", export);
        let checked = check_graph(
            syms,
            load_file(syms, &path, LoadOptions::default()),
            CheckRequest::default(),
        );
        assert_eq!(checked.diagnostics.len(), 1, "{:?}", checked.diagnostics);
        let fix = checked.diagnostics[0]
            .fix
            .as_ref()
            .expect("value import fix");
        assert_eq!(fix.replacement, "import Bytes from \"./values.ms\"\n");
        let mut repaired = source.to_string();
        repaired.insert_str(fix.pos.offset as usize, &fix.replacement);
        write(dir.path(), "main.ms", &repaired);
        let checked = check_graph(
            syms,
            load_file(syms, &path, LoadOptions::default()),
            CheckRequest::default(),
        );
        assert!(checked.success(), "{:?}", checked.diagnostics);
    }
}

#[test]
fn standard_functions_are_not_offered_as_type_imports() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let path = write(
        dir.path(),
        "main.ms",
        include_str!("import_hints/function-type-use.ms"),
    );
    let checked = check_graph(
        syms,
        load_file(syms, &path, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert_eq!(checked.diagnostics.len(), 1, "{:?}", checked.diagnostics);
    let issue = &checked.diagnostics[0];
    assert!(issue.message.starts_with("unknown type panic;"));
    assert!(!issue.message.contains("add: import"), "{}", issue.message);
    assert!(issue.fix.is_none(), "{:?}", issue.fix);
}

#[test]
fn project_import_fix_resolves_from_the_diagnostic_module() {
    let syms = ms_syntax::Names::global();
    let dir = TempDir::new();
    let manifest = write(dir.path(), "ms.toml", MANIFEST);
    let source = include_str!("import_hints/main.ms");
    write(dir.path(), "src/main.ms", source);
    write(
        dir.path(),
        "lib/blobs.ms",
        include_str!("import_hints/blobs.ms"),
    );
    let checked = check_graph(
        syms,
        load_file(syms, &manifest, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert_eq!(checked.diagnostics.len(), 1, "{:?}", checked.diagnostics);
    let issue = &checked.diagnostics[0];
    assert_eq!(&*issue.file, "src/main.ms");
    assert_eq!(issue.phase, Phase::Resolution);
    assert_eq!(
        issue.message,
        "unknown type Bytes; add: import Bytes from \"../lib/blobs.ms\""
    );
    let fix = issue.fix.as_ref().expect("machine-applicable import fix");
    assert_eq!(fix.pos, Pos::new(0, 1, 1));
    assert_eq!(fix.end, fix.pos);
    assert_eq!(fix.replacement, "import Bytes from \"../lib/blobs.ms\"\n");
    write(
        dir.path(),
        "src/main.ms",
        &format!("{}{source}", fix.replacement),
    );
    let repaired = check_graph(
        syms,
        load_file(syms, &manifest, LoadOptions::default()),
        CheckRequest::default(),
    );
    assert!(repaired.success(), "{:?}", repaired.diagnostics);
}

#[test]
fn import_fixes_preserve_file_effect_permissions() {
    let syms = ms_syntax::Names::global();
    let fixture = include_str!("import_hints/effect-header.ms");
    for project in [false, true] {
        for source in [fixture.to_string(), fixture.replace('\n', "\r\n")] {
            let dir = TempDir::new();
            let path = write(dir.path(), "main.ms", &source);
            if project {
                write(
                    dir.path(),
                    "blobs.ms",
                    include_str!("import_hints/blobs.ms"),
                );
            }
            let checked = check_graph(
                syms,
                load_file(syms, &path, LoadOptions::default()),
                CheckRequest::default(),
            );
            assert_eq!(checked.diagnostics.len(), 1, "{:?}", checked.diagnostics);
            let fix = checked.diagnostics[0].fix.as_ref().expect("import fix");
            assert_eq!(fix.pos.line, 3);
            assert_eq!(fix.end, fix.pos);
            let mut fixed = source.clone();
            fixed.insert_str(fix.pos.offset as usize, &fix.replacement);
            write(dir.path(), "main.ms", &fixed);
            let repaired = check_graph(
                syms,
                load_file(syms, &path, LoadOptions::default()),
                CheckRequest::default(),
            );
            assert!(repaired.success(), "{:?}", repaired.diagnostics);
            assert!(
                repaired
                    .program
                    .as_ref()
                    .unwrap()
                    .effect_violations
                    .is_empty(),
                "{fixed}"
            );
        }
    }
}

#[test]
fn generated_import_paths_round_trip_as_source() {
    for path in [
        "./plain.ms",
        "./a\"b.ms",
        r"./a\b.ms",
        "./a{b}.ms",
        "./a}b.ms",
        "./a\nb.ms",
        "./a\tb.ms",
        "./a\u{7}b.ms",
        "./é😀.ms",
        "./a\u{202e}b.ms",
    ] {
        let source = format!("{}\n", ms_driver::imports::import_statement("Widget", path));
        let module = ms_syntax::parser::parse(&"import.ms".into(), &source)
            .unwrap_or_else(|error| panic!("{path:?}: {error:?}"));
        assert_eq!(module.imports[0].path.as_ref(), path);
    }
}

#[test]
fn unrepresentable_import_paths_are_not_rewritten_as_another_path() {
    let expected = if cfg!(windows) {
        Some("./a/b.ms")
    } else {
        None
    };
    assert_eq!(
        ms_driver::imports::import_path("/root", r"/root/a\b.ms").as_deref(),
        expected
    );
}

//! Literal and operator hover uses the expression fallback rather than the
//! declaration/use index. Its ranges must stay in original UTF-16 coordinates.

use ms_lsp::analysis::{Document, Options, compile_source};
use ms_lsp::{nav, text, uri};
use ms_rt as _;

#[test]
fn fallback_hover_preserves_literal_operator_and_empty_ranges() {
    let syms = ms_syntax::Names::global();
    let fixture = include_str!("hover/fallback.ms");
    for source in [fixture.to_string(), fixture.replace('\n', "\r\n")] {
        // An unsaved file in a directory that does not exist, so its identity is its path on
        // every platform (macOS resolves the parent of a new file, and `/tmp` is a link there).
        let file = "/hover-fallback-unsaved/fallback.ms";
        let document = Document::new(uri::file_uri(file), &source);
        let analysis = compile_source(syms, file, &source, &Options::default());
        assert!(analysis.success(), "{:?}", analysis.diagnostics);
        let index = analysis.occurrence_index(syms);
        for (token, ty) in [
            ("123", "Int"),
            ("+", "Int"),
            ("true", "Bool"),
            ("unit", "Unit"),
        ] {
            let start = source.find(token).unwrap();
            for byte in start..start + token.len() {
                let position = text::position(&source, byte);
                assert!(nav::occurrence_at(syms, &analysis, &document, position, index).is_none());
                let hit =
                    nav::at(syms, &analysis, &document, position, index).expect("fallback hit");
                assert_eq!(hit.offset, start);
                assert_eq!(hit.text, token);
                assert_eq!(hit.info.ty.as_ref().unwrap().display(syms).to_string(), ty);
                let hover = nav::navigation(
                    syms,
                    &analysis,
                    &document,
                    position,
                    nav::Navigate::Hover,
                    index,
                );
                let range = text::Range::from_json(hover.get("range").expect("hover range"))
                    .expect("UTF-16 range");
                assert_eq!(range.start, text::position(&source, start));
                assert_eq!(range.end, text::position(&source, start + token.len()));
            }
            let after = text::position(&source, start + token.len());
            assert!(nav::at(syms, &analysis, &document, after, index).is_none());
        }
        for byte in [source.find("    return").unwrap(), source.len()] {
            assert!(
                nav::at(
                    syms,
                    &analysis,
                    &document,
                    text::position(&source, byte),
                    index
                )
                .is_none()
            );
        }
    }
}

#[test]
fn fallback_hover_keeps_clamped_and_invalid_snapshot_positions() {
    let syms = ms_syntax::Names::global();
    let source = include_str!("hover/fallback.ms");
    // An unsaved file in a directory that does not exist, so its identity is its path on
    // every platform (macOS resolves the parent of a new file, and `/tmp` is a link there).
    let file = "/hover-fallback-unsaved/fallback.ms";
    let analysis = compile_source(syms, file, source, &Options::default());
    assert!(analysis.success(), "{:?}", analysis.diagnostics);
    let index = analysis.occurrence_index(syms);
    let start = source.find("123").unwrap();
    let document = |text: &str| Document::new(uri::file_uri(file), text);
    for length in [start, start + 2] {
        let d = document(&source[..length]);
        let eof = text::position(&d.text, d.text.len());
        assert!(nav::at(syms, &analysis, &d, eof, index).is_none());
        if length > start {
            let at = text::position(&d.text, start);
            assert_eq!(nav::at(syms, &analysis, &d, at, index).unwrap().text, "123");
        }
    }
    let d = document(&source.replace("return value", "return\rvalue"));
    let at = text::position(&d.text, start);
    assert!(text::offset(&d.text, at).is_err());
    assert_eq!(nav::at(syms, &analysis, &d, at, index).unwrap().text, "123");

    let d = document(&source.replacen("123", "😀", 1));
    let start_position = text::position(&d.text, start);
    for column in [1, 2] {
        let at = text::Position {
            line: start_position.line,
            character: start_position.character + column,
        };
        assert_eq!(nav::at(syms, &analysis, &d, at, index).unwrap().text, "123");
    }
}

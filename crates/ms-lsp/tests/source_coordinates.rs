//! Malformed Unicode source still needs valid UTF-16 ranges in the server.

use ms_lsp::json::Json;
use ms_lsp::text::{self, Range};
use ms_rt as _;

mod support;
use support::{Script, Workspace};

const INVALID: &str = include_str!("source_coordinates/invalid-unicode.ms");

#[test]
fn scanner_tokens_keep_unicode_scalar_boundaries() {
    for source in ["😀", "é 日 𝄞 + value", "😀😀", "# 😀\n😀"] {
        for token in text::editor_tokens(source) {
            assert!(
                source.is_char_boundary(token.start),
                "{source:?}: {token:?}"
            );
            assert!(source.is_char_boundary(token.end), "{source:?}: {token:?}");
        }
    }
}

#[test]
fn unicode_lexer_errors_cover_a_complete_utf16_character() {
    for character in ["😀", "𝄞", "é", "日"] {
        for newline in ["\n", "\r\n"] {
            let ws = Workspace::new("unicode-diagnostics");
            let source = INVALID.replace('😀', character).replace('\n', newline);
            let uri = ws.uri("invalid.ms");
            let mut script = Script::initialize(ws.root.to_str().unwrap(), false);
            script.open(&uri, &source, 1);
            let messages = script.rust();
            let publication = messages
                .iter()
                .find(|message| {
                    message.get("method").and_then(Json::as_str)
                        == Some("textDocument/publishDiagnostics")
                        && message
                            .get("params")
                            .and_then(|params| params.get("uri"))
                            .and_then(Json::as_str)
                            == Some(uri.as_str())
                })
                .expect("diagnostic publication");
            let diagnostics = publication
                .get("params")
                .and_then(|params| params.get("diagnostics"))
                .and_then(Json::as_array)
                .expect("diagnostics");
            let offset = source.find(character).unwrap();
            let expected = Range {
                start: text::position(&source, offset),
                end: text::position(&source, offset + character.len()),
            };
            let diagnostic = diagnostics
                .iter()
                .find(|diagnostic| {
                    diagnostic
                        .get("range")
                        .and_then(Range::from_json)
                        .is_some_and(|range| range.start == expected.start)
                })
                .unwrap_or_else(|| panic!("{character:?}: {diagnostics:?}"));
            let range = Range::from_json(diagnostic.get("range").unwrap()).unwrap();
            assert_eq!(range, expected, "{character:?}: {diagnostic:?}");
            assert_eq!(text::offset(&source, range.start), Ok(offset));
            assert_eq!(
                text::offset(&source, range.end),
                Ok(offset + character.len())
            );
        }
    }
}

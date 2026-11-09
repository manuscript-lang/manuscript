//! Streaming coordinates preserve strict and forgiving semantic-token output.

use ms_lsp::analysis::Document;
use ms_lsp::json;
use ms_lsp::semantic::semantic_tokens;
use ms_lsp::text::{self, Position};
use ms_rt as _;

#[test]
fn semantic_positions_preserve_strict_and_forgiving_output() {
    let syms = ms_syntax::Names::global();
    for (source, expected) in [
        (
            include_str!("semantic_positions/valid.src"),
            include_str!("semantic_positions/valid.json"),
        ),
        (
            include_str!("semantic_positions/unfinished.src"),
            include_str!("semantic_positions/unfinished.json"),
        ),
    ] {
        let expected = json::parse(expected).unwrap();
        for source in [source.to_string(), source.replace('\n', "\r\n")] {
            let d = Document::new("file:///tmp/semantic-positions.ms", &source);
            let actual = semantic_tokens(syms, None, &[], &d);
            assert_eq!(actual, expected);
            let data = actual.get("data").unwrap().as_array().unwrap();
            let (tokens, remainder) = data.as_chunks::<5>();
            assert!(remainder.is_empty());
            let mut start = Position::default();
            for token in tokens {
                let line_delta = token[0].as_i64().unwrap() as usize;
                let character_delta = token[1].as_i64().unwrap() as usize;
                start.line += line_delta;
                start.character = if line_delta == 0 {
                    start.character + character_delta
                } else {
                    character_delta
                };
                let end = Position {
                    character: start.character + token[2].as_i64().unwrap() as usize,
                    ..start
                };
                assert!(text::offset(&source, start).is_ok());
                assert!(text::offset(&source, end).is_ok());
            }
        }
    }
}

#[test]
fn multiline_semantic_positions_match_crlf() {
    let syms = ms_syntax::Names::global();
    for literal in [
        "\"\"\"\n        hello 😀\n\n        world é\n        \"\"\"",
        "r\"\"\"\n        hello 😀\n\n        world é\n        \"\"\"",
        "\"\"\"\n        hello {1}\n        world 😀\n        \"\"\"",
    ] {
        let source =
            format!("fn text() String:\n    return {literal}\n\nfn next() Int:\n    return 1\n");
        ms_syntax::lexer::lex(&std::sync::Arc::from("test.ms"), &source).unwrap();
        let lf = Document::new("file:///tmp/semantic-multiline.ms", &source);
        let expected = semantic_tokens(syms, None, &[], &lf);
        for source in [
            source.clone(),
            source.replace('\n', "\r\n"),
            source.replacen('\n', "\r\n", 4),
        ] {
            let document = Document::new("file:///tmp/semantic-multiline.ms", &source);
            let actual = semantic_tokens(syms, None, &[], &document);
            assert_eq!(actual, expected, "{source:?}");
            let data = actual.get("data").unwrap().as_array().unwrap();
            let mut start = Position::default();
            let mut string_lines = 0;
            for token in data.chunks_exact(5) {
                let delta_line = token[0].as_i64().unwrap();
                let delta_character = token[1].as_i64().unwrap();
                assert!(delta_line >= 0 && delta_character >= 0);
                start.line += delta_line as usize;
                start.character = if delta_line == 0 {
                    start.character + delta_character as usize
                } else {
                    delta_character as usize
                };
                let end = Position {
                    character: start.character + token[2].as_i64().unwrap() as usize,
                    ..start
                };
                assert!(text::offset(&source, start).is_ok());
                assert!(text::offset(&source, end).is_ok());
                if token[3].as_i64() == Some(3) {
                    string_lines += 1;
                    let line = source.lines().nth(start.line).unwrap();
                    let expected_start = if string_lines == 1 { 11 } else { 0 };
                    assert_eq!(start.character, expected_start);
                    assert_eq!(end.character, line.encode_utf16().count());
                }
            }
            assert_eq!(string_lines, 4, "opening, two content lines and closing");
        }
    }
}

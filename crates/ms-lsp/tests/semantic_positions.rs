//! Streaming coordinates preserve strict and forgiving semantic-token output.

use ms_lsp::analysis::Document;
use ms_lsp::json;
use ms_lsp::semantic::semantic_tokens;
use ms_lsp::text::{self, Position};
use ms_rt as _;

#[test]
fn semantic_positions_preserve_strict_and_forgiving_output() {
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
            let actual = semantic_tokens(None, &[], &d);
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

use std::sync::Arc;

#[test]
fn rejected_multibyte_text_characters_start_at_a_utf8_boundary() {
    let file = Arc::from("spans.ms");
    for character in [
        '\u{202a}', '\u{202b}', '\u{202c}', '\u{202d}', '\u{202e}', '\u{2066}', '\u{2067}',
        '\u{2068}', '\u{2069}',
    ] {
        check_text_error(&file, &format!("a{character}b"), character, "bidirectional");
    }
    for character in ['é', '中', '🦀'] {
        check_text_error(
            &file,
            &format!("\\u{character}"),
            character,
            "Unicode escapes use",
        );
        check_text_error(
            &file,
            &format!("\\u{{{character}}}"),
            character,
            "invalid Unicode scalar escape",
        );
    }
}

fn check_text_error(file: &Arc<str>, text: &str, character: char, message: &str) {
    for literal in [format!("\"{text}\""), format!("\"{{\"{text}\"}}\"")] {
        for ending in ["\n", "\r\n"] {
            let source = format!(
                "fn head() Int: 1{ending}fn text() String: {literal}{ending}fn tail() Int: 2{ending}"
            );
            let expected = source.find(character).unwrap();
            let error = ms_syntax::parser::parse(file, &source).unwrap_err();
            assert!(error.message.contains(message), "{error:?}");
            assert!(
                source.is_char_boundary(error.pos.offset as usize),
                "{error:?}"
            );
            assert_eq!(error.pos.offset as usize, expected);
            assert_eq!(error.pos.line, 2);
            assert_eq!(
                error.pos.column as usize,
                expected - source.find('\n').unwrap()
            );

            let (module, errors) = ms_syntax::parse_partial(file, &source);
            assert_eq!(module.decls.len(), 2);
            assert_eq!(errors.len(), 1);
            assert_eq!(errors[0].pos, error.pos);
            assert_eq!(module.source.as_ref(), source);
        }
    }
}

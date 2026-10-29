use std::sync::Arc;

fn parse(source: &str) -> Result<(), String> {
    let file = Arc::from("bidi.ms");
    ms_syntax::parser::parse(&file, source)
        .map(|_| ())
        .map_err(|e| e.message)
}

#[test]
fn bidi_controls_are_rejected_in_comments_and_text() {
    for c in [
        '\u{202A}', '\u{202B}', '\u{202C}', '\u{202D}', '\u{202E}', '\u{2066}', '\u{2067}',
        '\u{2068}', '\u{2069}',
    ] {
        let comment = format!("fn f() Int:\n    # a {c} b\n    return 0\n");
        let message = parse(&comment).unwrap_err();
        assert!(message.contains("bidirectional"), "{message}");
        let text = format!("fn f() String:\n    return \"a{c}b\"\n");
        let message = parse(&text).unwrap_err();
        assert!(message.contains("\\u{202E}"), "{message}");
        let nested = format!("fn f() String:\n    return \"{{\"a{c}\"}}\"\n");
        assert!(parse(&nested).unwrap_err().contains("bidirectional"));
    }
}

#[test]
fn escapes_and_other_non_ascii_text_still_parse() {
    parse("fn f() String:\n    return \"\\u{202E} \u{e9} \u{2028} \u{1F600}\"\n").unwrap();
    parse("fn f() Int:\n    # \u{e9} \u{200E} \u{2029}\n    return 0\n").unwrap();
}

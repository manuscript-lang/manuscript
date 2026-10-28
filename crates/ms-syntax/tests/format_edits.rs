use std::sync::Arc;

#[test]
fn adjacent_source_edits_keep_exact_output_with_unicode_and_crlf() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/adjacent.src");
    let expected = include_str!("format_edits/adjacent.expected");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        ms_syntax::parser::parse(&file, &input).unwrap();
        let actual = ms_syntax::format(&file, &input).unwrap();
        assert_eq!(actual, expected);
        assert_eq!(ms_syntax::format(&file, &actual).unwrap(), actual);
    }
}

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

#[test]
fn statement_grouping_keeps_complete_inline_conditional_expressions() {
    let file: Arc<str> = Arc::from("bounds.ms");
    let source = include_str!("format_edits/expression_bounds.src");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        let before = ms_syntax::parser::parse(&file, &input).unwrap();
        let formatted = ms_syntax::format(&file, &input).unwrap();
        let after = ms_syntax::parser::parse(&file, &formatted).unwrap();
        assert_eq!(syntax_shape(&after), syntax_shape(&before));
        assert!(formatted.contains("# keep the complete conditional"));
        assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
    }
}

fn syntax_shape(module: &ms_syntax::Module) -> String {
    ms_syntax::dump::dump_module(module)
        .split(' ')
        .map(|word| {
            if word.split(':').count() == 3 && word.chars().all(|c| c.is_ascii_digit() || c == ':')
            {
                "position"
            } else {
                word
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

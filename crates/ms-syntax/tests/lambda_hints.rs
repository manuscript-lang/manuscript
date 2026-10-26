use std::sync::Arc;
#[test]
fn arrow_lambda_diagnostic_suggests_parseable_current_syntax() {
    let file = Arc::from("arrow.ms");
    for name in ["value", "item"] {
        let foreign = format!("{name} -> {name} + 1");
        let original = format!("def f() -> Int:\n    return apply({foreign})\n");
        for source in [original.clone(), original.replace('\n', "\r\n")] {
            let error = ms_syntax::parser::parse(&file, &source).unwrap_err();
            assert_eq!(error.code(), "MS1000");
            assert_eq!(error.pos.line, 2);
            assert_eq!(error.pos.offset as usize, source.rfind("->").unwrap());
            let suggestions = error
                .message
                .split('\'')
                .enumerate()
                .filter_map(|(i, s)| (i % 2 == 1).then_some(s))
                .collect::<Vec<_>>();
            assert_eq!(suggestions.len(), 2, "{}", error.message);
            for suggestion in suggestions {
                assert!(suggestion.starts_with("lambda "), "{suggestion}");
                let repaired = source.replace(&foreign, suggestion);
                ms_syntax::parser::parse(&file, &repaired).unwrap();
            }
        }
    }
}

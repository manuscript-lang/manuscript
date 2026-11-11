use std::sync::Arc;

#[test]
fn foreign_exception_hints_use_current_result_syntax() {
    let file = Arc::from("errors.ms");
    for keyword in ["throw", "raise", "catch", "except", "finally"] {
        let source = format!("fn f() Int:\n    {keyword}\n");
        let error = ms_syntax::parser::parse(&file, &source).unwrap_err();
        assert_eq!(error.code(), "MS1000");
        assert_eq!(error.pos.line, 2);
        assert_eq!(error.pos.column, 5);
        assert!(error.message.contains("'call()?'"), "{error}");
        assert!(error.message.contains("'if value := result:'"), "{error}");
        assert!(!error.message.contains("'try'"), "{error}");
        assert!(!error.message.contains("'if let'"), "{error}");
        assert!(
            error.fix.is_none(),
            "no one mechanical edit replaces exceptions"
        );
    }
    for repaired in [
        "fn f() Int!:\n    return call()?\n",
        "fn f() Int:\n    if value := result:\n        return value\n    else:\n        return 0\n",
    ] {
        ms_syntax::parser::parse(&file, repaired).unwrap();
    }
}

#[test]
fn eof_text_errors_locate_the_opening_and_explain_the_repair() {
    let file = Arc::from("text.ms");
    for ending in ["\n", "\r\n"] {
        for prefix in ["\"", "r\""] {
            let source = format!("fn head() Int: 1{ending}text := {prefix}héllo");
            let error = ms_syntax::parser::parse(&file, &source).unwrap_err();
            assert_eq!(error.code(), "MS1001");
            assert_eq!(error.pos.line, 2);
            assert_eq!(error.pos.column, 9);
            assert_eq!(error.pos.offset as usize, source.find(prefix).unwrap());
            assert!(error.message.contains("add the closing '\"'"), "{error}");
            let repaired = format!("{source}\"");
            ms_syntax::parser::parse(&file, &repaired).unwrap();
            assert!(error.to_json().contains("unterminated"));
        }
    }
}

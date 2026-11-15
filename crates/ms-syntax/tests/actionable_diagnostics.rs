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

#[test]
fn removed_let_forms_name_the_replacement_and_fix_only_a_plain_name() {
    let file = Arc::from("removed.ms");
    let parse = |statement: &str| {
        let source =
            format!("fn f(o: Int?) Int:\n    {statement}\n        return 1\n    return 0\n");
        ms_syntax::parser::parse(&file, &source).unwrap_err()
    };
    // A plain name: the edit rewrites `let v =` to `v :=`.
    let plain = parse("if let v = o:");
    assert!(plain.message.contains("'if let' was removed"), "{plain}");
    let fix = plain.fix.expect("a plain name has a fix");
    assert_eq!(fix.replacement, "v :=");
    assert_eq!((fix.pos.column, fix.end.column), (8, 15));
    // A pattern: the error still names the replacement, with no edit.
    for pattern in ["if let [a] = o:", "if let {a} = o:", "if let _ = o:"] {
        let error = parse(pattern);
        assert!(
            error.message.contains("'if let' was removed"),
            "{pattern}: {error}"
        );
        assert!(
            error.message.contains("'if value := optional:'"),
            "{pattern}: {error}"
        );
        assert!(error.fix.is_none(), "{pattern}: no single mechanical edit");
    }
    // `let` as an ordinary name is not touched.
    ms_syntax::parser::parse(
        &file,
        "fn f(let: Int) Int:\n    if let == 1:\n        return 1\n    return 0\n",
    )
    .unwrap();
}

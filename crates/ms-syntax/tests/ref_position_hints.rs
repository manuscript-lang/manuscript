use std::sync::Arc;

#[test]
fn misplaced_ref_names_where_ref_is_allowed() {
    let file = Arc::from("ref.ms");
    for source in [
        "fn f(x: ref String) Int:\n    return 0\n",
        "type T:\n    ref x: String\n",
        "type T:\n    x: List[ref String]\n",
    ] {
        let error = ms_syntax::parser::parse(&file, source).unwrap_err();
        assert!(error.message.contains("result type"), "{}", error.message);
        assert!(
            !error.message.contains("reserved word"),
            "{}",
            error.message
        );
    }
}

#[test]
fn punctuation_is_not_called_a_reserved_word() {
    let file = Arc::from("import.ms");
    let error = ms_syntax::parser::parse(&file, "import {} from \"./x.ms\"\n").unwrap_err();
    assert!(
        !error.message.contains("reserved word"),
        "{}",
        error.message
    );
}

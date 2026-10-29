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

#[test]
fn misplaced_opaque_says_where_it_goes() {
    let file = Arc::from("opaque.ms");
    for source in [
        "opaque fn g() Int:\n    return 1\n",
        "opaque interface I:\n    fn f() Int\n",
        "opaque export type T:\n    x: Int\n",
        "opaque\ntype T:\n    x: Int\n",
    ] {
        let error = ms_syntax::parser::parse(&file, source).unwrap_err();
        assert!(error.message.contains("opaque type"), "{}", error.message);
    }
}

#[test]
fn trailing_tokens_in_an_interpolation_are_not_an_end_of_file() {
    let file = Arc::from("interp.ms");
    for body in ["{1:}", "{1,2}", "{1 2}"] {
        let source = format!("fn f() String:\n    return \"{body}\"\n");
        let error = ms_syntax::parser::parse(&file, &source).unwrap_err();
        assert!(
            error.message.contains("holds one expression"),
            "{}",
            error.message
        );
    }
}

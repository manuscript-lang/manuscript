use std::sync::Arc;

#[test]
fn a_blank_line_after_a_comment_block_is_kept() {
    let file: Arc<str> = Arc::from("comments.ms");
    let source = "# module intro\n\n\n# about f\ndef f() -> Int:\n    return 1\n";
    let formatted = ms_syntax::format(&file, source).unwrap();
    assert_eq!(
        formatted,
        "# module intro\n\n# about f\ndef f() -> Int:\n    return 1\n"
    );
    assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
}

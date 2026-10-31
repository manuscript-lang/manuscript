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
fn parenthesized_return_type_gets_a_space_but_call_chains_do_not() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/paren_return.src");
    let expected = include_str!("format_edits/paren_return.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn optional_chains_never_break_before_the_question_mark_dot() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/optional_chain.src");
    let expected = include_str!("format_edits/optional_chain.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn comments_off_the_four_space_grid_format_in_one_stable_pass() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/misaligned_comment.src");
    let expected = include_str!("format_edits/misaligned_comment.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn off_grid_comment_before_a_block_argument_does_not_shift_its_suite() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/comment_before_block.src");
    let expected = include_str!("format_edits/comment_before_block.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn collapsing_a_flow_keeps_a_leading_dot_line_applied_to_the_whole_flow() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/flow_dot.src");
    let expected = include_str!("format_edits/flow_dot.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

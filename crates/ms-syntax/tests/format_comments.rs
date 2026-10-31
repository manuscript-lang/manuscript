use std::sync::Arc;

#[test]
fn a_blank_line_after_a_comment_block_is_kept() {
    let file: Arc<str> = Arc::from("comments.ms");
    let source = "# module intro\n\n\n# about f\nfn f() Int:\n    return 1\n";
    let formatted = ms_syntax::format(&file, source).unwrap();
    assert_eq!(
        formatted,
        "# module intro\n\n# about f\nfn f() Int:\n    return 1\n"
    );
    assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
}

#[test]
fn binding_group_comments_do_not_set_code_indentation() {
    let file: Arc<str> = Arc::from("groups.ms");
    let source = include_str!("format_comments/binding_groups.src");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        let before = ms_syntax::parser::parse(&file, &input).unwrap();
        let formatted = ms_syntax::format(&file, &input).unwrap();
        let after = ms_syntax::parser::parse(&file, &formatted).unwrap();
        assert_eq!(syntax_shape(&after), syntax_shape(&before));
        for comment in source.lines().filter(|line| line.trim().starts_with('#')) {
            assert!(formatted.contains(comment.trim()));
        }
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

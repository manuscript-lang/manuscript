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

#[test]
fn flow_prefixes_keep_comments_nested_groups_and_item_boundaries() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/flow_prefix.src");
    let expected = include_str!("format_edits/flow_prefix.expected");
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
        assert!(formatted.contains("// keep the complete conditional"));
        assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
    }
}

fn syntax_shape(module: &ms_syntax::Module) -> String {
    ms_syntax::dump::dump_module(ms_syntax::Names::global(), module)
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

#[test]
fn chain_hugging_preserves_first_call_width_and_later_operators() {
    let file: Arc<str> = Arc::from("call-prefix.ms");
    let source = include_str!("format_edits/call_prefix.src");
    let expected = include_str!("format_edits/call_prefix.expected");
    for input in [source.to_string(), source.replace('\n', "\r\n")] {
        ms_syntax::parser::parse(&file, &input).unwrap();
        let actual = ms_syntax::format(&file, &input).unwrap();
        assert_eq!(actual, expected);
        assert_eq!(ms_syntax::format(&file, &actual).unwrap(), actual);
    }
}

#[test]
fn long_bare_import_wraps_one_name_per_line() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/long_import.src");
    let expected = include_str!("format_edits/long_import.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn long_import_of_a_name_spelled_from_keeps_name_and_path() {
    let file: Arc<str> = Arc::from("edits.ms");
    let path = format!("{}.ms", "x".repeat(70));
    for (names, count) in [("from", 1), ("a, from", 2)] {
        let source = format!("import {names} from \"{path}\"\n");
        for input in [source.clone(), source.replace('\n', "\r\n")] {
            let formatted = ms_syntax::format(&file, &input).unwrap();
            let module = ms_syntax::parser::parse(&file, &formatted).expect(&formatted);
            assert_eq!(module.imports.len(), count, "{formatted}");
            assert!(module.imports.iter().all(|i| i.path.as_ref() == path));
            assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
        }
    }
}

#[test]
fn a_long_index_assignment_wraps_only_its_value() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/index_assign.src");
    let expected = include_str!("format_edits/index_assign.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn compaction_joins_guards_and_shortens_self_assignments() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = include_str!("format_edits/compact.src");
    let expected = include_str!("format_edits/compact.expected");
    assert_eq!(ms_syntax::format(&file, source).unwrap(), expected);
    assert_eq!(ms_syntax::format(&file, expected).unwrap(), expected);
}

#[test]
fn leading_whitespace_formats_to_one_tab_per_level() {
    let file: Arc<str> = Arc::from("tabs.ms");
    let tabbed = "fn f(n: Int) Int:\n\tvar t = 0\n\tfor i in 0..n:\n\t\tif i > 1:\n\t\t\tt += i\n\treturn t\n\nfn text() String:\n\treturn \"\"\"\n\t\ta\tb\n\t\t\"\"\"\n";
    let formatted = ms_syntax::format(&file, tabbed).unwrap();
    // Code indentation becomes tabs; text content is kept byte for byte.
    assert!(formatted.starts_with(
        "fn f(n: Int) Int:\n\tvar t = 0\n\tfor i in 0..n:\n\t\tif i > 1:\n\t\t\tt += i\n"
    ));
    let (code, _) = tabbed.split_once("\nfn text").unwrap();
    let spaced = code.replace('\t', "    ");
    assert_eq!(
        ms_syntax::format(&file, &spaced).unwrap(),
        ms_syntax::format(&file, code).unwrap()
    );
    let piped = "fn f(xs: List[Int]) Int:\n\treturn xs\n\t\t| map(g)\n\t\t| sum()\n";
    assert_eq!(ms_syntax::format(&file, piped).unwrap(), piped);
    assert!(
        formatted.contains("\n\t\ta\tb\n\t\t\"\"\"\n"),
        "{formatted:?}"
    );
    assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
}

#[test]
fn tabs_after_spaces_and_inside_code_are_rejected() {
    let file: Arc<str> = Arc::from("tabs.ms");
    let after_spaces = ms_syntax::parser::parse(&file, "fn f() Int:\n  \treturn 1\n").unwrap_err();
    assert!(
        after_spaces.message.contains("cannot follow spaces"),
        "{after_spaces:?}"
    );
    let inside = ms_syntax::parser::parse(&file, "fn f() Int:\n\treturn\t1\n").unwrap_err();
    assert!(
        inside
            .message
            .contains("tabs are allowed only in indentation"),
        "{inside:?}"
    );
}

#[test]
fn tab_indented_dot_and_pipe_continuations_match_four_space_source() {
    let file: Arc<str> = Arc::from("tabs.ms");
    let dump = |source: &str| {
        let module = ms_syntax::parser::parse(&file, source).unwrap();
        ms_syntax::dump::dump_module(ms_syntax::Names::global(), &module)
    };
    for (tabbed, spaced) in [
        (
            "fn f() Int:\n\treturn [1]\n\t\t| length\n",
            "fn f() Int:\n    return [1]\n        | length\n",
        ),
        (
            "fn f() String:\n\treturn 1\n\n\t\t// note\n\t\t.to_string()\n",
            "fn f() String:\n    return 1\n\n        // note\n        .to_string()\n",
        ),
    ] {
        // Positions differ by column, so compare the tree shape without them.
        let strip = |text: String| text.split_whitespace().collect::<Vec<_>>().len();
        assert_eq!(strip(dump(tabbed)), strip(dump(spaced)), "{tabbed:?}");
    }
}

#[test]
fn imports_merge_sort_and_split_into_sections() {
    let file: Arc<str> = Arc::from("edits.ms");
    for name in [
        "import_sections",
        "import_lone",
        "import_commented",
        "comment_wrap",
    ] {
        let dir = format!("{}/tests/format_edits", env!("CARGO_MANIFEST_DIR"));
        let source = std::fs::read_to_string(format!("{dir}/{name}.src")).unwrap();
        let expected = std::fs::read_to_string(format!("{dir}/{name}.expected")).unwrap();
        let actual = ms_syntax::format(&file, &source).unwrap();
        assert_eq!(actual, expected, "{name}");
        assert_eq!(ms_syntax::format(&file, &actual).unwrap(), actual, "{name}");
    }
}

#[test]
fn an_if_whose_multiline_header_joins_is_compacted_in_the_same_run() {
    let file: Arc<str> = Arc::from("edits.ms");
    let source = "fn f(mode: Int) Int:\n    if not (\n            mode == 2\n        ):\n            return 2\n    return 3\n";
    let expected = "fn f(mode: Int) Int:\n\tif not (mode == 2): return 2\n\treturn 3\n";
    let once = ms_syntax::format(&file, source).unwrap();
    assert_eq!(once, expected);
    assert_eq!(ms_syntax::format(&file, &once).unwrap(), once);
}

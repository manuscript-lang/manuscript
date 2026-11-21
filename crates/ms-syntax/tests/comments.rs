//! Comment syntax: `//` to end of line and whole-line, non-nesting `/* */` blocks.

use std::sync::Arc;

fn file() -> Arc<str> {
    Arc::from("comments.ms")
}

fn parse(source: &str) -> Result<(), String> {
    ms_syntax::parser::parse(&file(), source)
        .map(|_| ())
        .map_err(|e| e.message)
}

#[test]
fn line_comments_stand_alone_and_trail_code() {
    parse("// top\nfn f() Int:\n\t// inside\n\treturn 1 // trailing\n").unwrap();
}

#[test]
fn hash_is_not_a_comment() {
    let message = parse("# old\nfn f() Int:\n\treturn 1\n").unwrap_err();
    assert!(message.contains("comments start with '//'"), "{message}");
}

#[test]
fn text_keeps_comment_markers() {
    parse("fn f() String:\n\treturn \"a // b /* c */ d\"\n").unwrap();
}

#[test]
fn block_comments_span_lines_and_ignore_layout() {
    let source = "/*\nfree form\n\t  any indentation\n*/\nfn f() Int:\n\t/*\n  odd\n\t*/\n\treturn (\n\t\t/* inside parens */\n\t\t1\n\t)\n";
    parse(source).unwrap();
}

#[test]
fn single_line_block_may_end_with_a_line_comment() {
    parse("/* one line */ // and more\nfn f() Int:\n\treturn 1\n").unwrap();
}

#[test]
fn block_comment_errors() {
    let nested = parse("/* a /* b */ */\nfn f() Int:\n\treturn 1\n").unwrap_err();
    assert!(nested.contains("do not nest"), "{nested}");
    let open = parse("fn f() Int:\n\treturn 1\n/* never closed\n").unwrap_err();
    assert!(open.contains("unterminated block comment"), "{open}");
    let after = parse("/* a */ fn f() Int:\n\treturn 1\n").unwrap_err();
    assert!(after.contains("cannot follow a block comment"), "{after}");
    let trailing = parse("fn f() Int:\n\treturn 1 /* c */\n").unwrap_err();
    assert!(trailing.contains("must start its own line"), "{trailing}");
}

#[test]
fn block_comment_does_not_end_a_continued_pipe() {
    parse("fn f() Int:\n\treturn [1]\n\t\t// step\n\t\t| length\n").unwrap();
    parse("fn f() Int:\n\treturn [1]\n\t\t/* step */\n\t\t| length\n").unwrap();
}

#[test]
fn trailing_documentation_skips_nested_interpolated_text() {
    let source = include_str!("data/doc-trailing-interpolation.ms");
    for source in [source.to_string(), source.replace('\n', "\r\n")] {
        parse(&source).expect("valid nested text fixture");
        for (field, expected) in [
            ("annotated:", "the real note"),
            ("unannotated:", ""),
            ("nested:", "deeply nested"),
            ("escaped:", "escaped quote"),
        ] {
            let offset = source.find(field).unwrap();
            assert_eq!(ms_syntax::doc::trailing_comment(&source, offset), expected);
        }
    }
}

#[test]
fn trailing_documentation_tolerates_incomplete_surrounding_code() {
    let complete_text = "fn unfinished(text: String = f\"{\"http://x\"}\", // argument note";
    assert_eq!(
        ms_syntax::doc::trailing_comment(complete_text, 0),
        "argument note"
    );
    let incomplete_text = "fn unfinished(text: String = f\"{\"http://x\"} // still text";
    assert_eq!(ms_syntax::doc::trailing_comment(incomplete_text, 0), "");
}

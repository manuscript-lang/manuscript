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

fn format(source: &str) -> String {
    ms_syntax::format(&file(), source).unwrap()
}

#[test]
fn line_comments_stand_alone_and_trail_code() {
    parse("// top\nfn f() Int:\n    // inside\n    return 1 // trailing\n").unwrap();
}

#[test]
fn hash_is_not_a_comment() {
    let message = parse("# old\nfn f() Int:\n    return 1\n").unwrap_err();
    assert!(message.contains("comments start with '//'"), "{message}");
}

#[test]
fn text_keeps_comment_markers() {
    parse("fn f() String:\n    return \"a // b /* c */ d\"\n").unwrap();
}

#[test]
fn block_comments_span_lines_and_ignore_layout() {
    let source = "/*\nfree form\n      any indentation\n*/\nfn f() Int:\n    /*\n  odd\n    */\n    return (\n        /* inside parens */\n        1\n    )\n";
    parse(source).unwrap();
}

#[test]
fn single_line_block_may_end_with_a_line_comment() {
    parse("/* one line */ // and more\nfn f() Int:\n    return 1\n").unwrap();
}

#[test]
fn block_comment_errors() {
    let nested = parse("/* a /* b */ */\nfn f() Int:\n    return 1\n").unwrap_err();
    assert!(nested.contains("do not nest"), "{nested}");
    let open = parse("fn f() Int:\n    return 1\n/* never closed\n").unwrap_err();
    assert!(open.contains("unterminated block comment"), "{open}");
    let after = parse("/* a */ fn f() Int:\n    return 1\n").unwrap_err();
    assert!(after.contains("cannot follow a block comment"), "{after}");
    let trailing = parse("fn f() Int:\n    return 1 /* c */\n").unwrap_err();
    assert!(trailing.contains("must start its own line"), "{trailing}");
}

#[test]
fn block_comment_does_not_end_a_continued_pipe() {
    parse("fn f() Int:\n    return [1]\n        // step\n        | length\n").unwrap();
    parse("fn f() Int:\n    return [1]\n        /* step */\n        | length\n").unwrap();
}

#[test]
fn formatter_keeps_block_contents_and_normalizes_trailing_gap() {
    let source =
        "fn f() Int:\n    /*\n    keep   this\n       and this\n    */\n    return 1 // x\n";
    let out = format(source);
    assert_eq!(
        out,
        "fn f() Int:\n    /*\n    keep   this\n       and this\n    */\n    return 1  // x\n"
    );
    assert_eq!(format(&out), out);
}

#[test]
fn formatter_is_idempotent_on_block_before_declaration() {
    let source = "/*\nDocs for f.\n  Indented line.\n*/\nfn f() Int:\n    return 1  // one\n";
    let out = format(source);
    assert_eq!(out, source);
}

#[test]
fn formatter_restores_many_comment_and_text_spans_in_order() {
    let mut source = String::new();
    for i in 0..128 {
        source.push_str(&format!(
            "/* docs {i}\n    keep this indentation\n*/\nfn text_{i}() String:\n    /* inside {i} */\n    return \"\"\"\n        first {i}\n        second\n        \"\"\"\n\n"
        ));
    }
    let formatted = format(&source);
    assert_eq!(formatted, source.trim_end().to_string() + "\n");
    assert_eq!(format(&formatted), formatted);
}

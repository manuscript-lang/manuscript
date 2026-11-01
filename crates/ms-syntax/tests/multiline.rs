//! Multi-line (`"""`) and raw (`r"""`) text literals.

use ms_syntax::dump::dump_module;
use ms_syntax::format;
use std::sync::Arc;

fn dump(source: &str) -> Result<String, String> {
    let file: Arc<str> = Arc::from("m.ms");
    ms_syntax::parser::parse(&file, source)
        .map(|m| dump_module(&m))
        .map_err(|e| format!("{}:{}: {}", e.pos.line, e.pos.column, e.message))
}

fn body(literal: &str) -> String {
    format!("fn f() String:\n    return {literal}\n")
}

/// The `(part ...)` entries of the returned literal.
fn parts(literal: &str) -> String {
    let out = dump(&body(literal)).unwrap();
    let start = out.find("(part ").expect("a text part");
    let end = out[start..].find(") ]").expect("end of parts") + start;
    out[start..end + 1].to_string()
}

fn error(literal: &str) -> String {
    dump(&body(literal)).unwrap_err()
}

#[test]
fn indentation_of_the_closing_line_is_removed() {
    assert_eq!(
        parts("\"\"\"\n    a\n      b\n    \"\"\""),
        "(part \"a\\x0a  b\" nil)"
    );
    // Less indentation under the closing quotes keeps the difference.
    assert_eq!(parts("\"\"\"\n    a\n  \"\"\""), "(part \"  a\" nil)");
}

#[test]
fn first_and_last_line_breaks_are_dropped_and_blank_lines_kept() {
    assert_eq!(parts("\"\"\"\n    \"\"\""), "(part \"\" nil)");
    assert_eq!(
        parts("\"\"\"\n    a\n\n    b\n\n    \"\"\""),
        "(part \"a\\x0a\\x0ab\\x0a\" nil)"
    );
    // A whitespace-only line may be shorter than the indentation.
    assert_eq!(
        parts("\"\"\"\n    a\n  \n    b\n    \"\"\""),
        "(part \"a\\x0a\\x0ab\" nil)"
    );
}

#[test]
fn escapes_quotes_and_interpolation_work_in_multiline_text() {
    let out = parts("\"\"\"\n    say \"hi\"\\t\\{x\\}\n    n = {1 + 2}\n    \"\"\"");
    assert!(out.contains("say \\x22hi\\x22\\x09{x}\\x0an = "), "{out}");
    // The interpolated `1` sits on line 4, column 10.
    assert!(out.contains("(expr 4:10:"), "{out}");
}

#[test]
fn raw_text_is_literal() {
    assert_eq!(
        parts("r\"\"\"\n    {\"a\": \"b\\n\", \"c\": [1, {2}]}\n    \"\"\""),
        "(part \"{\\x22a\\x22: \\x22b\\x5cn\\x22, \\x22c\\x22: [1, {2}]}\" nil)"
    );
}

#[test]
fn multiline_text_needs_its_own_lines() {
    assert!(error("\"\"\"abc\n    \"\"\"").contains("start on the line after"));
    assert!(error("\"\"\"\n    abc\"\"\"").contains("alone on its own line"));
    assert!(error("\"\"\"\n    abc\n").contains("unterminated multi-line text"));
    assert!(error("r\"\"\"\n    abc\n").contains("unterminated multi-line text"));
    let shallow = error("\"\"\"\n        a\n      b\n        \"\"\"");
    assert!(shallow.starts_with("4:1:"), "{shallow}");
    assert!(shallow.contains("indented less than"), "{shallow}");
}

#[test]
fn multiline_text_keeps_text_rules() {
    assert!(error("\"\"\"\n    \\q\n    \"\"\"").contains("unknown text escape"));
    assert!(error("\"\"\"\n    }\n    \"\"\"").contains("unmatched closing brace"));
    assert!(error("\"\"\"\n    {}\n    \"\"\"").contains("empty interpolation"));
    assert!(error("\"\"\"\n    {1 +\n    2}\n    \"\"\"").contains("newlines"));
    assert!(error("\"a{\"\"\"\n    b\n    \"\"\"}\"").contains("inside an interpolation"));
}

#[test]
fn interpolation_errors_point_into_the_right_line() {
    let message = error("\"\"\"\n    a\n    b {1 +} c\n    \"\"\"");
    assert!(message.starts_with("4:"), "{message}");
}

#[test]
fn formatting_is_idempotent_and_keeps_text() {
    let file: Arc<str> = Arc::from("m.ms");
    let source = "fn f(n: Int) String:\n    if n > 0:\n        return \"\"\"\n            a {n}\n              b\n            \"\"\"\n\n    return r\"\"\"\n        {\"x\": 1}\n        \"\"\"\n";
    let once = format(&file, source).unwrap();
    assert_eq!(once, source);
    assert_eq!(format(&file, &once).unwrap(), once);
}

#[test]
fn formatting_moves_text_with_the_line_it_lands_on() {
    let file: Arc<str> = Arc::from("m.ms");
    let long = "a_rather_long_argument_name_to_force_wrapping";
    let source = format!(
        "fn g(a: String, b: String) String:\n    return a + b\n\nfn f(x: String) String:\n    return g({long}, \"\"\"\n        t\n          u\n        \"\"\") + {long}\n"
    );
    let once = format(&file, &source).unwrap();
    println!("{once}");
    assert_eq!(format(&file, &once).unwrap(), once);
    assert_eq!(dump(&source).unwrap().matches("t\\x0a  u").count(), 1);
    assert_eq!(dump(&once).unwrap().matches("t\\x0a  u").count(), 1);
}

#[test]
fn names_and_paths_stay_one_line() {
    let file: Arc<str> = Arc::from("m.ms");
    for source in [
        "import a from \"\"\"\n    ./a.ms\n    \"\"\"\n",
        "test \"\"\"\n    name\n    \"\"\":\n    assert true\n",
    ] {
        let error = ms_syntax::parser::parse(&file, source).unwrap_err();
        assert!(error.message.contains("one-line text"), "{}", error.message);
    }
}

#[test]
fn recovery_keeps_declarations_around_column_zero_text() {
    let file: Arc<str> = Arc::from("m.ms");
    let source = "let banner = \"\"\"\nfirst\nlast\n\"\"\"\n\nfn good() Int:\n    return 1\n\nfn bad() Int:\n    return (\n";
    let (module, diagnostics) = ms_syntax::parse_partial(&file, source);
    assert!(!diagnostics.is_empty());
    let names = dump_module(&module);
    assert!(
        names.contains("\"banner\"") && names.contains("\"good\""),
        "{names}"
    );
}

#[test]
fn crlf_sources_give_the_same_text() {
    let lf = body("\"\"\"\n    a\n      b\n    \"\"\"");
    let crlf = lf.replace('\n', "\r\n");
    assert_eq!(
        parts_of(&dump(&lf).unwrap()),
        parts_of(&dump(&crlf).unwrap())
    );
}

fn parts_of(dump: &str) -> &str {
    let start = dump.find("(part ").unwrap();
    &dump[start..start + dump[start..].find(") ]").unwrap()]
}

#[test]
fn recovery_keeps_a_multi_line_import_path_in_one_chunk() {
    let file: Arc<str> = Arc::from("m.ms");
    let source = include_str!("data/multiline/import_path.ms");
    let (_, issues) = ms_syntax::parse_partial(&file, source);
    let messages: Vec<&str> = issues.iter().map(|d| d.message.as_str()).collect();
    assert_eq!(messages.len(), 1, "{messages:?}");
    assert!(messages[0].contains("one-line text"), "{messages:?}");
}

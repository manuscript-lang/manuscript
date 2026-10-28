use ms_syntax::ast::{Expr, ExprKind, TextPart};
use ms_syntax::visit::{self, Visitor};
use std::sync::Arc;

#[test]
fn nested_fstrings_keep_braces_inside_nested_text() {
    struct Texts(Vec<String>);
    impl Visitor for Texts {
        fn expr(&mut self, expr: &Expr) {
            if let ExprKind::Text(parts) = &expr.kind {
                for part in parts {
                    if let TextPart::Lit(text) = part {
                        self.0.push(text.to_string());
                    }
                }
            }
        }
    }
    let file: Arc<str> = Arc::from("nested.ms");
    for literal in ["}", "{", "é}🦀", "a{b}c"] {
        let escaped = literal.replace('{', "\\{").replace('}', "\\}");
        let source = format!("fn text() String: return \"{{\"{{identity(\"{escaped}\")}}\"}}\"\n");
        for source in [source.clone(), source.replace('\n', "\r\n")] {
            let module = ms_syntax::parser::parse(&file, &source).unwrap();
            let mut texts = Texts(Vec::new());
            for decl in &module.decls {
                visit::walk_decl(&mut texts, decl);
            }
            assert_eq!(texts.0, [literal]);
            let formatted = ms_syntax::format(&file, &source).unwrap();
            assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
            let damaged = "fn broken(\n".to_string() + &source;
            let (partial, diagnostics) = ms_syntax::parse_partial(&file, &damaged);
            assert!(!diagnostics.is_empty());
            assert_eq!(partial.decls.len(), 1);
            assert_eq!(partial.decls[0].pos.line, 2);
            assert_eq!(partial.decls[0].pos.offset as usize, "fn broken(\n".len());
        }
    }
}

#[test]
fn deeply_nested_fstrings_keep_each_interpolation_and_format_idempotently() {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(check_deeply_nested_fstrings)
        .unwrap()
        .join()
        .unwrap();
}

fn check_deeply_nested_fstrings() {
    struct Count(usize);
    impl Visitor for Count {
        fn expr(&mut self, expr: &Expr) {
            if matches!(expr.kind, ExprKind::Text(_)) {
                self.0 += 1;
            }
        }
    }

    let file: Arc<str> = Arc::from("nested.ms");
    for depth in [64, 128, 256] {
        let source = format!(
            "let text = {}1{}\n",
            "\"{".repeat(depth),
            "}\"".repeat(depth)
        );
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        let mut count = Count(0);
        for decl in &module.decls {
            visit::walk_decl(&mut count, decl);
        }
        assert_eq!(count.0, depth);
        let formatted = ms_syntax::format(&file, &source).unwrap();
        assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
    }
}

#[test]
fn nested_interpolation_errors_keep_their_original_positions_and_hints() {
    let file: Arc<str> = Arc::from("nested.ms");
    for source in ["let x = \"{\"{1 + }\"}\"\n", "let x = \"{\"{1 + }\"}\"\r\n"] {
        let error = ms_syntax::parser::parse(&file, source).unwrap_err();
        assert_eq!(
            (error.pos.offset, error.pos.line, error.pos.column),
            (16, 1, 17)
        );
        assert_eq!(error.end.unwrap().offset, 16);
        assert_eq!(
            error.message,
            "expected an expression, found end of line; write a value, name, call, or literal here ('{' at column 12 starts an interpolation; write \\{ and \\} for literal braces) ('{' at column 10 starts an interpolation; write \\{ and \\} for literal braces)"
        );
    }
    let error = ms_syntax::parser::parse(&file, "let x = \"{1)}\"\n").unwrap_err();
    assert_eq!(error.pos.offset, 12);
    assert!(error.message.starts_with("unmatched closing delimiter ')'"));
    let error = ms_syntax::parser::parse(&file, "let x = \"{)(}\"\n").unwrap_err();
    assert_eq!(error.pos.offset, 10);
    assert!(
        error
            .message
            .starts_with("expected an expression, found ')'")
    );
}

#[test]
fn nested_interpolations_inside_multiline_functions_keep_expression_forms() {
    let file: Arc<str> = Arc::from("nested.ms");
    for ending in ["\n", "\r\n"] {
        let source =
            format!("fn get() String:\n    let x = \"{{\"{{fn x: x}}\"}} {{1..2}}\"{ending}");
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        assert_eq!(module.decls.len(), 1);
        let formatted = ms_syntax::format(&file, &source).unwrap();
        assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
    }
}

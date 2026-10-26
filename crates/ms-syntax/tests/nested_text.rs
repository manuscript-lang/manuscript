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
        let source =
            format!("def text() -> String: return f\"{{f\"{{identity(\"{literal}\")}}\"}}\"\n");
        for source in [source.clone(), source.replace('\n', "\r\n")] {
            let module = ms_syntax::parser::parse(&file, &source).unwrap();
            let mut texts = Texts(Vec::new());
            for decl in &module.decls {
                visit::walk_decl(&mut texts, decl);
            }
            assert_eq!(texts.0, [literal]);
            let formatted = ms_syntax::format(&file, &source).unwrap();
            assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
            let damaged = "def broken(\n".to_string() + &source;
            let (partial, diagnostics) = ms_syntax::parse_partial(&file, &damaged);
            assert!(!diagnostics.is_empty());
            assert_eq!(partial.decls.len(), 1);
            assert_eq!(partial.decls[0].pos.line, 2);
            assert_eq!(partial.decls[0].pos.offset as usize, "def broken(\n".len());
        }
    }
}

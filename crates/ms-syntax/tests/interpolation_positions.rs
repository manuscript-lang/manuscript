use ms_syntax::ast::{Expr, ExprKind};
use ms_syntax::visit::{self, Visitor};
use ms_syntax::{Module, Pos};
use std::sync::Arc;

#[derive(Default)]
struct Names(Vec<Pos>);

impl Visitor for Names {
    fn expr(&mut self, expr: &Expr) {
        if let ExprKind::Name(name) = expr.kind
            && name.as_str() == "value"
        {
            self.0.push(expr.pos);
        }
    }
}

fn names(module: &Module) -> Vec<Pos> {
    let mut visitor = Names::default();
    for decl in &module.decls {
        visit::walk_decl(&mut visitor, decl);
    }
    visitor.0
}

fn expected_positions(source: &str) -> Vec<Pos> {
    source
        .match_indices("value")
        .map(|(at, _)| {
            let prefix = &source[..at];
            Pos::new(
                at as u32,
                prefix.bytes().filter(|b| *b == b'\n').count() as u32 + 1,
                (at - prefix.rfind('\n').map_or(0, |line| line + 1)) as u32 + 1,
            )
        })
        .collect()
}

#[test]
fn many_interpolations_keep_byte_positions_and_node_ids() {
    let file = Arc::from("positions.ms");
    for ending in ["\n", "\r\n"] {
        // Unicode and escape spellings count source bytes, not decoded characters.
        let source = format!(
            "fn head() Int: 1{ending}let text = \"{}\"{ending}",
            "é\\u{41}\\{literal\\}{value}{value + value} ".repeat(1024)
        );
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        assert_eq!(names(&module), expected_positions(&source));
        assert_eq!(module.node_count, 4 * 1024 + 6);
        let (partial, errors) = ms_syntax::parse_partial(&file, &source);
        assert!(errors.is_empty());
        assert_eq!(names(&partial), names(&module));
    }
}

#[test]
fn multiline_interpolations_keep_positions_across_literal_lines() {
    let file = Arc::from("positions.ms");
    let source = format!(
        "fn head() Int: 1\nlet text = \"\"\"\n{}    \"\"\"\n",
        "    é\\n {value} and {value + value}\n    literal only\n".repeat(64)
    );
    let module = ms_syntax::parser::parse(&file, &source).unwrap();
    assert_eq!(names(&module), expected_positions(&source));
    let formatted = ms_syntax::format(&file, &source).unwrap();
    assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
}

#[test]
fn later_interpolation_errors_keep_positions_and_brace_columns() {
    let file = Arc::from("positions.ms");
    for prefix in ["é {value} ".repeat(64), "{value}".repeat(64)] {
        for ending in ["\n", "\r\n"] {
            let source = format!(
                "fn head() Int: 1{ending}let text = \"{prefix}{{value(item = 2)}}\"{ending}"
            );
            let error = ms_syntax::parser::parse(&file, &source).unwrap_err();
            assert!(error.message.starts_with("argument labels use a colon;"));
            assert_eq!(error.pos.offset as usize, source.rfind('=').unwrap());
            let brace = source.rfind('{').unwrap();
            let line_start = source[..brace].rfind('\n').unwrap() + 1;
            assert!(
                error
                    .message
                    .contains(&format!("'{{' at column {}", brace - line_start + 1))
            );
            let (partial, errors) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(partial.decls.len(), 1);
            assert_eq!(errors.len(), 1);
            assert_eq!(errors[0].to_string(), error.to_string());
        }
    }
}

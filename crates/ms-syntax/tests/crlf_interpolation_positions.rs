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

fn positions(module: &Module) -> Vec<Pos> {
    let mut visitor = Names::default();
    for declaration in &module.decls {
        visit::walk_decl(&mut visitor, declaration);
    }
    visitor.0
}

fn expected(source: &str) -> Vec<Pos> {
    source
        .match_indices("value")
        .map(|(offset, _)| {
            let prefix = &source[..offset];
            Pos::new(
                offset as u32,
                prefix.bytes().filter(|byte| *byte == b'\n').count() as u32 + 1,
                (offset - prefix.rfind('\n').map_or(0, |last| last + 1)) as u32 + 1,
            )
        })
        .collect()
}

#[test]
fn multiline_interpolation_positions_use_original_crlf_offsets() {
    let file = Arc::from("positions.ms");
    let fixture = include_str!("data/crlf-interpolation.src");
    for endings in [vec!["\n"], vec!["\r\n"], vec!["\n", "\r\n", "\r\n"]] {
        let source: String = fixture
            .split_inclusive('\n')
            .enumerate()
            .map(|(line, text)| {
                text.trim_end_matches('\n').to_owned() + endings[line % endings.len()]
            })
            .collect();
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        assert_eq!(positions(&module), expected(&source));
        let (partial, diagnostics) = ms_syntax::parse_partial(&file, &source);
        assert!(diagnostics.is_empty(), "{diagnostics:?}");
        assert_eq!(positions(&partial), expected(&source));

        let broken = source + "fn broken(\n";
        let (partial, diagnostics) = ms_syntax::parse_partial(&file, &broken);
        assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
        assert_eq!(positions(&partial), expected(&broken));
    }
}

#[test]
fn multiline_interpolation_diagnostics_use_original_crlf_offsets() {
    let file = Arc::from("positions.ms");
    let fixture = include_str!("data/crlf-interpolation.src");
    for expression in ["value(item = 2)", "value +", "value + @"] {
        let source = fixture
            .replace("{value}", &format!("{{{expression}}}"))
            .replace('\n', "\r\n");
        let diagnostic = ms_syntax::parser::parse(&file, &source).unwrap_err();
        let offset = if expression.contains('=') {
            source.find("item =").unwrap() + "item ".len()
        } else if expression.contains('@') {
            source.find('@').unwrap()
        } else {
            source.find("value +}").unwrap() + "value +".len()
        };
        assert_eq!(diagnostic.pos.offset as usize, offset, "{diagnostic:?}");
        if expression.contains('=') {
            assert_eq!(diagnostic.end.unwrap().offset as usize, offset + 1);
        }
        let (_, diagnostics) = ms_syntax::parse_partial(&file, &source);
        assert!(
            diagnostics.iter().any(|error| error.pos == diagnostic.pos),
            "{diagnostics:?}"
        );
    }
}

#[test]
fn first_crlf_interpolation_starts_at_original_byte_21() {
    let file = Arc::from("positions.ms");
    let source = include_str!("data/crlf-interpolation-minimal.src").replace('\n', "\r\n");
    let module = ms_syntax::parser::parse(&file, &source).unwrap();
    assert_eq!(positions(&module), vec![Pos::new(21, 2, 6)]);
}

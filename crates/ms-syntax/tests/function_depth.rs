use ms_syntax::{
    DeclKind, Expr, ExprKind, TypeKind,
    lexer::lex,
    parser::parse,
    token::Tok,
    visit::{self, Visitor},
};
use std::sync::Arc;

#[test]
fn multiline_function_types_keep_only_the_enclosing_function_suite() {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(|| {
            for depth in [1, 16, 64, 128, 256, 512] {
                let source = include_str!("data/function-depth.src")
                    .replace("OPEN\n", &"    fn(\n".repeat(depth))
                    .replace("CLOSE\n", &"    ) Unit\n".repeat(depth));
                for ending in ["\n", "\r\n"] {
                    let source = source.replace('\n', ending);
                    let file = Arc::from("function-depth.ms");
                    let lexed = lex(&file, &source).unwrap();
                    assert_eq!(
                        lexed.tokens.iter().filter(|t| t.kind == Tok::Fn).count(),
                        depth + 1
                    );
                    assert_eq!(
                        lexed
                            .tokens
                            .iter()
                            .filter(|t| t.kind == Tok::Indent)
                            .count(),
                        1
                    );
                    assert_eq!(
                        lexed
                            .tokens
                            .iter()
                            .filter(|t| t.kind == Tok::Dedent)
                            .count(),
                        1
                    );
                    let module = parse(&file, &source).unwrap();
                    let DeclKind::Fn(function) = &module.decls[0].kind else {
                        panic!("expected function")
                    };
                    assert_eq!(function.body[0].pos.line as usize, 2 * depth + 4);
                    let mut ty = function.params[0].ty.as_ref().unwrap();
                    for level in 0..depth {
                        let TypeKind::Fn { params, result } = &ty.kind else {
                            panic!("expected function type")
                        };
                        assert_eq!(ty.pos.line as usize, level + 2);
                        assert_eq!(ty.pos.column, 5);
                        assert_eq!(params.len(), 1);
                        assert_eq!(result.name(), "Unit");
                        ty = params[0].ty.as_ref().unwrap();
                    }
                    assert_eq!(ty.name(), "Int");
                }
            }
        })
        .unwrap()
        .join()
        .unwrap();
}

#[test]
fn delimited_function_and_match_suites_keep_their_boundaries() {
    struct Counts(usize, usize);
    impl Visitor for Counts {
        fn expr(&mut self, expr: &Expr) {
            if matches!(expr.kind, ExprKind::Lambda(_)) {
                self.0 += 1;
            }
            if matches!(expr.kind, ExprKind::Match { .. }) {
                self.1 += 1;
            }
        }
    }
    for ending in ["\n", "\r\n"] {
        let source = include_str!("data/delimited-header-depths.src").replace('\n', ending);
        let file = Arc::from("headers.ms");
        let lexed = lex(&file, &source).unwrap();
        assert_eq!(
            lexed
                .tokens
                .iter()
                .filter(|t| t.kind == Tok::Indent)
                .count(),
            4
        );
        assert_eq!(
            lexed
                .tokens
                .iter()
                .filter(|t| t.kind == Tok::Dedent)
                .count(),
            4
        );
        let module = parse(&file, &source).unwrap();
        let mut counts = Counts(0, 0);
        for declaration in &module.decls {
            visit::walk_decl(&mut counts, declaration);
        }
        assert_eq!((counts.0, counts.1), (2, 1));
        let formatted = ms_syntax::format(&file, &source).unwrap();
        assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
    }
}

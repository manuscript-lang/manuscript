use ms_syntax::{DeclKind, ExprKind, Pos, StmtKind};
use std::sync::Arc;

#[test]
fn rejected_statement_blanking_keeps_original_utf8_offsets_and_neighbors() {
    let file = Arc::from("blanking.ms");
    for rejected in [
        "@x".to_owned(),
        "@é中🦀\t\0".to_owned(),
        format!("@{}", "é中🦀x".repeat(4096)),
    ] {
        for ending in ["\n", "\r\n"] {
            let source = include_str!("recovery_blanking/statement.src")
                .replace("REJECTED", &rejected)
                .replace('\n', ending);
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.source.as_ref(), source);
            assert_eq!(module.decls.len(), 3);
            assert_eq!(diagnostics.len(), 1);
            let bad_at = source.find('@').unwrap();
            assert_eq!(diagnostics[0].pos, Pos::new(bad_at as u32, 3, 5));
            let DeclKind::Fn(function) = &module.decls[1].kind else {
                panic!("expected recovered function")
            };
            assert_eq!(function.body.len(), 1);
            let StmtKind::Return(Some(value)) = &function.body[0].kind else {
                panic!("expected retained return")
            };
            assert!(matches!(value.kind, ExprKind::Name(_)));
            let expected = source.find("return value").unwrap() + "return ".len();
            assert_eq!(value.pos, Pos::new(expected as u32, 4, 12));
            assert_eq!(
                module.decls[2].pos.offset as usize,
                source.find("fn tail").unwrap()
            );
            let clean = source.replacen(&rejected, &" ".repeat(rejected.len()), 1);
            let expected = ms_syntax::parser::parse(&file, &clean).unwrap();
            assert_eq!(module.node_count, expected.node_count);
            assert_eq!(
                format!("{:?}", module.decls),
                format!("{:?}", expected.decls)
            );
        }
    }
}

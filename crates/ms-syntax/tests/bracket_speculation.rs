use ms_syntax::{DeclKind, Expr, ExprKind, Module, StmtKind, parser::parse};
use std::{collections::HashSet, sync::Arc};

fn result(module: &Module) -> &Expr {
    let DeclKind::Fn(function) = &module.decls[0].kind else {
        panic!("expected function")
    };
    let StmtKind::Return(Some(value)) = &function.body[0].kind else {
        panic!("expected return")
    };
    value
}

#[test]
fn failed_type_speculation_preserves_nested_index_trees_and_positions() {
    for depth in [1, 2, 4, 8, 64, 128, 256] {
        let expression = "data[".repeat(depth) + "0" + &"]".repeat(depth);
        for ending in ["\n", "\r\n"] {
            let source = include_str!("data/bracket-expression.src")
                .replace("EXPR", &expression)
                .replace('\n', ending);
            let module = parse(&Arc::from("index.ms"), &source).unwrap();
            assert_eq!(module.node_count as usize, 2 * depth + 7);
            let mut value = result(&module);
            let mut ids = HashSet::new();
            let start = source.find("return ").unwrap() + "return ".len();
            for level in 0..depth {
                assert!(ids.insert(value.id));
                let ExprKind::Index { left, index } = &value.kind else {
                    panic!("expected index")
                };
                let ExprKind::Name(name) = &left.kind else {
                    panic!("expected receiver")
                };
                assert_eq!(name.as_str(), "data");
                assert!(ids.insert(left.id));
                assert_eq!(left.pos.offset as usize, start + 5 * level);
                assert_eq!(left.pos.line, 2);
                assert_eq!(left.pos.column as usize, 12 + 5 * level);
                value = index;
            }
            let ExprKind::Number(number) = &value.kind else {
                panic!("expected numeric index")
            };
            assert_eq!(number.as_str(), "0");
            assert!(ids.insert(value.id));
            assert!(ids.into_iter().all(|id| id.0 < module.node_count));
        }
    }
}

#[test]
fn replayed_failure_retains_ids_consumed_before_the_failure() {
    let source =
        include_str!("data/bracket-expression.src").replace("EXPR", "data[Box[Foo[Bar] + 1]]");
    let module = parse(&Arc::from("index.ms"), &source).unwrap();
    // Recorded from the parser before failure replay: speculative Foo[Bar]
    // consumes IDs even though the following '+' forces expression parsing.
    assert_eq!(module.node_count, 21);
    assert_eq!(result(&module).id.0, 18);
}

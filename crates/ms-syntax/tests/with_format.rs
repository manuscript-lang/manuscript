use ms_syntax::ast::{DeclKind, StmtKind};
use std::sync::Arc;

fn shape(module: &ms_syntax::ast::Module) -> String {
    ms_syntax::dump::dump_module(module)
        .split_whitespace()
        .map(|word| {
            let fields: Vec<_> = word.split(':').collect();
            if fields.len() == 3
                && fields.iter().all(|field| {
                    !field.is_empty() && field.bytes().all(|byte| byte.is_ascii_digit())
                })
            {
                "@"
            } else {
                word
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn long_with_initializers_group_only_the_resource_expression() {
    let file: Arc<str> = Arc::from("resource.ms");
    for binding in ["let", "var"] {
        for initializer in [
            "root.long_member_name.long_member_name.long_member_name.long_member_name.open()",
            "very_long_resource_name_one + very_long_resource_name_two + very_long_resource_name_three",
        ] {
            let source = format!(
                "def f() -> Int:\n    with {binding} handle = {initializer}:\n        return 1\n"
            );
            let before = ms_syntax::parser::parse(&file, &source).unwrap();
            for input in [source.clone(), source.replace('\n', "\r\n")] {
                let once = ms_syntax::format(&file, &input).unwrap();
                let after = ms_syntax::parser::parse(&file, &once).unwrap();
                let resource = |module: &ms_syntax::ast::Module| {
                    let DeclKind::Fn(function) = &module.decls[0].kind else {
                        panic!("expected function")
                    };
                    let StmtKind::With {
                        name,
                        mutable,
                        body,
                        ..
                    } = &function.body[0].kind
                    else {
                        panic!("expected with")
                    };
                    (name.to_string(), *mutable, body.len())
                };
                assert_eq!(resource(&before), resource(&after));
                assert_eq!(shape(&before), shape(&after));
                assert!(
                    once.contains(&format!("with {binding} handle = (")),
                    "{once}"
                );
                assert_eq!(ms_syntax::format(&file, &once).unwrap(), once);
            }
        }
    }
}

#[test]
fn deeply_nested_groups_preserve_layout_and_syntax() {
    let file: Arc<str> = Arc::from("nested.ms");
    for depth in [64usize, 128] {
        let source = format!("let x = {}1{}\n", "(".repeat(depth), ")".repeat(depth));
        let mut expected = String::from("let x = ");
        for level in 0..depth {
            if level > 0 {
                expected.push_str(&" ".repeat(4 * level));
            }
            expected.push_str("(\n");
        }
        expected.push_str(&" ".repeat(4 * depth));
        expected.push_str("1\n");
        for level in (0..depth).rev() {
            expected.push_str(&" ".repeat(4 * level));
            expected.push_str(")\n");
        }
        for input in [source.clone(), source.replace('\n', "\r\n")] {
            let formatted = ms_syntax::format(&file, &input).unwrap();
            assert_eq!(formatted, expected);
            assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
            let before = ms_syntax::parser::parse(&file, &source).unwrap();
            let after = ms_syntax::parser::parse(&file, &formatted).unwrap();
            assert_eq!(shape(&before), shape(&after));
        }
    }
}

use ms_syntax::{DeclKind, NodeId, TypeKind, TypeRef, parser::parse};
use std::{collections::HashSet, sync::Arc};

fn named(ty: &TypeRef, name: &str, arity: usize) {
    let TypeKind::Named { name: actual, args } = &ty.kind else {
        panic!("expected named type {name}");
    };
    assert_eq!(actual.as_str(), name);
    assert_eq!(args.len(), arity);
}

#[test]
fn type_suffixes_preserve_order_positions_and_distinct_node_ids() {
    for ending in ["\n", "\r\n"] {
        for suffix in ["?", "!", "!E", "?!E?", "!?!E?!"] {
            let source = include_str!("data/type-suffix.src")
                .replace("TYPE", &format!("Int{suffix}"))
                .replace('\n', ending);
            let module = parse(&Arc::from("suffix.ms"), &source).unwrap();
            let DeclKind::Fn(function) = &module.decls[0].kind else {
                panic!("expected function");
            };
            let mut wrappers = Vec::new();
            let mut suffixes = suffix.chars().peekable();
            while let Some(suffix) = suffixes.next() {
                let error = (suffix == '!').then(|| {
                    if suffixes.next_if_eq(&'E').is_some() {
                        "E"
                    } else {
                        "Error"
                    }
                });
                wrappers.push((suffix, error));
            }
            let mut ids = HashSet::new();
            let mut ty = &function.result;
            let offset = source.find("Int").unwrap() as u32;
            for (suffix, error) in wrappers.into_iter().rev() {
                assert!(ids.insert(ty.id));
                assert_eq!(
                    (ty.pos.offset, ty.pos.line, ty.pos.column),
                    (offset, 1, offset + 1)
                );
                named(
                    ty,
                    if suffix == '?' { "Optional" } else { "Result" },
                    if error.is_some() { 2 } else { 1 },
                );
                let TypeKind::Named { args, .. } = &ty.kind else {
                    unreachable!()
                };
                if let Some(error) = error {
                    named(&args[1], error, 0);
                    assert!(ids.insert(args[1].id));
                    assert_eq!(
                        args[1].pos.offset,
                        if error == "E" {
                            source.find('E').unwrap() as u32
                        } else {
                            offset
                        }
                    );
                }
                ty = &args[0];
            }
            named(ty, "Int", 0);
            assert!(ids.insert(ty.id));
            assert!(ids.into_iter().all(|NodeId(id)| id < module.node_count));
        }
    }
}

#[test]
fn long_type_suffix_chains_keep_every_wrapper() {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(|| {
            for depth in [16, 64, 128, 256, 512] {
                for suffix in ["?", "!"] {
                    let source = include_str!("data/type-suffix.src")
                        .replace("TYPE", &format!("Int{}", suffix.repeat(depth)));
                    let module = parse(&Arc::from("suffix.ms"), &source).unwrap();
                    let DeclKind::Fn(function) = &module.decls[0].kind else {
                        panic!("expected function")
                    };
                    let mut ty = &function.result;
                    for _ in 0..depth {
                        named(
                            ty,
                            if suffix == "?" { "Optional" } else { "Result" },
                            if suffix == "?" { 1 } else { 2 },
                        );
                        let TypeKind::Named { args, .. } = &ty.kind else {
                            unreachable!()
                        };
                        ty = &args[0];
                    }
                    named(ty, "Int", 0);
                }
            }
        })
        .unwrap()
        .join()
        .unwrap();
}

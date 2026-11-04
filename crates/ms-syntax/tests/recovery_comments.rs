use ms_syntax::{DeclKind, Names};
use std::sync::Arc;

#[test]
fn block_comment_contents_do_not_become_recovered_declarations() {
    let file = Arc::from("comments.ms");
    let comment = "/*\nfn ghost() Int: 99\nimport Missing from \"./missing.ms\"\n*/\n";
    for prefix in ["", "fn head() Int: 1\n", "fn broken(\n", "@\n"] {
        let suffix = if prefix == "fn broken(\n" {
            ""
        } else {
            "fn broken(\n"
        };
        for ending in ["\n", "\r\n"] {
            let source =
                format!("{prefix}{comment}fn real() Int: 2\n{suffix}").replace('\n', ending);
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            let names: Vec<_> = module
                .decls
                .iter()
                .map(|decl| {
                    let DeclKind::Fn(function) = &decl.kind else {
                        panic!("{decl:?}")
                    };
                    Names::global().str(function.name)
                })
                .collect();
            assert_eq!(
                names,
                if prefix.starts_with("fn head") {
                    vec!["head", "real"]
                } else {
                    vec!["real"]
                },
                "{diagnostics:?}"
            );
            assert!(module.imports.is_empty(), "comment produced an import");
            assert_eq!(
                diagnostics.len(),
                if prefix == "@\n" { 2 } else { 1 },
                "{diagnostics:?}"
            );
            let real = module.decls.last().unwrap();
            assert_eq!(real.pos.offset as usize, source.find("fn real").unwrap());
            assert_eq!(module.source.as_ref(), source);
        }
    }
}

#[test]
fn recovered_multiline_text_keeps_comment_markers_as_text() {
    let file = Arc::from("comments.ms");
    for raw in ["", "r"] {
        for ending in ["\n", "\r\n"] {
            let source = format!("let TEXT = {raw}\"\"\"\n/*\nfn ghost() Int: 99\n*/\n\"\"\"\nfn real() Int: 2\nfn broken(\n")
                .replace('\n', ending);
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.decls.len(), 2, "{diagnostics:?}");
            assert!(matches!(module.decls[0].kind, DeclKind::Const(_)));
            assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
            assert_eq!(
                module.decls[1].pos.offset as usize,
                source.find("fn real").unwrap()
            );
        }
    }
}

#[test]
fn unterminated_block_comment_does_not_expose_its_contents() {
    let file = Arc::from("comments.ms");
    for ending in ["\n", "\r\n"] {
        let source = "fn head() Int: 1\n/*\nfn ghost() Int: 99\n".replace('\n', ending);
        let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
        assert_eq!(module.decls.len(), 1, "{diagnostics:?}");
        assert_eq!(module.decls[0].pos.offset, 0);
        assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
        assert!(
            diagnostics[0]
                .message
                .starts_with("unterminated block comment")
        );
        assert_eq!(
            diagnostics[0].pos.offset as usize,
            source.find("/*").unwrap()
        );
    }
}

#[test]
fn malformed_block_comments_keep_their_diagnostic_during_recovery() {
    let file = Arc::from("comments.ms");
    for (comment, message) in [
        ("/* outer\n/* inner */\n", "block comments do not nest"),
        (
            "/*\n\u{202e} fn ghost() Int: 99\n*/\n",
            "bidirectional text controls",
        ),
        ("/*\nfn ghost() Int: 99\r\n*/\n", ""),
    ] {
        for ending in ["\n", "\r\n"] {
            let comment = comment.replace("\r\n", "\n").replace('\n', ending);
            let source = comment + "fn real() Int: 2\n";
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.decls.len(), 1, "{diagnostics:?}");
            assert_eq!(
                module.decls[0].pos.offset as usize,
                source.find("fn real").unwrap()
            );
            if message.is_empty() {
                assert!(diagnostics.is_empty(), "{diagnostics:?}");
            } else {
                assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
                assert!(
                    diagnostics[0].message.starts_with(message),
                    "{diagnostics:?}"
                );
            }
        }
    }
}

#[test]
fn malformed_multiline_text_does_not_hide_following_declarations() {
    let file = Arc::from("comments.ms");
    for raw in ["", "r"] {
        for content in ["\\q", "\u{202e}", "\0"] {
            if raw == "r" && content == "\\q" {
                continue;
            }
            for ending in ["\n", "\r\n"] {
                let source = format!("let BAD = {raw}\"\"\"\n{content}\nfn ghost() Int: 99\n\"\"\"\nfn real() Int: 2\nfn broken(\n")
                    .replace('\n', ending);
                let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
                assert_eq!(module.decls.len(), 1, "{diagnostics:?}");
                assert_eq!(
                    module.decls.last().unwrap().pos.offset as usize,
                    source.find("fn real").unwrap()
                );
                assert_eq!(diagnostics.len(), 2, "{diagnostics:?}");
                assert_eq!(diagnostics[0].pos.line, 2);
                assert!(
                    diagnostics
                        .last()
                        .unwrap()
                        .message
                        .starts_with("unterminated delimiter")
                );
            }
        }
    }
}

#[test]
fn invalid_text_headers_do_not_consume_a_later_valid_literal() {
    let file = Arc::from("comments.ms");
    for ending in ["\n", "\r\n"] {
        let source = "let BAD = \"\"\"wrong\nfn real() Int: 2\nlet GOOD = \"\"\"\nhello\n\"\"\"\nfn tail() Int: 3\nfn broken(\n".replace('\n', ending);
        let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
        assert_eq!(module.decls.len(), 3, "{diagnostics:?}");
        assert!(matches!(module.decls[1].kind, DeclKind::Const(_)));
        assert_eq!(
            module.decls[0].pos.offset as usize,
            source.find("fn real").unwrap()
        );
        assert_eq!(
            module.decls[2].pos.offset as usize,
            source.find("fn tail").unwrap()
        );
        assert_eq!(diagnostics.len(), 2, "{diagnostics:?}");
    }
}

#[test]
fn invalid_text_headers_do_not_consume_a_later_function_literal() {
    let file = Arc::from("comments.ms");
    for ending in ["\n", "\r\n"] {
        let source = "let BAD = \"\"\"wrong\nfn real() String:\n    return (\n        \"\"\"\n        hello\n        \"\"\"\n    )\nfn tail() Int: 3\nfn broken(\n".replace('\n', ending);
        let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
        assert_eq!(module.decls.len(), 2, "{diagnostics:?}");
        assert_eq!(
            module.decls[0].pos.offset as usize,
            source.find("fn real").unwrap()
        );
        assert_eq!(
            module.decls[1].pos.offset as usize,
            source.find("fn tail").unwrap()
        );
        assert_eq!(diagnostics.len(), 2, "{diagnostics:?}");
    }
}

#[test]
fn malformed_multiline_openers_preserve_later_declarations() {
    let file = Arc::from("comments.ms");
    for raw in ["", "r"] {
        for middle in ["", "fn ghost() Int: 99\n\"\"\"\n"] {
            for ending in ["\n", "\r\n"] {
                let source =
                    format!("let BAD = {raw}\"\"\"wrong\n{middle}fn real() Int: 2\nfn broken(\n")
                        .replace('\n', ending);
                let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
                assert_eq!(
                    module.decls.len(),
                    if middle.is_empty() { 1 } else { 2 },
                    "{diagnostics:?}"
                );
                assert_eq!(
                    module.decls.last().unwrap().pos.offset as usize,
                    source.find("fn real").unwrap()
                );
                assert_eq!(
                    diagnostics.len(),
                    if middle.is_empty() { 2 } else { 3 },
                    "{diagnostics:?}"
                );
                assert!(
                    diagnostics[0]
                        .message
                        .starts_with("multi-line text must start")
                );
                assert!(
                    diagnostics
                        .last()
                        .unwrap()
                        .message
                        .starts_with("unterminated delimiter")
                );
            }
        }
    }
}

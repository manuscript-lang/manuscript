use std::sync::Arc;
#[test]
fn unfinished_functions_do_not_swallow_constants_or_externs() {
    let file = Arc::from("recover.ms");
    for declaration in [
        "let VALUE = 3\n",
        "let(\n    VALUE = 3\n)\n",
        "extern fn native(value: Int) Int\n",
        "extern type Handle\n",
    ] {
        for ending in ["\n", "\r\n"] {
            let declaration = declaration.replace('\n', ending);
            let original = ms_syntax::parser::parse(&file, &declaration).unwrap();
            let prefix = "fn broken(\n".replace('\n', ending);
            let source =
                prefix.clone() + &declaration + &"fn tail() Int: return 7\n".replace('\n', ending);
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.decls.len(), 2, "{declaration:?}: {diagnostics:?}");
            assert_eq!(
                module.decls[0].pos.offset as usize,
                prefix.len() + original.decls[0].pos.offset as usize
            );
            assert_eq!(module.decls[0].pos.line, 1 + original.decls[0].pos.line);
            assert_eq!(diagnostics.len(), 1);
            assert!(diagnostics[0].message.starts_with("unterminated delimiter"));
        }
    }
}

#[test]
fn multiline_parameters_remain_continuations() {
    let file = Arc::from("recover.ms");
    for name in ["as", "from"] {
        let function = format!("fn valid(\n{name} : Int,\n) Int: return {name}\n");
        ms_syntax::parser::parse(&file, &function).unwrap();
        for source in [function.clone(), function.replace('\n', "\r\n")] {
            let damaged = source.clone() + "fn broken(\n";
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &damaged);
            assert_eq!(module.decls.len(), 1);
            assert_eq!(module.decls[0].pos.offset, 0);
            assert_eq!(diagnostics.len(), 1);
            assert_eq!(module.source.as_ref(), damaged);
        }
    }
}

#[test]
fn long_unfinished_lists_preserve_following_declarations() {
    let file = Arc::from("recover.ms");
    for ending in ["\n", "\r\n"] {
        for entry in ["1,\n", "(1),\n", "\"x ] #\",\n"] {
            let prefix = ("let data = [\n".to_string() + &entry.repeat(128)).replace('\n', ending);
            let tail = "fn sentinel() Int: return 7\n".replace('\n', ending);
            let source = prefix.clone() + &tail;
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.decls.len(), 1, "{entry:?}: {diagnostics:?}");
            assert_eq!(module.decls[0].pos.offset as usize, prefix.len());
            assert_eq!(module.decls[0].pos.line, 130);
            assert_eq!(diagnostics.len(), 1);
            assert!(diagnostics[0].message.starts_with("unterminated delimiter"));
            assert_eq!(diagnostics[0].pos.offset as usize, prefix.len());
            assert_eq!(module.source.as_ref(), source);
        }
    }
}

#[test]
fn unfinished_headers_preserve_contextual_and_adjacent_declarations() {
    let file = Arc::from("recover.ms");
    for declaration in [
        "opaque type Token:\n    value: Int\n",
        "bench \"increment\": consume(1)\n",
        "bench\"increment\": consume(1)\n",
        "test\"example\": consume(1)\n",
        "import(Item) from \"items.ms\"\n",
    ] {
        for ending in ["\n", "\r\n"] {
            let declaration = declaration.replace('\n', ending);
            let original = ms_syntax::parser::parse(&file, &declaration).unwrap();
            let prefix = "fn broken(\n".replace('\n', ending);
            let source =
                prefix.clone() + &declaration + &"fn tail() Int: 7\n".replace('\n', ending);
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(
                module.decls.len(),
                original.decls.len() + 1,
                "{declaration:?}: {diagnostics:?}"
            );
            assert_eq!(
                module.imports.len(),
                original.imports.len(),
                "{declaration:?}: {diagnostics:?}"
            );
            let recovered_pos = module
                .imports
                .first()
                .map(|i| i.pos)
                .unwrap_or(module.decls[0].pos);
            assert_eq!(recovered_pos.offset as usize, prefix.len());
            assert_eq!(recovered_pos.line, 2);
            assert_eq!(diagnostics.len(), 1, "{declaration:?}: {diagnostics:?}");
            assert!(diagnostics[0].message.starts_with("unterminated delimiter"));
            assert_eq!(module.source.as_ref(), source);
        }
    }
}

#[test]
fn contextual_names_in_multiline_parameters_are_not_declarations() {
    let file = Arc::from("recover.ms");
    for name in [
        "bench",
        "opaque",
        "benchmark",
        "opaque_type",
        "imported",
        "letter",
    ] {
        for ending in ["\n", "\r\n"] {
            let function =
                format!("fn valid(\n{name}: Int,\n) Int: {name}\n").replace('\n', ending);
            ms_syntax::parser::parse(&file, &function).unwrap();
            let source = function + "fn broken(\n";
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.decls.len(), 1, "{name}: {diagnostics:?}");
            assert_eq!(diagnostics.len(), 1);
            assert_eq!(module.source.as_ref(), source);
        }
    }
}

#[test]
fn anonymous_functions_at_column_zero_remain_continuations() {
    let file = Arc::from("recover.ms");
    for callback in ["fn(value: Int) Int: value", "fn (value: Int) Int: value"] {
        for ending in ["\n", "\r\n"] {
            let valid = format!("let callbacks = [\n{callback},\n]\n").replace('\n', ending);
            ms_syntax::parser::parse(&file, &valid).unwrap();
            let source = valid + "fn broken(\n";
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(module.decls.len(), 1, "{callback}: {diagnostics:?}");
            assert_eq!(diagnostics.len(), 1, "{callback}: {diagnostics:?}");
            assert_eq!(module.source.as_ref(), source);
        }
    }
}

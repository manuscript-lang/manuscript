use std::sync::Arc;
#[test]
fn unfinished_functions_do_not_swallow_constants_or_externs() {
    let file = Arc::from("recover.ms");
    for declaration in [
        "let VALUE = 3\n",
        "let(\n    VALUE = 3\n)\n",
        "extern def native(value: Int) -> Int\n",
        "extern type Handle\n",
    ] {
        for ending in ["\n", "\r\n"] {
            let declaration = declaration.replace('\n', ending);
            let original = ms_syntax::parser::parse(&file, &declaration).unwrap();
            let prefix = "def broken(\n".replace('\n', ending);
            let source = prefix.clone()
                + &declaration
                + &"def tail() -> Int: return 7\n".replace('\n', ending);
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
    let function = "def valid(\nas : Int,\n) -> Int: return as\n";
    ms_syntax::parser::parse(&file, function).unwrap();
    for source in [function.to_string(), function.replace('\n', "\r\n")] {
        let damaged = source.clone() + "def broken(\n";
        let (module, diagnostics) = ms_syntax::parse_partial(&file, &damaged);
        assert_eq!(module.decls.len(), 1);
        assert_eq!(module.decls[0].pos.offset, 0);
        assert_eq!(diagnostics.len(), 1);
        assert_eq!(module.source.as_ref(), damaged);
    }
}

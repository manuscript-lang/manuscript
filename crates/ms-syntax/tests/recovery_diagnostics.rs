use std::sync::Arc;

#[test]
fn recovered_diagnostics_use_original_lines_in_messages_and_edits() {
    let file = Arc::from("diagnostics.ms");
    for fixture in [
        include_str!("recovery_diagnostics/header.src"),
        include_str!("recovery_diagnostics/nested_header.src"),
        include_str!("recovery_diagnostics/mismatch.src"),
        include_str!("recovery_diagnostics/probed_mismatch.src"),
        include_str!("recovery_diagnostics/unterminated.src"),
    ] {
        for ending in ["\n", "\r\n"] {
            let source = fixture.replace('\n', ending);
            let expected = ms_syntax::parser::parse(&file, &source).unwrap_err();
            let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
            assert_eq!(diagnostics, vec![*expected], "{source:?}");
            if let Some(fix) = &diagnostics[0].fix {
                let mut repaired = source.clone();
                repaired.replace_range(
                    fix.pos.offset as usize..fix.end.offset as usize,
                    &fix.replacement,
                );
                ms_syntax::parser::parse(&file, &repaired).unwrap();
            }
            assert_eq!(module.source.as_ref(), source);
            assert_eq!(module.decls[0].pos.offset, 0);
            if let Some(tail) = source.find("fn tail") {
                assert_eq!(module.decls.last().unwrap().pos.offset as usize, tail);
            }
        }
    }
}

#[test]
fn statement_retries_keep_original_diagnostic_lines() {
    let file = Arc::from("diagnostics.ms");
    for ending in ["\n", "\r\n"] {
        let source = include_str!("recovery_diagnostics/retry.src").replace('\n', ending);
        let first = ms_syntax::parser::parse(&file, &source).unwrap_err();
        let clean = source.replace('@', " ");
        let second = ms_syntax::parser::parse(&file, &clean).unwrap_err();
        let (module, diagnostics) = ms_syntax::parse_partial(&file, &source);
        assert_eq!(diagnostics, vec![*first, *second]);
        assert_eq!(module.decls.len(), 3);
        assert_eq!(module.source.as_ref(), source);
        assert_eq!(
            module.decls.last().unwrap().pos.offset as usize,
            source.find("fn tail").unwrap()
        );
    }
}

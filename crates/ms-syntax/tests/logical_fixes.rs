use std::sync::Arc;

#[test]
fn logical_operator_fixes_preserve_operand_boundaries() {
    let file = Arc::from("logical.ms");
    let templates = [
        include_str!("logical_fixes/direct.src"),
        include_str!("logical_fixes/interpolation.src"),
    ];
    for (operator, keyword) in [("&&", "and"), ("||", "or")] {
        for (input, expected) in [
            ("leftOPright", "left WORD right"),
            ("leftOP right", "left WORD right"),
            ("left OPright", "left WORD right"),
            ("left OP right", "left WORD right"),
            ("trueOPfalse", "true WORD false"),
            ("_leftOP_right", "_left WORD _right"),
            ("1OP2", "1 WORD 2"),
            ("(left)OP(right)", "(left)WORD(right)"),
            ("leftOP(right)", "left WORD(right)"),
            ("(left)OPright", "(left)WORD right"),
            ("left  OP  right", "left  WORD  right"),
        ] {
            for template in templates {
                let source = template.replace("EXPRESSION", &input.replace("OP", operator));
                let expected = template.replace("EXPRESSION", &expected.replace("WORD", keyword));
                for (source, expected) in [
                    (source.clone(), expected.clone()),
                    (source.replace('\n', "\r\n"), expected.replace('\n', "\r\n")),
                ] {
                    let error = ms_syntax::parser::parse(&file, &source).unwrap_err();
                    assert!(
                        error
                            .message
                            .starts_with(&format!("'{operator}' is not an operator;"))
                    );
                    let fix = error.fix.unwrap();
                    let mut repaired = source.clone();
                    repaired.replace_range(
                        fix.pos.offset as usize..fix.end.offset as usize,
                        &fix.replacement,
                    );
                    assert_eq!(repaired, expected, "{source}");
                    let module = ms_syntax::parser::parse(&file, &repaired).unwrap();
                    let tree = ms_syntax::dump::dump_module(ms_syntax::Names::global(), &module);
                    assert!(tree.contains(&format!("binary \"{keyword}\"")), "{tree}");
                    let formatted = ms_syntax::format(&file, &repaired).unwrap();
                    assert_eq!(ms_syntax::format(&file, &formatted).unwrap(), formatted);
                    let (partial, errors) = ms_syntax::parse_partial(&file, &source);
                    assert_eq!(errors.len(), 1);
                    assert_eq!(errors[0].fix.as_ref(), Some(&fix));
                    assert_eq!(partial.source.as_ref(), source);
                }
            }
        }
    }
}

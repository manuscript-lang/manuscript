use ms_syntax::DeclKind;
use ms_tooling::guide::{render::default_text, source::Source};
use std::sync::Arc;

#[test]
fn defaults_late_in_a_module_keep_their_original_expression_boundaries() {
    let fixture = include_str!("guide_testdata/moddoc/defaults.ms");
    let (_, function) = fixture.split_once("export fn defaults").unwrap();
    let mut text = fixture.to_string();
    for i in 0..256 {
        text.push_str(&format!("\nexport fn defaults_{i}{function}"));
    }
    for text in [text.clone(), text.replace('\n', "\r\n")] {
        let file = Arc::from("defaults.ms");
        let module = ms_syntax::parser::parse(&file, &text).unwrap();
        let source = Source::new(text.into());
        let tokens = source.tokens().unwrap();
        assert!(tokens.windows(2).all(|pair| pair[0].1 <= pair[1].1));
        let syms = ms_syntax::Names::global();
        let mut checked = 0;
        for declaration in &module.decls {
            let DeclKind::Fn(function) = &declaration.kind else {
                continue;
            };
            if function.params.len() != 4 {
                continue;
            }
            let defaults: Vec<_> = function
                .params
                .iter()
                .map(|parameter| default_text(syms, parameter, Some(&source)))
                .collect();
            assert_eq!(defaults[0], "-3");
            assert_eq!(defaults[1], "helper(left: first, right: 2)");
            assert_eq!(defaults[2], "\"literal, )\"");
            assert_eq!(
                defaults[3].replace("\r\n", "\n"),
                "(\n        fn(value: Int) Int:\n            return value + 1\n    )"
            );
            checked += 1;
        }
        assert_eq!(checked, 257);
    }
}

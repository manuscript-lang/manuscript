use ms_syntax::{DeclKind, TypeKind, TypeRef};
use ms_tooling::guide::{page, render::type_text, search};
use std::sync::Arc;

fn assert_same_type(expected: &TypeRef, actual: &TypeRef) {
    match (&expected.kind, &actual.kind) {
        (TypeKind::Named { name: a, args: aa }, TypeKind::Named { name: b, args: ba }) => {
            assert_eq!(a, b);
            assert_eq!(aa.len(), ba.len());
            for (a, b) in aa.iter().zip(ba) {
                assert_same_type(a, b);
            }
        }
        (
            TypeKind::Fn {
                params: a,
                result: ar,
            },
            TypeKind::Fn {
                params: b,
                result: br,
            },
        ) => {
            assert_eq!(a.len(), b.len());
            for (a, b) in a.iter().zip(b) {
                assert_same_type(a.ty.as_ref().unwrap(), b.ty.as_ref().unwrap());
            }
            assert_same_type(ar, br);
        }
        _ => panic!("rendering changed the type: {expected:?} -> {actual:?}"),
    }
}

fn parse_type(text: &str) -> TypeRef {
    let file: Arc<str> = Arc::from("roundtrip.ms");
    let source = include_str!("guide_testdata/type-display/roundtrip.ms").replace("Printed", text);
    let parsed = ms_syntax::parser::parse(&file, &source).unwrap();
    let DeclKind::Fn(function) = &parsed.decls[0].kind else {
        panic!("expected a function")
    };
    function.params[0].ty.clone().unwrap()
}

#[test]
fn source_type_compositions_preserve_the_parsed_structure() {
    for seed in [
        "Int",
        "Int?",
        "Int??",
        "List[Int?]",
        "fn(Int) String?",
        "(fn(Int) String)?",
        "Result[Int?, Error]",
    ] {
        for text in [
            format!("({seed})?"),
            format!("List[{seed}]"),
            format!("fn({seed}) Int?"),
            format!("Result[{seed}, Error]"),
            format!("Map[String, {seed}]"),
        ] {
            let original = parse_type(&text);
            let rendered = type_text(&original);
            assert_same_type(&original, &parse_type(&rendered));
        }
    }
}

#[test]
fn source_optional_types_render_as_parseable_suffixes() {
    let file: Arc<str> = Arc::from("types.ms");
    let module =
        ms_syntax::parser::parse(&file, include_str!("guide_testdata/type-display/types.ms"))
            .unwrap();
    let DeclKind::Fn(function) = &module.decls[0].kind else {
        panic!("expected a function")
    };
    let expected = [
        "Int?",
        "List[Int??]",
        "(fn(Int?) String)?",
        "fn(Int) String?",
        "Result[Int, Error]?",
        "Result[Int?, Error]",
    ];
    assert_eq!(function.params.len(), expected.len());
    for (parameter, expected) in function.params.iter().zip(expected) {
        let original = parameter.ty.as_ref().unwrap();
        let text = type_text(original);
        assert_eq!(text, expected, "{}", parameter.name);
        let source =
            include_str!("guide_testdata/type-display/roundtrip.ms").replace("Printed", &text);
        let reparsed = ms_syntax::parser::parse(&file, &source).unwrap();
        let DeclKind::Fn(roundtrip) = &reparsed.decls[0].kind else {
            panic!("expected a function")
        };
        assert_same_type(original, roundtrip.params[0].ty.as_ref().unwrap());
    }
}

#[test]
fn standard_source_signatures_do_not_teach_rejected_optional_syntax() {
    let text = page("fs.read_file").unwrap();
    assert!(text.contains("max_bytes: Int?"), "{text}");
    let matches = search("fs.read_file", 10);
    let read_file = matches
        .iter()
        .find(|m| m.module == "@std/os/fs.ms" && m.name == "read_file")
        .unwrap();
    assert!(
        read_file.signature.contains("max_bytes: Int?"),
        "{}",
        read_file.signature
    );
    assert!(
        !read_file.signature.contains("Optional["),
        "{}",
        read_file.signature
    );
}

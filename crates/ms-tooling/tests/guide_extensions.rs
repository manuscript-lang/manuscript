//! Receiver implementations stay discoverable when their element types have bounds.

use ms_tooling::guide::docgen::{render_module, to_json};
use ms_tooling::guide::{ApiDeclaration, module_documentation, page, search, standard_library};

fn list() -> &'static ApiDeclaration {
    standard_library()
        .iter()
        .find(|module| module.path == "prelude")
        .unwrap()
        .declarations
        .iter()
        .find(|declaration| declaration.name == "List")
        .unwrap()
}

#[test]
fn bounded_source_methods_reach_list_pages_search_and_downloads() {
    for name in [
        "contains", "distinct", "to_set", "min", "max", "min_by", "max_by",
    ] {
        let members: Vec<_> = list()
            .members
            .iter()
            .filter(|member| member.name.split('[').next() == Some(name))
            .collect();
        assert_eq!(members.len(), 1, "List.{name}: {members:?}");
        assert!(
            !members[0].doc.is_empty(),
            "List.{name} lost its source comment"
        );
        let output = page(&format!("prelude.List.{name}")).unwrap();
        assert!(output.contains(&members[0].signature), "{output}");
        assert!(
            search(&format!("List.{name}"), 10)
                .iter()
                .any(|found| found.module == "prelude"
                    && found.name.starts_with(&format!("List.{name}"))),
            "List.{name} is absent from search"
        );
    }
    let module = standard_library()
        .iter()
        .find(|module| module.path == "prelude")
        .unwrap();
    assert!(render_module(module).contains("fn min() T?"));
    assert!(to_json(std::slice::from_ref(module)).contains("fn min() T?"));
    let minimum = page("prelude.List.min").unwrap();
    assert!(
        minimum.contains("# Receiver: List[T]; T: Comparable & Clonable"),
        "{minimum}"
    );
    let keyed = page("prelude.List.min_by").unwrap();
    assert!(
        keyed.contains("fn min_by[K: Comparable](key: fn(T) K) T?"),
        "{keyed}"
    );
}

#[test]
fn sorted_search_exposes_its_actual_result_and_comparable_bound_once() {
    let members: Vec<_> = list()
        .members
        .iter()
        .filter(|member| member.name == "binary_search")
        .collect();
    assert_eq!(members.len(), 1, "{members:?}");
    assert_eq!(
        members[0].signature,
        "# Receiver: List[T]; T: Comparable\nfn binary_search(value: T) SearchResult:"
    );
    let text = page("prelude.List.binary_search").unwrap();
    assert!(text.contains(&members[0].signature), "{text}");
    let matches = search("List.binary_search", 10);
    assert_eq!(
        matches
            .iter()
            .filter(|found| found.name == "List.binary_search")
            .count(),
        1,
        "{matches:?}"
    );
    assert!(
        page("collections.SearchResult")
            .unwrap()
            .contains("index: Int")
    );
}

#[test]
fn string_affix_cuts_expose_each_actual_receiver_signature_once() {
    let string = standard_library()
        .iter()
        .find(|module| module.path == "prelude")
        .unwrap()
        .declarations
        .iter()
        .find(|declaration| declaration.name == "String")
        .unwrap();
    for (name, signature) in [
        ("cut_prefix", "fn cut_prefix(prefix: String) String?:"),
        ("cut_suffix", "fn cut_suffix(suffix: String) String?:"),
    ] {
        let members: Vec<_> = string
            .members
            .iter()
            .filter(|member| member.name == name)
            .collect();
        assert_eq!(members.len(), 1, "String.{name}: {members:?}");
        assert_eq!(members[0].signature, signature);
        assert!(
            page(&format!("prelude.String.{name}"))
                .unwrap()
                .contains(signature)
        );
        assert_eq!(
            search(&format!("String.{name}"), 10)
                .iter()
                .filter(|found| found.name == format!("String.{name}"))
                .count(),
            1
        );
    }
    for removed in ["cut", "cut_last"] {
        assert!(string.members.iter().all(|member| member.name != removed));
    }
    assert!(page("string.StringCut").is_err());
}

#[test]
fn receiver_constraints_and_nominal_identity_survive_repeated_method_records() {
    let files = [
        ("box.ms", include_str!("guide_testdata/extensions/box.ms")),
        (
            "other.ms",
            include_str!("guide_testdata/extensions/other.ms"),
        ),
    ];
    let modules = files
        .iter()
        .map(|(file, text)| {
            let file: std::sync::Arc<str> = std::sync::Arc::from(*file);
            let parsed = ms_syntax::parser::parse(&file, text).unwrap();
            ms_check::load_module(&parsed)
        })
        .collect();
    let mut program = ms_check::check(
        modules,
        ms_check::ImportMap::default(),
        ms_check::CheckOptions::default(),
    );
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
    program.methods.extend(program.methods.clone());
    let documented = module_documentation(&program);
    let first = &documented
        .iter()
        .find(|module| module.path == "box.ms")
        .unwrap()
        .declarations[0];
    assert_eq!(first.name, "Box");
    let names: Vec<_> = first
        .members
        .iter()
        .filter(|member| member.kind == "operation")
        .map(|member| member.name.as_str())
        .collect();
    assert_eq!(names, ["accepts", "number", "precedes"]);
    let signatures: Vec<_> = first
        .members
        .iter()
        .map(|member| member.signature.as_str())
        .collect();
    assert!(
        signatures
            .iter()
            .any(|signature| signature.contains("fn accepts(flag: Bool = true) Bool")),
        "{signatures:?}"
    );
    assert!(
        signatures
            .iter()
            .any(|signature| signature.contains("# Receiver: Box[Int]\nfn number() Int")),
        "{signatures:?}"
    );
    assert!(
        signatures.iter().any(|signature| signature
            .contains("# Receiver: Box[T]; T: Comparable\nfn precedes(other: T) Bool")),
        "{signatures:?}"
    );
    let other = &documented
        .iter()
        .find(|module| module.path == "other.ms")
        .unwrap()
        .declarations[0];
    let other_names: Vec<_> = other
        .members
        .iter()
        .filter(|member| member.kind == "operation")
        .map(|member| member.name.as_str())
        .collect();
    assert_eq!(other_names, ["other"]);
}

#[test]
fn source_and_native_overloads_remain_distinct_without_repeated_implementations() {
    for name in ["sort", "sorted"] {
        let members: Vec<_> = list()
            .members
            .iter()
            .filter(|member| member.name == name)
            .collect();
        assert_eq!(members.len(), 2, "List.{name}: {members:?}");
        assert!(
            members
                .iter()
                .any(|member| member.signature.contains("compare:"))
        );
        assert!(
            members
                .iter()
                .any(|member| member.signature.contains(&format!("{name}()")))
        );
    }
    let sums: Vec<_> = list()
        .members
        .iter()
        .filter(|member| member.name == "sum")
        .collect();
    assert_eq!(sums.len(), 9, "specialized sum overloads: {sums:?}");
    let mut signatures = std::collections::BTreeSet::new();
    for member in &list().members {
        assert!(
            signatures.insert((&member.name, &member.signature, &member.contract)),
            "duplicate: {member:?}"
        );
    }
    assert_eq!(
        list()
            .members
            .iter()
            .filter(|member| member.name == "append")
            .count(),
        1
    );
}

//! Grouped imports: one statement imports from several modules.

use std::sync::Arc;

fn file() -> Arc<str> {
    Arc::from("grouped.ms")
}

fn imports(source: &str) -> Vec<(String, String)> {
    let module = ms_syntax::parser::parse(&file(), source).unwrap();
    module
        .imports
        .iter()
        .map(|i| {
            (
                ms_syntax::Names::global().str(i.name).to_string(),
                i.path.to_string(),
            )
        })
        .collect()
}

fn format(source: &str) -> String {
    ms_syntax::format(&file(), source).unwrap()
}

fn pair(name: &str, path: &str) -> (String, String) {
    (name.into(), path.into())
}

#[test]
fn group_expands_to_one_import_per_name() {
    let source = "import (\n\tA, B from \"./a.ms\",\n\tC from \"./c.ms\",\n)\n";
    assert_eq!(
        imports(source),
        [
            pair("A", "./a.ms"),
            pair("B", "./a.ms"),
            pair("C", "./c.ms")
        ]
    );
}

#[test]
fn group_allows_one_line_and_no_trailing_comma() {
    let source = "import (A from \"./a.ms\", B from \"./b.ms\")\n";
    assert_eq!(imports(source), [pair("A", "./a.ms"), pair("B", "./b.ms")]);
}

#[test]
fn older_forms_still_parse() {
    assert_eq!(imports("import A from \"./a.ms\"\n").len(), 1);
    assert_eq!(imports("import A, B from \"./a.ms\"\n").len(), 2);
    assert_eq!(
        imports("import (\n\tA,\n\tB,\n) from \"./a.ms\"\n").len(),
        2
    );
}

#[test]
fn malformed_groups_are_rejected() {
    for source in [
        "import ()\n",
        "import (A)\n",
        "import (A from \"./a.ms\" B from \"./b.ms\")\n",
        "import (A from \"./a.ms\",, B from \"./b.ms\")\n",
        "import (A as X from \"./a.ms\")\n",
        "import (A from \"./a.ms\"\n",
    ] {
        assert!(
            ms_syntax::parser::parse(&file(), source).is_err(),
            "{source}"
        );
    }
}

#[test]
fn format_groups_adjacent_imports() {
    let source = "import A from \"./a.ms\"\nimport B, C from \"./b.ms\"\nimport (\n\tD,\n\tE,\n) from \"./d.ms\"\n\nfn f() Int:\n\treturn 1\n";
    let expected = "import (\n\tA from \"./a.ms\",\n\tB, C from \"./b.ms\",\n\tD, E from \"./d.ms\",\n)\n\nfn f() Int:\n\treturn 1\n";
    let once = format(source);
    assert_eq!(once, expected);
    assert_eq!(format(&once), once);
}

#[test]
fn format_keeps_lone_import_and_commented_neighbors() {
    let lone = "import A from \"./a.ms\"\n\nfn f() Int:\n\treturn 1\n";
    assert_eq!(format(lone), lone);
    let commented =
        "import A from \"./a.ms\"  // keep\nimport B from \"./b.ms\"\n\nfn f() Int:\n\treturn 1\n";
    assert_eq!(format(commented), commented);
}

#[test]
fn format_wraps_a_wide_clause_one_name_per_line() {
    let names: Vec<String> = (0..12).map(|i| format!("long_imported_name_{i}")).collect();
    let source = format!(
        "import {} from \"./wide.ms\"\nimport Z from \"./z.ms\"\n",
        names.join(", ")
    );
    let once = format(&source);
    assert!(once.contains("\tlong_imported_name_0,\n"), "{once}");
    assert!(
        once.contains("\tlong_imported_name_11 from \"./wide.ms\",\n"),
        "{once}"
    );
    assert_eq!(format(&once), once);
    assert_eq!(imports(&once).len(), 13);
}

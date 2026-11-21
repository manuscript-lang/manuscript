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

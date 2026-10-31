//! Imports expose declarations exported by the named module, not its lexical scope.

use ms_check::types::n;
use ms_check::{CheckOptions, ImportMap, Program};
use ms_syntax::Phase;
use std::sync::Arc;

fn check(file: &str, source: &str) -> Program {
    let sources = [
        ("declared.ms", include_str!("module_exports/declared.ms")),
        ("bridge.ms", include_str!("module_exports/bridge.ms")),
        (file, source),
    ];
    let mut imports = ImportMap::default();
    let modules = sources
        .into_iter()
        .map(|(file, source)| {
            let file: Arc<str> = Arc::from(file);
            let parsed = ms_syntax::parser::parse(&file, source).expect("fixture parses");
            for import in &parsed.imports {
                let target = import
                    .path
                    .strip_prefix("./")
                    .expect("local fixture import");
                imports.insert(n(&file), import.id, n(target));
            }
            ms_check::load_module(&parsed)
        })
        .collect();
    ms_check::check(modules, imports, CheckOptions::default())
}

#[test]
fn imports_do_not_reexport_functions_constants_records_or_interfaces() {
    let program = check(
        "transitive.ms",
        include_str!("module_exports/transitive.ms"),
    );
    assert_eq!(program.diagnostics.len(), 4, "{:?}", program.diagnostics);
    for (diagnostic, name) in program
        .diagnostics
        .iter()
        .zip(["Item", "Sized", "answer", "LIMIT"])
    {
        assert_eq!(&*diagnostic.file, "transitive.ms");
        assert_eq!(diagnostic.pos.line, 1);
        assert_eq!(diagnostic.phase, Phase::Resolution);
        assert_eq!(
            diagnostic.message,
            format!(
                "module does not export {name}; ./bridge.ms exports: score; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from \"./bridge.ms\"'"
            )
        );
    }
}

#[test]
fn imports_do_not_export_ambient_primitive_or_prelude_names() {
    let program = check("ambient.ms", include_str!("module_exports/ambient.ms"));
    assert_eq!(program.diagnostics.len(), 3, "{:?}", program.diagnostics);
    for (diagnostic, name) in program.diagnostics.iter().zip(["Int", "List", "none"]) {
        assert_eq!(&*diagnostic.file, "ambient.ms");
        assert_eq!(diagnostic.phase, Phase::Resolution);
        assert!(
            diagnostic
                .message
                .starts_with(&format!("module does not export {name};")),
            "{diagnostic}"
        );
    }
}

#[test]
fn direct_imports_keep_exported_declarations_and_nominal_identity() {
    let program = check("direct.ms", include_str!("module_exports/direct.ms"));
    assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
}

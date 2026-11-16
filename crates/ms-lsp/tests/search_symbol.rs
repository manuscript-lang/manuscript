//! Symbol search keeps checked identities, imports and uses while filtering files.

use crate::support;

use ms_lsp::analysis::{Document, Documents};
use ms_lsp::query::search_symbols;
use ms_lsp::workspace::workspace_symbols;
use support::Workspace;

#[test]
fn fuzzy_search_keeps_private_function_uses_and_distinct_declarations() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("search-private");
    let root = ws.root.join("search");
    std::fs::create_dir_all(&root).unwrap();
    for file in ["a.ms", "b.ms"] {
        std::fs::write(
            root.join(file),
            "fn read_file() Int:\r\n    return 1\r\n\r\nfn main() Int:\r\n    reader := read_file\r\n    return reader()\r\n",
        )
        .unwrap();
    }
    std::fs::write(
        root.join("unrelated.ms"),
        "// read_file\nnote := \"read_file\"\nfn main() Int:\n    return 0\n",
    )
    .unwrap();
    for query in ["read file", "readFile", "raed_file", "rdf"] {
        let (found, total) = search_symbols(syms, root.to_str().unwrap(), query, 1).unwrap();
        assert_eq!(total, 2, "{query}");
        assert_eq!(found.len(), 1);
        let symbol = &found[0];
        assert_eq!(symbol.name, "read_file");
        assert!(symbol.definition.ends_with("a.ms:1:4"), "{symbol:?}");
        assert!(symbol.hover.contains("fn() Int"), "{symbol:?}");
        assert_eq!(symbol.references.len(), 2, "{symbol:?}");
        assert!(
            symbol.references.iter().any(|r| r.ends_with("a.ms:5:15")),
            "{symbol:?}"
        );
        assert!(
            symbol.references.iter().all(|r| !r.contains("b.ms")),
            "{symbol:?}"
        );
    }
}

#[test]
fn workspace_search_keeps_declarations_from_imported_subdirectories() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("search-imports");
    let root = ws.root.join("search");
    std::fs::create_dir_all(root.join("sub")).unwrap();
    let path = root.join("main.ms");
    let source = "import load from \"./sub/helper.ms\"\n\nfn main() Int:\n    return load()\n";
    std::fs::write(&path, source).unwrap();
    std::fs::write(
        root.join("sub/helper.ms"),
        "fn hidden_reader() Int:\n    return 1\n\nexport fn load() Int:\n    return hidden_reader()\n",
    )
    .unwrap();
    let d = Document::new(ms_lsp::uri::file_uri(path.to_str().unwrap()), source);
    let docs = Documents::from([(d.uri.clone(), d)]);
    // Without a manifest, open-document discovery scans only its directory.
    let found = workspace_symbols(
        syms,
        &ms_check::Session::new(),
        &docs,
        &[],
        "hidden_reader",
        None,
    )
    .unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!(
        found[0].get("name").and_then(|v| v.as_str()),
        Some("hidden_reader")
    );

    // A manifest extends cross-file references to callers in the parent dir.
    std::fs::write(
        root.join("ms.toml"),
        "[project]\nname = \"search\"\nsource = \".\"\nentry = \"main.ms\"\n",
    )
    .unwrap();
    let (found, total) = search_symbols(syms, root.to_str().unwrap(), "load", 5).unwrap();
    assert_eq!(total, 1);
    let symbol = &found[0];
    assert!(
        symbol.references.iter().any(|r| r.ends_with("main.ms:1:8")),
        "{symbol:?}"
    );
    assert!(
        symbol
            .references
            .iter()
            .any(|r| r.ends_with("main.ms:4:12")),
        "{symbol:?}"
    );
}

/// A workspace root with a `util` library member and an `app` member that imports it.
fn two_members(ws: &Workspace) {
    let write = |path: &str, text: &str| {
        let full = ws.root.join(path);
        std::fs::create_dir_all(full.parent().unwrap()).unwrap();
        std::fs::write(full, text).unwrap();
    };
    write(
        "team/ms.toml",
        "[workspace]\nmembers = [\"app\", \"libs/*\"]\n",
    );
    write(
        "team/app/ms.toml",
        "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n[dependencies]\n\"@util\" = { path = \"../libs/util\" }\n",
    );
    write(
        "team/app/src/main.ms",
        "import greet from \"@util/greet.ms\"\n\nfn main() Int:\n    print(greet(\"x\"))\n    return 0\n",
    );
    write(
        "team/libs/util/ms.toml",
        "[project]\nname = \"util\"\nsource = \"src\"\n",
    );
    write(
        "team/libs/util/src/greet.ms",
        "export fn greet(name: String) String:\n    return \"hi \" + name\n",
    );
}

#[test]
fn a_workspace_member_symbol_lists_uses_in_sibling_members() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("search-members");
    two_members(&ws);
    let util = ws.path("team/libs/util");
    let (found, _) = search_symbols(syms, &util, "greet", 5).unwrap();
    let symbol = found.iter().find(|s| s.name == "greet").expect("greet");
    assert!(
        symbol
            .references
            .iter()
            .any(|r| r.ends_with("main.ms:4:11")),
        "{symbol:?}"
    );
}

#[test]
fn renaming_a_member_function_edits_the_importing_member() {
    let syms = ms_syntax::Names::global();
    let ws = Workspace::new("rename-members");
    two_members(&ws);
    let source = ws.read("team/libs/util/src/greet.ms");
    let d = Document::new(ws.uri("team/libs/util/src/greet.ms"), source.clone());
    let docs = Documents::from([(d.uri.clone(), d.clone())]);
    let checked = ms_lsp::analysis::analyze(syms, &support::session(), &d, &docs);
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let at = ms_lsp::text::position(&source, source.find("greet").unwrap());
    let edit = ms_lsp::rename::rename(
        syms,
        &checked,
        checked.occurrence_index(syms),
        &d,
        at,
        "welcome",
        None,
        Some(&docs),
    )
    .expect("rename");
    let edits = edit.compact(ms_json::Escape::Plain);
    assert!(edits.contains("app/src/main.ms"), "{edits}");
    assert!(edits.contains("util/src/greet.ms"), "{edits}");
}

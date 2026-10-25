//! Symbol search keeps checked identities, imports and uses while filtering files.

mod support;

use ms_lsp::analysis::{Document, Documents};
use ms_lsp::query::search_symbols;
use ms_lsp::workspace::workspace_symbols;
use support::Workspace;

#[test]
fn fuzzy_search_keeps_private_function_uses_and_distinct_declarations() {
    let ws = Workspace::new("search-private");
    let root = ws.root.join("search");
    std::fs::create_dir_all(&root).unwrap();
    for file in ["a.ms", "b.ms"] {
        std::fs::write(
            root.join(file),
            "def read_file() -> Int:\r\n    return 1\r\n\r\ndef main() -> Int:\r\n    let reader = read_file\r\n    return reader()\r\n",
        )
        .unwrap();
    }
    std::fs::write(
        root.join("unrelated.ms"),
        "# read_file\nlet note = \"read_file\"\ndef main() -> Int:\n    return 0\n",
    )
    .unwrap();
    for query in ["read file", "readFile", "raed_file", "rdf"] {
        let (found, total) = search_symbols(root.to_str().unwrap(), query, 1).unwrap();
        assert_eq!(total, 2, "{query}");
        assert_eq!(found.len(), 1);
        let symbol = &found[0];
        assert_eq!(symbol.name, "read_file");
        assert!(symbol.definition.ends_with("a.ms:1:5"), "{symbol:?}");
        assert!(symbol.hover.contains("Callable[[], Int]"), "{symbol:?}");
        assert_eq!(symbol.references.len(), 2, "{symbol:?}");
        assert!(
            symbol.references.iter().any(|r| r.ends_with("a.ms:5:18")),
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
    let ws = Workspace::new("search-imports");
    let root = ws.root.join("search");
    std::fs::create_dir_all(root.join("sub")).unwrap();
    let path = root.join("main.ms");
    let source = "from \"./sub/helper.ms\" import load\n\ndef main() -> Int:\n    return load()\n";
    std::fs::write(&path, source).unwrap();
    std::fs::write(
        root.join("sub/helper.ms"),
        "def hidden_reader() -> Int:\n    return 1\n\nexport def load() -> Int:\n    return hidden_reader()\n",
    )
    .unwrap();
    let d = Document::new(ms_lsp::uri::file_uri(path.to_str().unwrap()), source);
    let docs = Documents::from([(d.uri.clone(), d)]);
    // Without a manifest, open-document discovery scans only its directory.
    let found = workspace_symbols(&docs, &[], "hidden_reader", None).unwrap();
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
    let (found, total) = search_symbols(root.to_str().unwrap(), "load", 5).unwrap();
    assert_eq!(total, 1);
    let symbol = &found[0];
    assert!(
        symbol
            .references
            .iter()
            .any(|r| r.ends_with("main.ms:1:31")),
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

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::completion::completion_at;
use ms_lsp::query::search_symbols;
use ms_lsp::symbols::document_symbols;
use ms_lsp::text::Position;
use ms_rt as _;

mod support;
use support::Workspace;

#[test]
fn enum_outline_and_workspace_search_keep_enum_identity() {
    let syms = ms_syntax::Names::global();
    let session = ms_check::Session::new();
    let ws = Workspace::new("enum-symbols");
    let source = include_str!("enum_declarations/source.ms");
    std::fs::write(ws.root.join("source.ms"), source).unwrap();
    let document = Document::new(ws.uri("source.ms"), source);
    let analysis = analyze(syms, &session, &document, &Documents::new());
    assert!(
        analysis.diagnostics.is_empty(),
        "{:?}",
        analysis.diagnostics
    );
    let symbols = document_symbols(syms, &analysis, &document);
    let symbols = symbols.as_array().unwrap();
    assert_eq!(symbols.len(), 2);
    for symbol in symbols {
        assert_eq!(symbol.get("kind").and_then(|v| v.as_i64()), Some(10));
    }
    let (found, total) = search_symbols(syms, ws.root.to_str().unwrap(), "Status", 5).unwrap();
    assert_eq!(total, 1);
    assert_eq!(found[0].kind, "enum");
}

#[test]
fn enum_keyword_snippet_inserts_a_checked_declaration() {
    let syms = ms_syntax::Names::global();
    let session = ms_check::Session::new();
    let ws = Workspace::new("enum-snippet");
    let mut document = Document::new(ws.uri("source.ms"), "enu");
    let item = completion_at(
        syms,
        &session,
        &document,
        &Documents::new(),
        Position {
            line: 0,
            character: 3,
        },
        true,
    )
    .unwrap()
    .into_iter()
    .map(|item| item.json())
    .find(|item| item.get("label").and_then(|v| v.as_str()) == Some("enum"))
    .unwrap();
    let source = item
        .get("textEdit")
        .unwrap()
        .get("newText")
        .unwrap()
        .as_str()
        .unwrap()
        .replace("${1:Name}", "Status")
        .replace("${0:Ready}", "Ready");
    assert_eq!(source, "enum Status:\n    case Ready");
    document.text = source;
    let checked = analyze(syms, &session, &document, &Documents::new());
    assert!(checked.diagnostics.is_empty(), "{:?}", checked.diagnostics);
}

#[test]
fn enum_semantic_tokens_preserve_strict_and_forgiving_headers() {
    let syms = ms_syntax::Names::global();
    let source = include_str!("enum_declarations/source.ms");
    for ending in ["\n", "\r\n"] {
        for suffix in ["", "\0"] {
            let source = source.replace('\n', ending) + suffix;
            let document = Document::new("file:///tmp/enums.ms", &source);
            let tokens = ms_lsp::semantic::semantic_tokens(syms, None, &[], &document);
            let data = tokens.get("data").unwrap().as_array().unwrap();
            let mut position = Position::default();
            let mut found = Vec::new();
            let (tokens, remainder) = data.as_chunks::<5>();
            assert!(remainder.is_empty());
            for token in tokens {
                let delta = token[0].as_i64().unwrap() as usize;
                position.line += delta;
                position.character = if delta == 0 { position.character } else { 0 }
                    + token[1].as_i64().unwrap() as usize;
                let start = ms_lsp::text::offset(&source, position).unwrap();
                let length = token[2].as_i64().unwrap() as usize;
                let kind = token[3].as_i64().unwrap();
                found.push((&source[start..start + length], kind));
            }
            for expected in [("opaque", 0), ("enum", 0), ("private", 6)] {
                assert!(found.contains(&expected), "{found:?}");
            }
        }
    }
}

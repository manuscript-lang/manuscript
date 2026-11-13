//! Explicit name handles remain authoritative while another session is current.

use ms_lsp::analysis::{Analysis, Document, Documents, analyze};
use ms_lsp::editor;
use ms_lsp::index;
use ms_lsp::nav;
use ms_lsp::semantic::semantic_tokens;
use ms_lsp::text;
use ms_rt as _;

fn with_retained_analysis(check: impl Fn(ms_syntax::Names, &Analysis, &Document)) {
    for newline in ["\n", "\r\n"] {
        let names = ms_syntax::Session::new();
        let entered = names.enter();
        let document = Document::new(
            "file:///retained-names-unsaved/source.ms",
            include_str!("retained_names/source.ms").replace('\n', newline),
        );
        let analysis = analyze(
            names.names(),
            &ms_check::Session::new(),
            &document,
            &Documents::new(),
        );
        assert!(analysis.success(), "{:?}", analysis.diagnostics);
        check(names.names(), &analysis, &document);
        drop(entered);
        let other = ms_syntax::Session::new();
        let _entered = other.enter();
        // Empty tables expose invalid IDs; populated ones expose silent wrong text.
        check(names.names(), &analysis, &document);
        for i in 0..30_000 {
            other.names().intern(&format!("foreign_{i}"));
        }
        check(names.names(), &analysis, &document);
    }
}

#[test]
fn semantic_tokens_keep_supplied_names() {
    with_retained_analysis(|names, analysis, document| {
        let tokens = semantic_tokens(names, Some(analysis), &[], document);
        let data = tokens.get("data").unwrap().as_array().unwrap();
        assert!(!data.is_empty());
        // A resolved function use is function-colored even without an occurrence index.
        let mut at = text::Position::default();
        let target = document.text.rfind("identity").unwrap();
        let mut found = false;
        let (items, remainder) = data.as_chunks::<5>();
        assert!(remainder.is_empty());
        for item in items {
            let lines = item[0].as_i64().unwrap() as usize;
            at.line += lines;
            at.character =
                if lines == 0 { at.character } else { 0 } + item[1].as_i64().unwrap() as usize;
            if text::offset(&document.text, at).unwrap() == target {
                assert_eq!(item[3].as_i64(), Some(5));
                found = true;
            }
        }
        assert!(found);
    });
}

#[test]
fn occurrence_index_keeps_supplied_names() {
    with_retained_analysis(|names, analysis, document| {
        let index = index::build_index(names, analysis, false);
        for name in ["identity", "value", "result", "caller"] {
            assert!(
                index
                    .iter()
                    .any(|entry| entry.name == name && entry.declaration)
            );
        }
        assert_eq!(
            index.iter().filter(|entry| entry.name == "floor").count(),
            2
        );
        let target = document.text.rfind("identity").unwrap();
        let use_site = index.iter().find(|entry| entry.offset == target).unwrap();
        assert_eq!(use_site.name, "identity");
        assert!(
            index
                .iter()
                .any(|entry| entry.declaration && entry.key == use_site.key)
        );
    });
}

#[test]
fn hover_fallback_keeps_supplied_names() {
    with_retained_analysis(|names, analysis, document| {
        let target = document.text.find("identity(1)").unwrap() + "identity(".len();
        let hit = nav::at(
            names,
            analysis,
            document,
            text::position(&document.text, target),
            &[],
        )
        .expect("literal fallback");
        assert_eq!(hit.text, "1");
        assert_eq!(hit.offset, target);
        assert_eq!(
            hit.info.ty.as_ref().unwrap().display(names).to_string(),
            "Int"
        );
    });
}

#[test]
fn retained_call_query_keeps_supplied_names() {
    check_retained_call(include_str!("retained_names/source.ms"));
}

fn check_retained_call(source: &str) {
    let names = ms_syntax::Session::new();
    let entered = names.enter();
    let document = Document::new("file:///retained-names-unsaved/source.ms", source);
    let target = document.text.find("(1)").unwrap() + 1;
    let context = editor::context_at(&document, text::position(&document.text, target)).unwrap();
    let query = editor::query_editor(
        names.names(),
        &ms_check::Session::new(),
        &document,
        &Documents::new(),
        &context,
    );
    let expected = editor::query_call(names.names(), &query).expect("checked call");
    let expected = expected.1.display(names.names()).to_string();
    drop(entered);
    let other = ms_syntax::Session::new();
    let _entered = other.enter();
    let actual = editor::query_call(names.names(), &query).expect("retained checked call");
    assert_eq!(actual.1.display(names.names()).to_string(), expected);
    for i in 0..30_000 {
        other.names().intern(&format!("foreign_{i}"));
    }
    let actual = editor::query_call(names.names(), &query).expect("retained checked call");
    assert_eq!(actual.1.display(names.names()).to_string(), expected);
}

#[test]
fn retained_type_scope_uses_existing_symbols() {
    let names = ms_syntax::Session::new();
    let entered = names.enter();
    let document = Document::new(
        "file:///retained-names-unsaved/constructor.ms",
        include_str!("retained_names/constructor.ms"),
    );
    let target = document.text.find("(1)").unwrap() + 1;
    let context = editor::context_at(&document, text::position(&document.text, target)).unwrap();
    let query = editor::query_editor(
        names.names(),
        &ms_check::Session::new(),
        &document,
        &Documents::new(),
        &context,
    );
    let (call, _) = editor::query_call(names.names(), &query).expect("constructor call");
    let ms_syntax::ast::ExprKind::Call { callee, .. } = &call.kind else {
        panic!("expected call");
    };
    let expected = editor::type_expression(names.names(), callee, &query.scope)
        .expect("applied type")
        .display(names.names())
        .to_string();
    assert_eq!(expected, "Item[Int]");
    drop(entered);
    let other = ms_syntax::Session::new();
    let _entered = other.enter();
    for i in 0..30_000 {
        other.names().intern(&format!("foreign_{i}"));
    }
    let actual = editor::type_expression(names.names(), callee, &query.scope)
        .expect("retained type")
        .display(names.names())
        .to_string();
    assert_eq!(actual, expected);
}

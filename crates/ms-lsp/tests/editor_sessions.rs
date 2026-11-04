//! Repaired editor snapshots share the caller's library without sharing analyses.

use ms_lsp::analysis::{Document, Documents};
use ms_lsp::editor::{context_at, query_editor};
use ms_lsp::text::Position;
use ms_rt as _;
use std::rc::Rc;

mod support;
use support::Workspace;

#[test]
fn repaired_queries_keep_the_supplied_library_and_fresh_document_analysis() {
    let syms = ms_syntax::Names::global();
    let session = ms_check::Session::new();
    let workspace = Workspace::new("editor-library-session");
    let mut previous = None;
    for source in [
        include_str!("completion/session.ms"),
        include_str!("completion/session-repair.ms"),
    ] {
        for newline in ["\n", "\r\n"] {
            for ty in ["Int", "String"] {
                let source = source.replace('\n', newline).replace("Int", ty);
                let d = Document::new(workspace.uri("query.ms"), source.clone());
                let docs = Documents::from([(d.uri.clone(), d.clone())]);
                let context = context_at(
                    &d,
                    Position {
                        line: 1,
                        character: 13,
                    },
                )
                .unwrap();
                let query = query_editor(syms, &session, &d, &docs, &context);
                assert!(query.expression.is_some(), "{newline:?} {ty}");
                assert!(query.result.program.is_some());
                assert!(Rc::ptr_eq(&query.result.session, &session));
                let binding = query.scope.bindings.get(&syms.intern("value")).unwrap();
                assert_eq!(binding.ty.display(syms).to_string(), ty);
                if let Some(previous) = previous {
                    assert!(!Rc::ptr_eq(&query.result, &previous));
                }
                assert_eq!(d.text, source);
                assert_eq!(docs[&d.uri].text, source);
                previous = Some(query.result);
            }
        }
    }
}

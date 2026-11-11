//! Recovered declarations retain the same editor name ranges as valid source.

use ms_lsp::analysis::{Document, Documents, analyze};
use ms_lsp::json::Json;
use ms_lsp::nav::{self, Navigate};
use ms_lsp::symbols::document_symbols;
use ms_lsp::text::{self, Range};
use ms_rt as _;

use crate::support;
use support::Workspace;

const SOURCE: &str = include_str!("recovery_navigation/declarations.ms");

#[test]
fn recovered_declaration_names_keep_hover_and_definition_ranges() {
    let syms = ms_syntax::Names::global();
    for broken in [
        "fn broken(\n\n",
        "broken := 😀\n\n",
        "fn broken():\n    text := \"\n\n",
    ] {
        for newline in ["\n", "\r\n"] {
            let ws = Workspace::new("recovered-navigation");
            let source = format!("{broken}{SOURCE}").replace('\n', newline);
            let document = Document::new(ws.uri("recovered.ms"), source.clone());
            let analysis = analyze(syms, &support::session(), &document, &Documents::new());
            assert!(
                !analysis.diagnostics.is_empty(),
                "malformed neighbor is retained"
            );
            for name in ["Point", "identity", "sample"] {
                let offset = source.find(name).unwrap();
                let at = text::position(&source, offset + name.len() - 1);
                let hover = nav::navigation(
                    syms,
                    &analysis,
                    &document,
                    at,
                    Navigate::Hover,
                    analysis.occurrence_index(syms),
                );
                let range = Range::from_json(
                    hover
                        .get("range")
                        .unwrap_or_else(|| panic!("{name}: {hover:?}")),
                )
                .unwrap();
                assert_eq!(text::offset(&source, range.start), Ok(offset));
                assert_eq!(text::offset(&source, range.end), Ok(offset + name.len()));
                let definition = nav::navigation(
                    syms,
                    &analysis,
                    &document,
                    at,
                    Navigate::Definition,
                    analysis.occurrence_index(syms),
                );
                let range =
                    Range::from_json(definition.as_array().unwrap()[0].get("range").unwrap())
                        .unwrap();
                assert_eq!(text::offset(&source, range.start), Ok(offset));
                assert_eq!(text::offset(&source, range.end), Ok(offset + name.len()));
            }
            let at = text::position(&source, source.rfind("point.x").unwrap());
            let definition = nav::type_definition(
                syms,
                &analysis,
                &document,
                at,
                analysis.occurrence_index(syms),
            );
            let range =
                Range::from_json(definition.as_array().unwrap()[0].get("range").unwrap()).unwrap();
            assert_eq!(
                text::offset(&source, range.start),
                Ok(source.find("Point").unwrap())
            );
        }
    }
}

#[test]
fn recovered_outline_selects_exact_declaration_names() {
    let syms = ms_syntax::Names::global();
    for newline in ["\n", "\r\n"] {
        let ws = Workspace::new("recovered-outline");
        let source = format!("fn broken(\n\n{SOURCE}").replace('\n', newline);
        let document = Document::new(ws.uri("recovered.ms"), source.clone());
        let analysis = analyze(syms, &support::session(), &document, &Documents::new());
        let outline = document_symbols(syms, &analysis, &document);
        for name in ["Point", "identity", "sample"] {
            let symbol = outline
                .as_array()
                .unwrap()
                .iter()
                .find(|item| item.get("name").and_then(Json::as_str) == Some(name))
                .expect("recovered symbol");
            let range = Range::from_json(symbol.get("selectionRange").unwrap()).unwrap();
            let start = text::offset(&source, range.start).unwrap();
            let end = text::offset(&source, range.end).unwrap();
            assert_eq!(&source[start..end], name);
        }
    }
}

#[test]
fn a_statement_cut_off_mid_expression_keeps_hover_and_definition() {
    let syms = ms_syntax::Names::global();
    for tail in ["g.", "g +", "g and"] {
        for newline in ["\n", "\r\n"] {
            let ws = Workspace::new("cut-off-statement");
            let source = format!(
                "fn f(s: String) String:\n    g := s\n    return {tail}\n\nfn other() Int: 1\n"
            )
            .replace('\n', newline);
            let document = Document::new(ws.uri("cut.ms"), source.clone());
            let analysis = analyze(syms, &support::session(), &document, &Documents::new());
            assert!(!analysis.diagnostics.is_empty());
            let at = text::position(&source, source.find(&format!("return {tail}")).unwrap() + 7);
            for method in [Navigate::Hover, Navigate::Definition] {
                let found = nav::navigation(
                    syms,
                    &analysis,
                    &document,
                    at,
                    method,
                    analysis.occurrence_index(syms),
                );
                assert!(!matches!(found, Json::Null), "{tail:?}");
            }
        }
    }
}

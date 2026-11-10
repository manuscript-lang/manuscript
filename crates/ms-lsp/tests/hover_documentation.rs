//! Hover documentation dispatch keeps method, receiver and plain-value behavior.

use ms_lsp::analysis::{Document, Options, compile_source};
use ms_lsp::json::Json;
use ms_lsp::{nav, text, uri};

#[test]
fn hover_documentation_keeps_values_symbols_and_method_fallbacks() {
    let syms = ms_syntax::Names::global();
    for newline in ["\n", "\r\n"] {
        let source = include_str!("hover_documentation/source.ms").replace('\n', newline);
        let d = Document::new(uri::file_uri("/hover-documentation.ms"), &source);
        let a = compile_source(syms, &d.path(), &source, &Options::default());
        assert!(a.success(), "{:?}", a.diagnostics);
        // A local fallback hover need not load unrelated deferred standard modules.
        // Its result stays identical once an occurrence index has loaded them.
        let position = text::position(&source, source.find("value +").unwrap());
        let fallback = nav::navigation(syms, &a, &d, position, nav::Navigate::Hover, &[]);
        assert_eq!(
            fallback,
            nav::navigation(
                syms,
                &a,
                &d,
                position,
                nav::Navigate::Hover,
                a.occurrence_index(syms),
            )
        );
        for (needle, shown, docs) in [
            ("value +", "value: Int", ""),
            ("value}", "value: Int", ""),
            ("123", "123: Int", ""),
            (
                "documented(meter",
                "documented: fn(Int) Int",
                "Function documentation.",
            ),
            ("read() +", "read: fn() Int", "Method documentation."),
            ("plain())", "plain: fn() Int", "Receiver documentation."),
        ] {
            let offset = source.rfind(needle).unwrap();
            let hover = nav::navigation(
                syms,
                &a,
                &d,
                text::position(&source, offset),
                nav::Navigate::Hover,
                a.occurrence_index(syms),
            );
            let value = hover
                .get("contents")
                .unwrap()
                .get("value")
                .and_then(Json::as_str)
                .unwrap();
            let expected = format!(
                "```manuscript\n{shown}\n```{}{}",
                if shown.contains("fn(") {
                    "\n\neffects: pure (ambient authority only)"
                } else {
                    ""
                },
                if docs.is_empty() {
                    String::new()
                } else {
                    format!("\n\n{docs}")
                }
            );
            assert_eq!(value, expected, "{needle}");
            let name = shown.split(':').next().unwrap();
            assert_eq!(
                hover.get("range").unwrap(),
                &text::Range {
                    start: text::position(&source, offset),
                    end: text::position(&source, offset + name.len()),
                }
                .json()
            );
        }
    }
}

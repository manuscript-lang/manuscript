use ms_tooling::guide::docgen::{render_module, to_json};
use ms_tooling::guide::{module_documentation, page, search, standard_library};
use std::sync::Arc;

#[test]
fn opaque_representation_is_hidden_but_public_operations_remain() {
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(|| {
            let names = ms_syntax::Names::global();
            let source = r#"
// Public secret.
export opaque type Secret[T]:
    hidden: T

// Read the value.
fn Secret[T].value(fallback: Int = 7) Int:
    return fallback

export interface Measured:
    fn size() Int

fn Secret[Int].size() Int:
    return 1

export opaque enum Choice[T]:
    Internal(payload: T)

export opaque type Bounded[T: Clonable]:
    hidden: T

export opaque enum Token:
    Internal

export opaque type Handle:
    hidden: Int

export type Visible:
    field: Int

export enum Open:
    Item(value: Int)
"#;
            let module = ms_syntax::parser::parse(&Arc::from("api.ms"), source).unwrap();
            let program = ms_check::check(
                names,
                vec![ms_check::load_module(names, &module)],
                ms_check::ImportMap::default(),
                ms_check::CheckOptions::default(),
            );
            assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
            let modules = module_documentation(names, &program);
            let module = modules.iter().find(|m| m.path == "api.ms").unwrap();
            for name in ["Secret", "Choice", "Bounded", "Token", "Handle"] {
                let d = module.declarations.iter().find(|d| d.name == name).unwrap();
                assert!(d.opaque);
                if name == "Bounded" {
                    assert_eq!(d.parameters, ["T: Clonable"]);
                } else if name == "Secret" || name == "Choice" {
                    assert_eq!(d.parameters, ["T"]);
                } else {
                    assert!(d.parameters.is_empty());
                }
                assert!(d.fields.is_empty());
                if name == "Secret" {
                    assert_eq!(d.implements, ["Measured"]);
                    assert_eq!(d.members.iter().filter(|m| m.name == "value").count(), 1);
                }
                assert!(d.cases.is_empty());
                assert!(d.members.iter().all(|m| m.kind == "operation"));
            }
            let markdown = render_module(module);
            let json = to_json(std::slice::from_ref(module));
            for output in [&markdown, &json] {
                for private in ["hidden", "Internal", "payload"] {
                    assert!(!output.contains(private), "{output}");
                }
                for public in [
                    "field: Int",
                    "Item(value: Int)",
                    "fallback: Int = 7",
                    "Read the value.",
                    "Public secret.",
                ] {
                    assert!(output.contains(public), "{output}");
                }
            }
            assert!(markdown.contains("opaque type Secret[T]:"));
            assert!(markdown.contains("opaque enum Choice[T]:"));
            assert!(json.contains("\"opaque\": true"));
            for name in ["Visible", "Open"] {
                let d = module.declarations.iter().find(|d| d.name == name).unwrap();
                assert!(!d.opaque);
                assert!(!d.members.is_empty());
            }
        })
        .unwrap()
        .join()
        .unwrap();
}

#[test]
fn promise_pages_search_and_downloads_hide_id_and_keep_methods() {
    let names = ms_syntax::Names::global();
    let module = standard_library(names)
        .iter()
        .find(|m| m.path == "@std/concurrency/promise.ms")
        .unwrap();
    let promise = module
        .declarations
        .iter()
        .find(|d| d.name == "Promise")
        .unwrap();
    assert!(promise.opaque);
    assert!(promise.fields.is_empty());
    assert!(!promise.members.iter().any(|m| m.name == "id"));
    for method in ["wait", "cancel", "done", "close", "with"] {
        assert!(promise.members.iter().any(|m| m.name == method));
        assert!(page(names, &format!("promise.Promise.{method}")).is_ok());
        assert!(
            search(names, &format!("Promise.{method}"), 10)
                .iter()
                .any(|m| m.name == format!("Promise.{method}"))
        );
    }
    let output = page(names, "promise.Promise").unwrap();
    assert!(output.starts_with("opaque type Promise"));
    assert!(!output.contains("id: Int"), "{output}");
    assert!(page(names, "promise.Promise.id").is_err());
    assert!(
        !search(names, "Promise.id", 100)
            .iter()
            .any(|m| m.name == "Promise.id")
    );
    assert!(render_module(module).contains("opaque type Promise[T]:"));
    assert!(to_json(std::slice::from_ref(module)).contains("\"opaque\": true"));
}

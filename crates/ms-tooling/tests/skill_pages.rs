//! The installed skill teaches executable, versioned Manuscript rather than placeholders.
use ms_check::{CheckOptions, ImportMap};
use ms_tooling::guide::skill::FILES;
use std::sync::Arc;

#[test]
fn skill_complete_examples_check() {
    let mut examples = 0;
    for (path, text) in FILES {
        assert!(
            !text.contains('\t'),
            "skill uses four-space indentation: {path}"
        );
        for after in text.split("<!-- complete").skip(1) {
            let (_, after_marker) = after.split_once(" -->\n").expect("complete marker");
            let source = after_marker
                .strip_prefix("```manuscript\n")
                .expect("marked Manuscript fence")
                .split_once("```")
                .expect("closed fence")
                .0
                .to_string();
            let path = path.to_string();
            std::thread::Builder::new()
                .stack_size(64 << 20)
                .spawn(move || {
                    let names = ms_syntax::Names::global();
                    let name: Arc<str> = Arc::from("skill_example.ms");
                    let module = ms_syntax::parser::parse(&name, &source)
                        .unwrap_or_else(|e| panic!("{path}: {}", e.message));
                    let program = ms_check::check(
                        names,
                        vec![ms_check::load_module(names, &module)],
                        ImportMap::default(),
                        CheckOptions::default(),
                    );
                    assert!(
                        program.diagnostics.is_empty(),
                        "{path}: {:?}",
                        program.diagnostics
                    );
                })
                .unwrap()
                .join()
                .unwrap();
            examples += 1;
        }
    }
    assert_eq!(examples, 8, "retain all complete skill examples");
}

#[test]
fn skill_root_is_short_and_references_are_substantive() {
    let root = FILES
        .iter()
        .find(|(path, _)| *path == "SKILL.md")
        .unwrap()
        .1;
    assert!(root.len() <= 2600, "entry skill should remain concise");
    assert!(root.starts_with("---\nname: manuscript\n"));
    assert!(root.contains("{{MS_VERSION}}"));
    for (path, text) in FILES
        .iter()
        .filter(|(path, _)| path.starts_with("references/"))
    {
        assert!(root.contains(path), "unreachable reference {path}");
        assert!(
            text.len() >= 600,
            "reference must teach its concept: {path}"
        );
        assert!(
            text.contains("```manuscript"),
            "reference needs a real example: {path}"
        );
    }
}

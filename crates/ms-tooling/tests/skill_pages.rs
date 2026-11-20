//! The installed skill teaches executable, versioned Manuscript rather than placeholders.
use ms_check::{CheckOptions, ImportMap};

/// The skill files as they sit in the repository, `SKILL.md` first, with `{{MS_VERSION}}` unfilled.
pub fn files() -> &'static [(&'static str, &'static str)] {
    static FILES: std::sync::OnceLock<Vec<(&'static str, &'static str)>> =
        std::sync::OnceLock::new();
    FILES.get_or_init(|| {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tools/ms/data/agent-skill");
        let mut names: Vec<String> = std::fs::read_dir(root.join("references"))
            .unwrap()
            .map(|entry| {
                format!(
                    "references/{}",
                    entry.unwrap().file_name().to_string_lossy()
                )
            })
            .collect();
        names.sort();
        names.insert(0, "SKILL.md".to_string());
        names
            .into_iter()
            .map(|name| {
                let text = std::fs::read_to_string(root.join(&name)).unwrap();
                let name: &'static str = Box::leak(name.into_boxed_str());
                (name, &*Box::leak(text.into_boxed_str()))
            })
            .collect()
    })
}

use std::sync::Arc;

#[test]
fn skill_complete_examples_check() {
    let mut examples = 0;
    for (path, text) in files() {
        for fence in text.split("```manuscript\n").skip(1) {
            let source = fence.split_once("```").expect("closed fence").0;
            assert!(
                source.lines().all(|line| !line.starts_with(' ')),
                "skill code indentation must use tabs: {path}"
            );
        }
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
    assert_eq!(examples, 25, "retain all complete skill examples");
}

#[test]
fn skill_root_is_short_and_references_are_substantive() {
    let root = files()
        .iter()
        .find(|(path, _)| *path == "SKILL.md")
        .unwrap()
        .1;
    assert!(root.len() <= 13000, "entry skill should remain concise");
    assert!(root.starts_with("---\nname: manuscript\n"));
    assert!(root.contains("{{MS_VERSION}}"));
    assert!(root.contains("Use tabs for indentation"));
    for (path, text) in files()
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

/// The server-state example is also a conformance fixture, which runs it.
#[test]
fn skill_server_state_example_is_the_tested_fixture() {
    let page = files()
        .iter()
        .find(|(path, _)| *path == "references/servers-and-state.md")
        .unwrap()
        .1;
    let shown = page
        .split_once("<!-- complete: server-state.ms -->\n```manuscript\n")
        .expect("example")
        .1
        .split_once("```")
        .unwrap()
        .0;
    let fixture =
        include_str!("../../../tests/conformance/fixtures/e2e/stdlib/serve-state-owner.ms");
    assert_eq!(
        shown,
        fixture
            .strip_prefix("// conform: tags=testing,tier-io\n// conform: phase=test\n")
            .expect("fixture header"),
        "keep the skill example equal to its fixture"
    );
}

/// The call table is rendered from the standard library's declarations, so a renamed or
/// removed call fails here instead of going stale.
#[test]
fn skill_call_tables_match_the_declarations() {
    use ms_tooling::guide::skill_calls::{block_of, render};
    let page = files()
        .iter()
        .find(|(path, _)| *path == "references/standard-calls.md")
        .unwrap()
        .1;
    let rendered = render();
    assert_eq!(
        block_of(page).expect("calls markers"),
        rendered,
        "run `cargo run -p ms-tooling --bin ms-tooling-dev -- skill-calls update`"
    );
    assert!(rendered.contains("length() Int"), "{rendered}");
}

/// The module map is rendered from the declarations too.
#[test]
fn skill_module_map_matches_the_declarations() {
    use ms_tooling::guide::skill_calls::{
        MODULES_END, MODULES_START, block_between, render_modules,
    };
    let page = files()
        .iter()
        .find(|(path, _)| *path == "references/standard-modules.md")
        .unwrap()
        .1;
    let rendered = render_modules();
    assert_eq!(
        block_between(page, MODULES_START, MODULES_END).expect("module markers"),
        rendered,
        "run `cargo run -p ms-tooling --bin ms-tooling-dev -- skill-calls update`"
    );
    assert!(rendered.contains("`@std/data/json.ms`: "), "{rendered}");
}

/// Every `ms.toml` the projects page shows parses with the real manifest reader, so the page
/// cannot teach a table or key the compiler rejects.
#[test]
fn skill_manifest_examples_parse() {
    use ms_driver::project::manifest::read_manifest;
    let page = files()
        .iter()
        .find(|(path, _)| *path == "references/projects-and-packages.md")
        .unwrap()
        .1;
    let mut parsed = 0;
    for after in page.split("<!-- manifest: ").skip(1) {
        let (name, rest) = after.split_once(" -->\n").expect("manifest marker");
        let text = rest
            .strip_prefix("```toml\n")
            .expect("toml fence")
            .split_once("```")
            .expect("closed fence")
            .0;
        let dir =
            std::env::temp_dir().join(format!("ms-skill-manifest-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        for sub in ["src/domain", "assets", "app/src", "libs/util/src"] {
            std::fs::create_dir_all(dir.join(sub)).unwrap();
        }
        for file in ["src/main.ms", "app/src/main.ms", "libs/util/src/greet.ms"] {
            std::fs::write(dir.join(file), "fn main() Void:\n\tvoid\n").unwrap();
        }
        std::fs::write(
            dir.join("libs/util/ms.toml"),
            "[project]\nname = \"util\"\nsource = \"src\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("src/domain/customers.ms"),
            "export type Customer:\n\tid: Int\n",
        )
        .unwrap();
        let (manifest, base) = if name == "member" {
            (dir.join("app/ms.toml"), dir.join("app"))
        } else {
            (dir.join("ms.toml"), dir.clone())
        };
        let _ = base;
        std::fs::write(&manifest, text).unwrap();
        let mut project = ms_driver::project::manifest::Project::default();
        read_manifest(manifest.to_str().unwrap(), &mut project)
            .unwrap_or_else(|e| panic!("manifest {name}: {e:?}"));
        let _ = std::fs::remove_dir_all(&dir);
        parsed += 1;
    }
    assert_eq!(parsed, 6, "retain every manifest example");
}

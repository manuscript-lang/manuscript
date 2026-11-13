//! Tests for documentation generation.

use ms_tooling::guide::docgen::{
    DescriptionPolicy, DocumentationEntry, check_descriptions, description_key, inventory,
    render_module, render_site_module, site_files, standard_description_policy,
    standard_library_markdown, to_json,
};
use ms_tooling::guide::json::{self, Json};
use ms_tooling::guide::{ApiDeclaration, ApiMember, ApiModule, standard_library};

#[test]
fn coverage_inside_artifacts_survives_regeneration() {
    let root = std::env::temp_dir().join(format!(
        "ms-docgen-coverage-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let artifacts = root.join("docs");
    let coverage = artifacts.join("coverage.json");
    std::fs::create_dir_all(&artifacts).unwrap();
    std::fs::write(artifacts.join("stale.md"), "retired page").unwrap();
    let result = std::process::Command::new(env!("CARGO_BIN_EXE_ms-docgen"))
        .arg("-artifacts")
        .arg(&artifacts)
        .arg("-static")
        .arg(root.join("static"))
        .arg("-coverage")
        .arg(&coverage)
        .output()
        .unwrap();
    assert!(result.status.success(), "{result:?}");
    assert!(!artifacts.join("stale.md").exists());
    assert!(
        artifacts
            .join("documentation/standard-library/reference/_index.md")
            .is_file()
    );
    let report = std::fs::read_to_string(&coverage).unwrap();
    assert!(
        json::parse(&report)
            .unwrap()
            .get("declarations")
            .unwrap()
            .as_i64()
            .unwrap()
            > 0
    );
    assert!(root.join("static/stdlib.json").is_file());

    // A bad report destination must fail before retiring the existing pages.
    let invalid_coverage = root.join("report-directory");
    std::fs::create_dir(&invalid_coverage).unwrap();
    let marker = artifacts.join("keep-on-error.md");
    std::fs::write(&marker, "existing page").unwrap();
    let failed = std::process::Command::new(env!("CARGO_BIN_EXE_ms-docgen"))
        .arg("-artifacts")
        .arg(&artifacts)
        .arg("-static")
        .arg(root.join("static"))
        .arg("-coverage")
        .arg(&invalid_coverage)
        .output()
        .unwrap();
    assert!(!failed.status.success());
    assert_eq!(std::fs::read_to_string(marker).unwrap(), "existing page");
    std::fs::remove_dir_all(root).unwrap();
}

fn member(name: &str, kind: &str, signature: &str, doc: &str) -> ApiMember {
    ApiMember {
        name: name.into(),
        kind: kind.into(),
        signature: signature.into(),
        doc: doc.into(),
        contract: String::new(),
        legacy_contract: String::new(),
    }
}

fn module(path: &str, declarations: Vec<ApiDeclaration>) -> ApiModule {
    ApiModule {
        path: path.into(),
        declarations,
    }
}

#[test]
fn declaration_kind_presentation() {
    for (kind, label) in [
        ("fn", "Function"),
        ("alternative", "Enum"),
        ("interface", "Interface"),
        ("type", "Type"),
        ("native", "Native type"),
    ] {
        let m = module(
            "example.ms",
            vec![ApiDeclaration {
                name: "example".into(),
                kind: kind.into(),
                ty: "fn(value: String) Bool".into(),
                declaration: "fn example(value: String) Bool\n".into(),
                ..ApiDeclaration::default()
            }],
        );
        let site = render_site_module(&m);
        assert!(
            site.contains(&format!("## example {{data-api-kind=\"{label}\"}}")),
            "{site}"
        );
        let portable = render_module(&m);
        assert!(
            portable.contains(&format!("**{label}**")) && !portable.contains("data-api-kind"),
            "{portable}"
        );
        for output in [&site, &portable] {
            assert!(
                !output.contains("Kind:") && output.contains("fn example(value: String) Bool"),
                "{output}"
            );
        }
        let data = to_json(std::slice::from_ref(&m));
        let Json::Obj(root) = json::parse(&data).unwrap() else {
            panic!()
        };
        assert_eq!(root[0].1, Json::int(1));
        assert!(
            data.contains(&format!("\"kind\": \"{kind}\""))
                && data.contains("\"type\": \"fn(value: String) Bool\"")
        );
        assert!(
            !data.contains("Declaration") && !data.contains("\"declaration\""),
            "{data}"
        );
    }
}

#[test]
fn source_declarations_reach_documentation() {
    let syms = ms_syntax::Names::global();
    for module in standard_library(syms) {
        for output in [render_site_module(module), render_module(module)] {
            for d in &module.declarations {
                if !d.declaration.is_empty() {
                    assert!(
                        output.contains(&format!("```manuscript\n{}```", d.declaration)),
                        "{}#{} lost its source declaration",
                        module.path,
                        d.name
                    );
                }
            }
            for obsolete in [
                "\noperation ",
                "\nfield ",
                "\ntype parameters:",
                "<unknown>",
            ] {
                assert!(
                    !output.contains(obsolete),
                    "{} contains checker formatting {obsolete:?}",
                    module.path
                );
            }
        }
        if module.path == "@std/collections/collections.ms" {
            assert!(
                render_site_module(module).contains("## List {data-api-kind=\"Native type\"}"),
                "native receiver signatures must not label List as a source interface"
            );
        }
    }
    assert!(site_files(syms).contains_key("website/static/stdlib.json"));
}

#[test]
fn mixed_prelude_module_import_guidance() {
    for (path, guidance) in [
        (
            "@std/core.ms",
            "`Error`, `Optional`, `Result`, `Equal`, `Comparable`, and `Hashable` are prelude declarations",
        ),
        (
            "@std/collections/collections.ms",
            "`List`, `Map`, `Set`, `ListEntry`, and `MapEntry`",
        ),
    ] {
        let text = render_module(&module(path, vec![]));
        assert!(
            text.contains(guidance)
                && text.contains("Import other names")
                && text.contains("explicit imports")
                && !text.contains("These names are available"),
            "{path}: {text}"
        );
    }
}

#[test]
fn member_descriptions_reach_markdown_and_compatible_json() {
    let data = ApiDeclaration {
        name: "Data".into(),
        kind: "type".into(),
        ty: "Data".into(),
        declaration: "type Data:\n    value: Int\n".into(),
        fields: vec!["value: Int".into()],
        cases: vec!["Ready(value: Int)".into()],
        operations: vec!["read: fn() Int".into()],
        members: vec![
            member(
                "value",
                "field",
                "value: Int",
                "The **stored** count.\n\nMeasured in items.",
            ),
            member("Ready", "case", "Ready(value: Int)", "Completed work."),
            member(
                "read",
                "operation",
                "fn read() Int",
                "Reads without mutation.",
            ),
            member("missing", "field", "missing: Int", ""),
        ],
        ..ApiDeclaration::default()
    };
    let m = module("example.ms", vec![data]);
    let output = render_module(&m);
    for want in [
        "### Data.value",
        "The **stored** count.\n\nMeasured in items.",
        "### Data.Ready",
        "Completed work.",
        "### Data.read",
        "Reads without mutation.",
        "fn read() Int",
    ] {
        assert!(output.contains(want), "missing {want:?}: {output}");
    }
    assert!(
        !output.contains("### Data.missing"),
        "undocumented member fabricated a description"
    );
    let json = to_json(&[m]);
    for want in [
        "\"value: Int\"",
        "\"Ready(value: Int)\"",
        "\"read: fn() Int\"",
    ] {
        assert!(json.contains(want), "{json}");
    }
}

#[test]
fn description_inventory_includes_missing_members() {
    let syms = ms_syntax::Names::global();
    let modules = vec![module(
        "fixture.ms",
        vec![
            ApiDeclaration {
                name: "Data".into(),
                doc: "A record.".into(),
                members: vec![
                    member("present", "field", "", "A value."),
                    member("missing", "operation", "", ""),
                ],
                ..ApiDeclaration::default()
            },
            ApiDeclaration {
                name: "Missing".into(),
                ..ApiDeclaration::default()
            },
        ],
    )];
    let report = inventory(&modules);
    assert!(
        report.declarations == 2
            && report.described_declarations == 1
            && report.members == 2
            && report.described_members == 1
            && report.entries.len() == 4
    );
    assert!(!report.entries[2].described && report.entries[2].name == "missing");
    let standard = inventory(standard_library(syms));
    assert!(
        standard.members > 0 && standard.entries.len() == standard.declarations + standard.members
    );
}

fn payload(members: Vec<ApiMember>) -> Vec<ApiModule> {
    vec![module(
        "fixture",
        vec![ApiDeclaration {
            name: "Payload".into(),
            doc: "Holds a host failure diagnostic.".into(),
            members,
            ..ApiDeclaration::default()
        }],
    )]
}

#[test]
fn description_gate_rejects_placeholders_and_name_restatements() {
    let entry = DocumentationEntry {
        module: "fixture".into(),
        declaration: "Payload".into(),
        kind: "field".into(),
        name: "message".into(),
        ..DocumentationEntry::default()
    };
    let problem = |doc: &str| {
        let report = inventory(&payload(vec![member("message", "field", "", doc)]));
        let _ = &entry;
        report.entries[1].problem.clone()
    };
    for doc in [
        "",
        " \n ",
        "TODO: add details later.",
        "Returns a value.",
        "This is the public message field.",
        "Documentation about the Payload message field.",
        "The message value as a String.",
    ] {
        assert!(!problem(doc).is_empty(), "boilerplate passed: {doc:?}");
    }
    for doc in [
        "Original host diagnostic text, returned unchanged by message().",
        "Maximum UTF-8 bytes in one record; none adds no budget.",
        "Returns a shallow copy; nested mutable references remain shared.",
    ] {
        assert_eq!(problem(doc), "", "useful contract rejected: {doc:?}");
    }
}

#[test]
fn description_gate_ratchets_only_exact_existing_gaps() {
    let mut modules = payload(vec![member("message", "field", "", "")]);
    let report = inventory(&modules);
    let key = description_key(&report.entries[1]);
    let policy = DescriptionPolicy {
        format: 1,
        backlog: vec![key],
    };
    assert!(check_descriptions(&report, &policy).is_empty());
    modules[0].declarations[0]
        .members
        .push(member("new_field", "field", "", ""));
    let problems = check_descriptions(&inventory(&modules), &policy);
    assert!(
        problems.len() == 1 && problems[0].contains("new_field"),
        "new gap was allowed: {problems:?}"
    );
    modules[0].declarations[0].members.truncate(1);
    modules[0].declarations[0].members[0].doc = "This is the public message field.".into();
    let problems = check_descriptions(&inventory(&modules), &policy);
    assert_eq!(
        problems.len(),
        2,
        "backlog waived invalid prose or failed to shrink: {problems:?}"
    );
    modules[0].declarations[0].members[0].doc =
        "Original host diagnostic text returned unchanged.".into();
    let problems = check_descriptions(&inventory(&modules), &policy);
    assert!(
        problems.len() == 1 && problems[0].contains("stale backlog"),
        "{problems:?}"
    );
    assert!(
        check_descriptions(
            &inventory(&modules),
            &DescriptionPolicy {
                format: 1,
                backlog: vec![]
            }
        )
        .is_empty()
    );
    modules[0].declarations[0].members.clear();
    let problems = check_descriptions(&inventory(&modules), &policy);
    assert!(
        problems.len() == 1 && problems[0].contains("no longer exists"),
        "{problems:?}"
    );
}

#[test]
fn description_inventory_distinguishes_presence_from_quality() {
    let report = inventory(&[module(
        "fixture",
        vec![ApiDeclaration {
            name: "Payload".into(),
            doc: "A type.".into(),
            members: vec![member(
                "message",
                "field",
                "",
                "Original host diagnostic text returned unchanged.",
            )],
            ..ApiDeclaration::default()
        }],
    )]);
    assert!(
        report.described_declarations == 1
            && report.qualified_declarations == 0
            && report.described_members == 1
            && report.qualified_members == 1
            && !report.includes_prelude_aliases
    );
}

#[test]
fn the_standard_library_passes_its_own_gate() {
    let syms = ms_syntax::Names::global();
    let report = inventory(standard_library(syms));
    let policy = standard_description_policy().unwrap();
    assert_eq!(check_descriptions(&report, &policy), Vec::<String>::new());
    assert!(
        standard_library_markdown(syms).starts_with("# Manuscript implemented standard library")
    );
}

#[test]
fn generated_pages_link_to_tracked_sources() {
    let syms = ms_syntax::Names::global();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let files = site_files(syms);
    let mut pages = 0;
    for (path, bytes) in &files {
        let text = String::from_utf8_lossy(bytes);
        let Some(source) = text
            .lines()
            .find_map(|l| l.strip_prefix("edit_source = \""))
            .and_then(|l| l.strip_suffix('"'))
        else {
            continue;
        };
        pages += 1;
        assert!(root.join(source).is_file(), "{path} edits missing {source}");
    }
    assert!(pages > 0, "no generated page names its source");
    assert!(!standard_library_markdown(syms).contains("ms doc"));
}

#[test]
fn inherent_methods_keep_public_names_and_real_contracts() {
    let modules = standard_library(ms_syntax::Names::global());
    for module in modules {
        let text = render_module(module);
        assert!(!text.contains("$methods"), "{}: {text}", module.path);
        assert!(!text.contains("SourceMethods"), "{}: {text}", module.path);
        assert!(!to_json(std::slice::from_ref(module)).contains("$methods"));
    }
    for (path, name, operation) in [
        ("@std/data/histogram.ms", "Histogram", "record"),
        ("@std/concurrency/promise.ms", "Promise", "wait"),
        ("@std/io/io.ms", "ReadStream", "next"),
    ] {
        let module = modules.iter().find(|m| m.path == path).unwrap();
        let declaration = module.declarations.iter().find(|d| d.name == name).unwrap();
        assert!(
            declaration
                .members
                .iter()
                .any(|m| m.name == operation && m.contract.is_empty()),
            "{declaration:?}"
        );
        assert!(render_module(module).contains(&format!(".{operation}(")));
        if name == "Promise" {
            assert!(
                render_site_module(module)
                    .contains("api-legacy-anchor \"Promise.Promise$methods[T].wait\"")
            );
            assert!(declaration.implements.iter().any(|c| c == "Closeable"));
        }
    }
}

#[test]
fn reference_navigation_follows_source_paths_and_preserves_old_routes() {
    let syms = ms_syntax::Names::global();
    let files = site_files(syms);
    for module in standard_library(syms) {
        let path = module.path.strip_prefix("@std/").unwrap_or(&module.path);
        let stem = path.strip_suffix(".ms").unwrap_or(path);
        let page = &files[&format!("documentation/standard-library/reference/{path}.md")];
        let text = String::from_utf8_lossy(page);
        let title = path.rsplit('/').next().unwrap();
        assert!(text.contains(&format!("title = {title:?}")));
        let old = ms_check::api::stdlib::module_stem(&module.path).replace('/', "-");
        if old != stem {
            assert!(text.contains(&format!(
                "aliases = [\"/standard-library/reference/{old}/\"]"
            )));
        }
        if let Some((parent, _)) = stem.rsplit_once('/') {
            let index = String::from_utf8_lossy(
                &files[&format!("documentation/standard-library/reference/{parent}/_index.md")],
            );
            assert!(index.contains(&format!("[{title}]({title}.md)")));
        }
    }
    assert!(!files.contains_key("documentation/standard-library/reference/promise.md"));
}

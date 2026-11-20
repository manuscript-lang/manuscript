//! Developer tool: run a source tool on standalone `.ms` files and print the
//! output of the matching `ms` command, so the two can be diffed.
//!
//! ```text
//! ms-tooling-dev lint FILE...
//! ms-tooling-dev inspect FILE
//! ms-tooling-dev facts FILE                 the fact model as JSON, the input of tools/ms/views.ms
//! ms-tooling-dev view FILE VIEW ENTITY DEPTH FORMAT   one `ms diagram` view (ascii, mermaid, json)
//! ms-tooling-dev skill-calls update         rewrite the standard-call table in the agent skill
//! ```
//!
//! Only files without local imports are supported; projects and aliases belong
//! to the driver.

use ms_check::{CheckOptions, ImportMap};
use std::path::Path;
use std::sync::Arc;

fn main() {
    let syms = ms_syntax::Names::global();
    let handle = std::thread::Builder::new()
        .stack_size(512 << 20)
        .spawn(move || run(syms))
        .expect("spawn");
    std::process::exit(handle.join().unwrap_or(2));
}

fn run(syms: ms_syntax::Names) -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((command, files)) = args.split_first() else {
        eprintln!("usage: ms-tooling-dev lint FILE...");
        return 2;
    };
    match command.as_str() {
        "lint" => lint(syms, files),
        "inspect" => inspect(syms, files),
        "facts" => facts_json(syms, files),
        "view" => view(syms, files),
        "skill-calls" => skill_calls(files),
        other => {
            eprintln!("unknown command {other}");
            2
        }
    }
}

fn lint(syms: ms_syntax::Names, files: &[String]) -> i32 {
    let mut status = 0;
    for path in files {
        let text = std::fs::read_to_string(path).expect("read source");
        let file: Arc<str> = Arc::from(
            Path::new(path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(path),
        );
        let module = match ms_syntax::parser::parse(&file, &text) {
            Ok(m) => m,
            Err(d) => {
                println!("{d}");
                status = 1;
                continue;
            }
        };
        let program = ms_check::check(
            syms,
            vec![ms_check::load_module(syms, &module)],
            ImportMap::default(),
            CheckOptions::default(),
        );
        if !program.diagnostics.is_empty() {
            for d in &program.diagnostics {
                println!("{d}");
            }
            status = 1;
            continue;
        }
        for f in ms_tooling::lint::lint_modules(syms, &program) {
            println!(
                "{}:{}:{}: {} {}",
                f.file, f.pos.line, f.pos.column, f.code, f.message
            );
            status = 1;
        }
    }
    status
}

/// Parses and checks one standalone file, printing diagnostics on failure.
fn checked(syms: ms_syntax::Names, path: &str) -> Option<ms_check::Program> {
    let text = std::fs::read_to_string(path).expect("read source");
    let file: Arc<str> = Arc::from(
        Path::new(path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(path),
    );
    let module = match ms_syntax::parser::parse(&file, &text) {
        Ok(m) => m,
        Err(d) => {
            println!("{d}");
            return None;
        }
    };
    let program = ms_check::check(
        syms,
        vec![ms_check::load_module(syms, &module)],
        ImportMap::default(),
        CheckOptions::default(),
    );
    if program.diagnostics.is_empty() {
        return Some(program);
    }
    for d in &program.diagnostics {
        println!("{d}");
    }
    None
}

fn inspect(syms: ms_syntax::Names, files: &[String]) -> i32 {
    let Some(program) = files.first().and_then(|f| checked(syms, f)) else {
        return 1;
    };
    println!(
        "{}",
        ms_tooling::inspect::inspect(syms, &program)
            .to_json()
            .pretty(ms_json::Escape::HtmlSafe)
    );
    0
}

/// `skill-calls update` renders the standard-call table into `references/standard-calls.md`.
fn skill_calls(args: &[String]) -> i32 {
    use ms_tooling::guide::skill_calls::{
        MODULES_END, MODULES_START, block_between, block_of, render, render_modules, splice,
        splice_between,
    };
    let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("data/agent-skill");
    match args.first() {
        Some(mode) if mode == "update" => {
            let path = data.join("references/standard-calls.md");
            let page = std::fs::read_to_string(&path).expect("standard calls page");
            let Some(updated) = splice(&page, &render()) else {
                eprintln!("standard-calls.md has no calls:start and calls:end markers");
                return 2;
            };
            let mut changed = block_of(&page) != block_of(&updated);
            std::fs::write(&path, updated).expect("write standard calls page");
            let path = data.join("references/standard-modules.md");
            let page = std::fs::read_to_string(&path).expect("standard modules page");
            let Some(updated) =
                splice_between(&page, MODULES_START, MODULES_END, &render_modules())
            else {
                eprintln!("standard-modules.md has no modules:start and modules:end markers");
                return 2;
            };
            changed |= block_between(&page, MODULES_START, MODULES_END)
                != block_between(&updated, MODULES_START, MODULES_END);
            std::fs::write(&path, updated).expect("write standard modules page");
            eprintln!("{}", if changed { "updated" } else { "unchanged" });
            0
        }
        _ => {
            eprintln!("usage: ms-tooling-dev skill-calls update");
            2
        }
    }
}

fn facts_of(syms: ms_syntax::Names, path: &str) -> Option<ms_tooling::facts::Facts> {
    let program = checked(syms, path)?;
    Some(ms_tooling::collect::collect_facts(
        syms,
        &ms_tooling::inspect::collect(syms, &program).rows(),
        &program,
    ))
}

fn node_json(n: &ms_tooling::tree::Node) -> ms_json::Json {
    ms_json::obj([
        ("label", ms_json::Json::str(&n.label)),
        ("kind", ms_json::Json::str(&n.kind)),
        ("reference", ms_json::Json::str(&n.reference)),
        ("file", ms_json::Json::str(&n.file)),
        ("line", ms_json::Json::int(n.line as i64)),
        ("omitted", ms_json::Json::int(0)),
        (
            "children",
            ms_json::Json::Arr(n.children.iter().map(node_json).collect()),
        ),
    ])
}

fn slot_json(s: &ms_tooling::facts::Slot) -> ms_json::Json {
    ms_json::obj([
        ("name", ms_json::Json::str(&s.name)),
        ("ty", ms_json::Json::str(&s.ty)),
        ("exclusive", ms_json::Json::Bool(s.var)),
        ("mode", ms_json::Json::str(s.passing_mode())),
        ("refs", ms_json::Json::strings(&s.refs)),
    ])
}

/// The fact model of one file, with entities in key order, as `tools/ms/views.ms` reads it.
fn facts_value(facts: &ms_tooling::facts::Facts) -> ms_json::Json {
    let entities = facts
        .entities
        .values()
        .map(|f| {
            ms_json::obj([
                ("key", ms_json::Json::str(&f.key)),
                ("file", ms_json::Json::str(&f.file)),
                ("kind", ms_json::Json::str(&f.kind)),
                ("name", ms_json::Json::str(&f.name)),
                ("line", ms_json::Json::int(f.line as i64)),
                ("effects", ms_json::Json::strings(&f.effects)),
                ("error", ms_json::Json::str(&f.error)),
                ("tries", ms_json::Json::int(f.tries as i64)),
                ("scopes", ms_json::Json::int(f.scopes as i64)),
                ("calls", ms_json::Json::strings(&f.calls)),
                ("external", ms_json::Json::strings(&f.external)),
                (
                    "slots",
                    ms_json::Json::Arr(f.slots.iter().map(slot_json).collect()),
                ),
                (
                    "result",
                    f.result.as_ref().map_or(ms_json::Json::Null, slot_json),
                ),
                (
                    "result_ownership",
                    ms_json::Json::str(f.result_ownership.label()),
                ),
                (
                    "result_borrow",
                    ms_json::Json::Bool(matches!(
                        f.result_ownership,
                        ms_tooling::facts::ResultOwnership::Borrow
                    )),
                ),
                ("receiver", ms_json::Json::str(f.receiver)),
            ])
        })
        .collect();
    let imports = facts
        .imports
        .iter()
        .map(|(file, paths)| {
            ms_json::obj([
                ("file", ms_json::Json::str(file)),
                ("paths", ms_json::Json::strings(paths)),
            ])
        })
        .collect();
    let flows = facts
        .flows
        .iter()
        .map(|(key, steps)| {
            ms_json::obj([
                ("key", ms_json::Json::str(key)),
                (
                    "steps",
                    ms_json::Json::Arr(steps.iter().map(node_json).collect()),
                ),
            ])
        })
        .collect();
    ms_json::obj([
        ("entities", ms_json::Json::Arr(entities)),
        ("imports", ms_json::Json::Arr(imports)),
        ("flows", ms_json::Json::Arr(flows)),
    ])
}

fn facts_json(syms: ms_syntax::Names, files: &[String]) -> i32 {
    let Some(facts) = files.first().and_then(|f| facts_of(syms, f)) else {
        return 1;
    };
    println!("{}", facts_value(&facts).pretty(ms_json::Escape::HtmlSafe));
    0
}

/// `view FILE VIEW ENTITY DEPTH FORMAT`: the text `ms diagram` prints for the view.
fn view(syms: ms_syntax::Names, args: &[String]) -> i32 {
    let [file, name, entity, depth, format] = args else {
        eprintln!("usage: ms-tooling-dev view FILE VIEW ENTITY DEPTH ascii|mermaid|json");
        return 2;
    };
    let Some(facts) = facts_of(syms, file) else {
        return 1;
    };
    let depth: i64 = depth.parse().expect("depth");
    let tree = match ms_tooling::views::build_view(&facts, name, entity, depth) {
        Ok(tree) => tree,
        Err(message) => {
            println!("error: {message}");
            return 2;
        }
    };
    let text = match format.as_str() {
        "json" => {
            ms_json::obj([
                ("format", ms_json::Json::int(1)),
                ("view", ms_json::Json::str(name)),
                ("entity", ms_json::Json::str(entity)),
                ("tree", tree.to_json()),
            ])
            .pretty_line(ms_json::Escape::HtmlSafe)
                + "\n"
        }
        "mermaid" => ms_tooling::views::mermaid_view(&facts, name, entity, depth)
            .unwrap_or_else(|| tree.mermaid()),
        _ => ms_tooling::views::ascii_view(&facts, name, entity, depth)
            .unwrap_or_else(|| tree.ascii()),
    };
    print!("{text}");
    0
}

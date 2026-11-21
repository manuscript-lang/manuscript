//! Developer tool: run a source tool on standalone `.ms` files and print the
//! output of the matching `ms` command, so the two can be diffed.
//!
//! ```text
//! ms-tooling-dev lint FILE...
//! ms-tooling-dev inspect FILE
//! ms-tooling-dev facts FILE                 the fact model as JSON, the input of src/ms/views.ms
//! ms-tooling-dev nodes FILE                 `ID KIND` per typed expression, the oracle of `ms_check_dump --nodes`
//! ms-tooling-dev view FILE VIEW ENTITY DEPTH FORMAT   one `ms diagram` view (ascii, mermaid, json)
//! ms-tooling-dev review BASE HEAD [--no-base] [--added FILE]... [--touch FILE:LINE]...
//!                                           the ranked findings of `ms review` as JSON, the oracle of src/ms/review.ms
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
        "nodes" => nodes(syms, files),
        "view" => view(syms, files),
        "review" => review(syms, files),
        "report" => report(syms, files),
        "html" => html(syms, files),
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
    let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../src/ms/data/agent-skill");
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

/// The fact model of one file, with entities in key order, as `src/ms/views.ms` reads it.
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
                ("label", ms_json::Json::str(&f.label)),
                ("ty", ms_json::Json::str(&f.ty)),
                ("exported", ms_json::Json::Bool(f.exported)),
                ("reach", ms_json::Json::strings(&f.reach)),
                ("permits", ms_json::Json::strings(&f.permits)),
                ("first", ms_json::Json::int(f.first as i64)),
                ("last", ms_json::Json::int(f.last as i64)),
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

/// The options `review` and `report` share.
struct ReviewArgs {
    input: ms_tooling::review::DiffInput,
    all: bool,
    effect: String,
    format: String,
    project: bool,
    paths: Vec<String>,
}

fn review_args(args: &[String]) -> Option<ReviewArgs> {
    let mut out = ReviewArgs {
        input: ms_tooling::review::DiffInput {
            base_checked: true,
            ..Default::default()
        },
        all: false,
        effect: String::new(),
        format: "ascii".into(),
        project: false,
        paths: Vec::new(),
    };
    let mut options = args.iter();
    while let Some(option) = options.next() {
        match option.as_str() {
            "--no-base" => out.input.base_checked = false,
            "--project" => out.project = true,
            "--all" => out.all = true,
            "--effect" => out.effect = options.next()?.clone(),
            "--format" => out.format = options.next()?.clone(),
            "--added" => {
                out.input.added.insert(options.next()?.clone());
            }
            "--touch" => {
                let (file, line) = options.next()?.rsplit_once(':')?;
                out.input
                    .touched
                    .entry(file.to_string())
                    .or_default()
                    .push(line.parse().ok()?);
            }
            "--stats" => {
                let mut number = || options.next()?.parse::<usize>().ok();
                out.input.files = number()?;
                out.input.sources = number()?;
                out.input.insertions = number()?;
                out.input.deletions = number()?;
            }
            other if other.starts_with("--") => return None,
            _ => out.paths.push(option.clone()),
        }
    }
    Some(out)
}

/// `review BASE HEAD [options]`: the findings of `compare_facts` as a JSON array, in rank order.
fn review(syms: ms_syntax::Names, args: &[String]) -> i32 {
    let Some(parsed) = review_args(args) else {
        eprintln!(
            "usage: ms-tooling-dev review BASE HEAD [--no-base] [--added FILE]... [--touch FILE:LINE]..."
        );
        return 2;
    };
    let [base, head] = parsed.paths.as_slice() else {
        eprintln!("review needs BASE and HEAD");
        return 2;
    };
    let (Some(base), Some(head)) = (facts_of(syms, base), facts_of(syms, head)) else {
        return 1;
    };
    let findings = ms_tooling::review::compare_facts(&base, &head, &parsed.input);
    let json = ms_json::Json::Arr(
        findings
            .iter()
            .map(ms_tooling::review::Finding::to_json)
            .collect(),
    );
    println!("{}", json.pretty(ms_json::Escape::HtmlSafe));
    0
}

/// `report BASE HEAD [options]` or `report --project HEAD [options]`: the rendered review report.
fn report(syms: ms_syntax::Names, args: &[String]) -> i32 {
    let Some(parsed) = review_args(args) else {
        eprintln!("usage: ms-tooling-dev report BASE HEAD [options] | --project HEAD");
        return 2;
    };
    let options = ms_tooling::report::ReviewOptions {
        all: parsed.all,
        effect: &parsed.effect,
    };
    let report = if parsed.project {
        let [head] = parsed.paths.as_slice() else {
            eprintln!("report --project needs HEAD");
            return 2;
        };
        let Some(head) = facts_of(syms, head) else {
            return 1;
        };
        ms_tooling::report::project_report(&head, options)
    } else {
        let [base, head] = parsed.paths.as_slice() else {
            eprintln!("report needs BASE and HEAD");
            return 2;
        };
        let (Some(base), Some(head)) = (facts_of(syms, base), facts_of(syms, head)) else {
            return 1;
        };
        ms_tooling::report::diff_report(&base, &head, &parsed.input, options)
    };
    print!("{}", report.render(&parsed.format));
    0
}

/// `html HEAD [BASE]`: the interactive page, with the findings against BASE when given and no type hints.
fn html(syms: ms_syntax::Names, args: &[String]) -> i32 {
    let (Some(head_file), base_file) = (args.first(), args.get(1)) else {
        eprintln!("usage: ms-tooling-dev html HEAD [BASE]");
        return 2;
    };
    let Some(head) = facts_of(syms, head_file) else {
        return 1;
    };
    let findings = match base_file {
        Some(file) => {
            let Some(base) = facts_of(syms, file) else {
                return 1;
            };
            let input = ms_tooling::review::DiffInput {
                base_checked: true,
                ..Default::default()
            };
            Some(ms_tooling::review::compare_facts(&base, &head, &input))
        }
        None => None,
    };
    print!(
        "{}",
        ms_tooling::html::html_page(&head, findings.as_deref(), &[])
    );
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

struct KindScan<'a> {
    module: &'a ms_check::ModuleData,
    out: Vec<(u32, &'static str)>,
}

impl ms_syntax::visit::Visitor for KindScan<'_> {
    fn expr(&mut self, e: &ms_syntax::ast::Expr) {
        use ms_check::api::types::Builtin as B;
        let Some(ty) = self.module.facts().info(e.id).and_then(|i| i.ty.clone()) else {
            return;
        };
        let kinds = [
            (B::Optional, "Optional"),
            (B::Result, "Result"),
            (B::List, "List"),
            (B::Map, "Map"),
            (B::Set, "Set"),
            (B::Bytes, "Bytes"),
            (B::Int, "Int"),
            (B::Float, "Float"),
            (B::Bool, "Bool"),
            (B::Void, "Void"),
            (B::Promise, "Promise"),
        ];
        let kind = if ty.is_string() {
            "String"
        } else {
            kinds
                .iter()
                .find(|(b, _)| ty.is(*b))
                .map_or("Other", |(_, n)| n)
        };
        self.out.push((e.id.0, kind));
    }
}

/// `nodes FILE`: `ID KIND` for each expression the Rust checker typed, sorted by id.
fn nodes(syms: ms_syntax::Names, files: &[String]) -> i32 {
    let Some(program) = files.first().and_then(|f| checked(syms, f)) else {
        return 1;
    };
    for module in program.modules.iter().filter(|m| !m.is_standard(syms)) {
        let mut scan = KindScan {
            module,
            out: Vec::new(),
        };
        for decl in &module.decls {
            ms_syntax::visit::walk_decl(&mut scan, decl.decl());
        }
        scan.out.sort();
        for (id, kind) in scan.out {
            println!("{id} {kind}");
        }
    }
    0
}

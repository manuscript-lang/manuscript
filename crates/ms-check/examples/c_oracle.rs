//! Prints the checker's standard-library tables in a canonical text form, so the C checker in
//! `compiler/` can be compared with it byte for byte (`make c-compiler-test`).
//! Temporary tooling for the C rewrite: delete it with the Rust checker.

use ms_check::Session;
use ms_check::api::types::{Native, SymKind};
use ms_syntax::Names;
use std::fmt::Write;

/// The diagnostic families the C checker implements so far; the scope mode prints only these.
const SCOPE_FAMILIES: [&str; 5] = [
    "reuses a prelude",
    "collides with another",
    "duplicate or intrinsic name ",
    "module does not export ",
    "unknown standard module ",
];

/// `c_oracle --scope FILE...`: the name-resolution diagnostics of each file, one per line.
fn scope_diagnostics(files: &[String]) {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in files {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: std::sync::Arc<str> = "main.ms".into();
        let Ok(module) = ms_syntax::parser::parse(&file, &source) else {
            continue;
        };
        if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
            continue;
        }
        let program = ms_check::check_in(
            syms,
            &session,
            vec![ms_check::load_module(syms, &module)],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        for d in &program.diagnostics {
            let family = SCOPE_FAMILIES.iter().any(|f| d.message.contains(f));
            if d.phase == ms_syntax::Phase::Resolution && family {
                println!("{path}:{}:{}: {}", d.pos.line, d.pos.column, d.message);
            }
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|a| a == "--scope") {
        scope_diagnostics(&args[1..]);
        return;
    }
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    let mut out = String::new();
    // `extern type`s of bundled source modules, by the module that declares them.
    for module in session.standard_modules() {
        for d in &module.decls {
            if matches!(&d.decl().kind, ms_check::api::ast::DeclKind::Type(r) if r.external) {
                let s = session
                    .standard_symbol(syms.str(d.name()))
                    .expect("extern type");
                let _ = writeln!(
                    out,
                    "extern {} {} id={} export={} vars={}",
                    syms.str(module.file),
                    syms.str(d.name()),
                    syms.str(s.id),
                    s.export,
                    s.variables().len()
                );
            }
        }
    }
    for module in session.standard_modules() {
        let file = syms.str(module.file);
        if session.standard_source_module(module.file).is_some() {
            continue;
        }
        let _ = writeln!(out, "module {file}");
        let mut rows: Vec<_> = session.standard_exports(file).into_iter().collect();
        rows.sort_by_key(|(name, _)| syms.str(*name).to_string());
        for (name, s) in rows {
            if matches!(s.native, Native::Source) {
                // The `+source` twin's exports are checked symbols, numbered in checking order.
                continue;
            }
            let kind = match s.kind {
                SymKind::Type => "type",
                SymKind::Fn => "fn",
                SymKind::Alias => "alias",
            };
            let native = match s.native {
                Native::Source => "source".to_string(),
                Native::Contract => "contract".to_string(),
                Native::Extern { symbol, bundled } => {
                    format!("extern:{}:{bundled}", syms.str(symbol))
                }
                Native::Builtin(b) => format!("builtin:{}", syms.str(b)),
            };
            let _ = writeln!(
                out,
                "  {} {kind} export={} id={} native={native} vars={}",
                syms.str(name),
                s.export,
                syms.str(s.id),
                s.variables().len()
            );
        }
    }
    print!("{out}");
}

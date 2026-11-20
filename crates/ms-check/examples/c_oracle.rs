//! Prints the checker's standard-library tables in a canonical text form, so the C checker in
//! `compiler/` can be compared with it byte for byte (`make c-compiler-test`).
//! Temporary tooling for the C rewrite: delete it with the Rust checker.

use ms_check::Session;
use ms_check::api::types::{Native, SymKind};
use ms_syntax::Names;
use std::fmt::Write;

fn main() {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    let mut out = String::new();
    // `extern type`s of bundled source modules, by the module that declares them.
    for module in session.standard_modules() {
        for d in &module.decls {
            if matches!(&d.decl().kind, ms_check::api::ast::DeclKind::Type(r) if r.external) {
                let s = session.standard_symbol(syms.str(d.name())).expect("extern type");
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
                Native::Extern { symbol, bundled } => format!("extern:{}:{bundled}", syms.str(symbol)),
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

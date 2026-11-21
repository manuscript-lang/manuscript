//! Prints what inherent-impl desugaring gives for source files, so the C checker in `src/compiler/`
//! can be compared with it byte for byte (`src/compiler/tests/check-diff.sh`). Temporary tooling for
//! the C rewrite: delete it with the Rust checker.
//!
//!   c_oracle_desugar user|std FILE..
//!   c_oracle_desugar foreign FOREIGN FILE..
//!
//! `user` desugars each file as a project module, `std` as a bundled `@std/` module, and `foreign`
//! as a project module whose methods may also name the types of src/stdlib/core/core.ms.

use ms_check::desugar_oracle::desugar_inherent_impls;
use ms_syntax::Names;
use ms_syntax::ast::{Decl, DeclKind, Module, TypeKind};
use ms_syntax::dump::{dump_module, quote};
use ms_syntax::parser::parse;
use std::fmt::Write;
use std::sync::Arc;

fn ids(out: &mut String, d: &Decl) {
    let _ = write!(out, "decl {}", d.id.0);
    let methods = match &d.kind {
        DeclKind::Impl(i) => &i.methods,
        DeclKind::Interface(i) => &i.methods,
        _ => {
            out.push('\n');
            return;
        }
    };
    for m in methods {
        let _ = write!(out, " {}", m.id.0);
    }
    out.push('\n');
}

/// What the C pass does not build: the interface synthesized for a type's own methods and the
/// impl that carries it. The C pass keeps the written blocks, so only their methods are compared
/// (see src/compiler/tests/check-divergences.txt).
fn is_inherent(syms: Names, d: &Decl) -> bool {
    match &d.kind {
        DeclKind::Interface(i) => syms.str(i.name).ends_with("$methods"),
        DeclKind::Impl(i) => matches!(
            i.contract.as_ref().map(|c| &c.kind),
            Some(TypeKind::Named { name, .. }) if syms.str(*name).ends_with("$methods")
        ),
        _ => false,
    }
}

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mode = args.remove(0);
    let mode = mode.as_str();
    let syms = Names::global();
    let file: Arc<str> = Arc::from(if mode == "std" { "@std/f.ms" } else { "f.ms" });
    let foreign: Vec<Decl> = if mode == "foreign" {
        let text = std::fs::read_to_string(args.remove(0)).expect("foreign file");
        let module = parse(&Arc::from("f.ms"), &text).expect("parse foreign file");
        module
            .decls
            .into_iter()
            .filter(|d| matches!(d.kind, DeclKind::Type(_) | DeclKind::Alternative(_)))
            .collect()
    } else {
        Vec::new()
    };
    let mut out = String::new();
    for path in &args {
        let _ = writeln!(out, "=== {path}");
        let bytes = std::fs::read(path).expect("read");
        let Ok(text) = std::str::from_utf8(&bytes) else {
            out.push_str("error invalid-utf8\n");
            continue;
        };
        let Ok(module) = parse(&file, text) else {
            out.push_str("parse-error\n");
            continue;
        };
        let (decls, errors, node_count) = desugar_inherent_impls(syms, &module, &foreign);
        let mut methods: Vec<String> = Vec::new();
        for d in decls.iter().filter(|d| is_inherent(syms, d)) {
            if let DeclKind::Impl(i) = &d.kind {
                for m in &i.methods {
                    methods.push(format!(
                        "method {} {}:{}\n",
                        syms.str(m.func.name),
                        m.pos.line,
                        m.pos.column
                    ));
                }
            }
        }
        methods.sort();
        let desugared = Module {
            decls: decls
                .into_iter()
                .filter(|d| !is_inherent(syms, d))
                .collect(),
            node_count,
            ..module
        };
        out.push_str(&dump_module(syms, &desugared));
        desugared.decls.iter().for_each(|d| ids(&mut out, d));
        methods.iter().for_each(|m| out.push_str(m));
        for e in &errors {
            let p = e.pos;
            let _ = writeln!(
                out,
                "inherent {}:{}:{} {}",
                p.line,
                p.column,
                p.offset,
                quote(&e.message)
            );
        }
    }
    print!("{out}");
}

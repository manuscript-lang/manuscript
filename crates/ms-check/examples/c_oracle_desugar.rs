//! Prints what inherent-impl desugaring gives for source files, so the C checker in `compiler/`
//! can be compared with it byte for byte (`compiler/tests/check-diff.sh`). Temporary tooling for
//! the C rewrite: delete it with the Rust checker.
//!
//!   c_oracle_desugar user|std FILE..
//!   c_oracle_desugar foreign FOREIGN FILE..
//!
//! `user` desugars each file as a project module, `std` as a bundled `@std/` module, and `foreign`
//! as a project module whose methods may also name the types of stdlib/core/core.ms.

use ms_check::desugar_oracle::desugar_inherent_impls;
use ms_syntax::Names;
use ms_syntax::ast::{Decl, DeclKind, Module};
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
        let desugared = Module {
            decls,
            node_count,
            ..module
        };
        out.push_str(&dump_module(syms, &desugared));
        let _ = writeln!(out, "nodes {node_count}");
        desugared.decls.iter().for_each(|d| ids(&mut out, d));
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

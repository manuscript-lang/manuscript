//! Prints the operations of the interfaces a module declares and the methods its implementations
//! add, in a canonical text form, so the C checker in `compiler/` can be compared with it byte for
//! byte (`compiler/tests/check-diff.sh`). Temporary tooling for the C rewrite: delete it with the
//! Rust checker.
//!
//!   c_oracle_methods FILE..   each file that imports only `@std/` modules, as module `main.ms`

use ms_check::Session;
use ms_check::api::ast::DeclKind;
use ms_check::api::types::{SymKind, Ty};
use ms_syntax::Names;
use std::fmt::Write;

/// The diagnostics about operations the C checker implements so far.
const FAMILIES: [&str; 3] = [
    "duplicate operation ",
    "shadows a type parameter of the receiver",
    "Self can only be a whole parameter or result type",
];

fn show(syms: Names, t: &Ty) -> String {
    t.display(syms).to_string()
}

fn variables(syms: Names, vars: &[Ty]) -> String {
    let each: Vec<String> = vars
        .iter()
        .map(|v| {
            let default = v.default_ty().map_or("-".to_string(), |t| show(syms, &t));
            let bounds: Vec<String> = v.bounds().iter().map(|b| show(syms, b)).collect();
            format!("{} default={default} bounds={}", syms.str(v.name), bounds.join(","))
        })
        .collect();
    format!("[{}]", each.join("; "))
}

fn interface_operations(
    out: &mut String,
    syms: Names,
    session: &std::rc::Rc<Session>,
    program: &ms_check::Program,
    module: &ms_check::ModRef,
) {
    let Some(names) = program.symbols.get(&module.file) else {
        return;
    };
    for d in &module.decls {
        if !matches!(d.decl().kind, DeclKind::Interface(_)) {
            continue;
        }
        let name = d.name();
        let Some(s) = names
            .borrow()
            .get(&name)
            .filter(|s| s.decl.as_ref().is_some_and(|sd| sd.same(d)) && s.kind == SymKind::Type)
            .cloned()
        else {
            continue;
        };
        let ty = s.ty(syms);
        let Some(def) = ty.def.clone() else {
            continue;
        };
        for op in def.operations.borrow().iter() {
            let own = session.operation_variables(&format!(
                "{}/{}",
                syms.str(ty.id),
                syms.str(op.name)
            ));
            let labels: Vec<String> = op
                .ty
                .params
                .iter()
                .map(|p| {
                    format!(
                        "{}{}{}",
                        if p.mutable { "var " } else { "" },
                        if p.moving { "move " } else { "" },
                        syms.str(p.name)
                    )
                })
                .collect();
            let _ = writeln!(
                out,
                "op {}.{}: {} params={} vars={}",
                syms.str(name),
                syms.str(op.name),
                show(syms, &op.ty),
                labels.join(","),
                variables(syms, &own)
            );
        }
    }
}

fn main() {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in std::env::args().skip(1) {
        let Ok(source) = std::fs::read_to_string(&path) else {
            continue;
        };
        let file: std::sync::Arc<str> = "main.ms".into();
        let Ok(module) = ms_syntax::parser::parse(&file, &source) else {
            continue;
        };
        if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
            continue;
        }
        println!("== {path}");
        let loaded = ms_check::load_module(syms, &module);
        let program = ms_check::check_in(
            syms,
            &session,
            vec![loaded.clone()],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        for d in &program.diagnostics {
            if FAMILIES.iter().any(|f| d.message.contains(f)) {
                println!("{}:{}: {}", d.pos.line, d.pos.column, d.message);
            }
        }
        println!("--");
        let mut out = String::new();
        interface_operations(&mut out, syms, &session, &program, &loaded);
        print!("{out}");
    }
}

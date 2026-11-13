//! The type-and-impl adjacency rule: in the standard library, an `impl` block follows its type declaration or
//! another `impl` of the same type, so everything a type offers reads in one stretch of the file.

use crate::stdlib_modules::parsed;
use ms_syntax::ast::{DeclKind, Module};
use std::collections::BTreeSet;

pub fn check(syms: ms_syntax::Names, files: &[String]) -> Vec<String> {
    parsed(files)
        .flat_map(|(path, module)| {
            misplaced(syms, &module).into_iter().map(move |(line, name)| {
                format!("{path}:{line}: `impl` for `{name}` must directly follow `{name}` or another impl of it")
            })
        })
        .collect()
}

/// `(line, type)` for each impl on a type declared in the same module that does not follow it directly.
fn misplaced(syms: ms_syntax::Names, module: &Module) -> Vec<(u32, String)> {
    let local: BTreeSet<&str> = module
        .decls
        .iter()
        .filter_map(|d| match &d.kind {
            DeclKind::Type(r) => Some(syms.str(r.name)),
            DeclKind::Alternative(a) => Some(syms.str(a.name)),
            _ => None,
        })
        .collect();
    let mut found = Vec::new();
    let mut previous: Option<&str> = None;
    for decl in &module.decls {
        match &decl.kind {
            DeclKind::Type(r) => previous = Some(syms.str(r.name)),
            DeclKind::Alternative(a) => previous = Some(syms.str(a.name)),
            DeclKind::Impl(i) => {
                let name = i.receiver.name(syms);
                if local.contains(name) && previous != Some(name) {
                    found.push((decl.pos.line, name.to_string()));
                }
                previous = Some(name);
            }
            _ => previous = None,
        }
    }
    found
}

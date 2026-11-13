//! The optional-parameter rule: an exported standard-library function never requires a caller to write
//! `none`. A parameter of type `T?` therefore declares `= none` (or another default), and a parameter
//! named `options` or `limits` carries a default too (`options: FooOptions = FooOptions()`).
//! Modules in `stdlib/internal/` are extern glue and are not checked.
//!
//! `optional-defaults-allowed.txt` lists the parameters that predate the rule as `path owner.function
//! parameter` lines (`owner` is the function name, or `Type.method`). An entry is deleted by the change
//! that gives the parameter a default, and an entry whose parameter is gone or already defaulted fails
//! the check, so the list only shrinks.

use crate::stdlib_modules::{allow_list, check_shrinking, parsed};
use ms_syntax::ast::{DeclKind, Func};
use std::collections::BTreeSet;

const ALLOWED: &str = include_str!("../optional-defaults-allowed.txt");

pub fn check(syms: ms_syntax::Names, files: &[String]) -> Vec<String> {
    let mut found = Vec::new();
    for (path, module) in parsed(files).filter(|(p, _)| !p.starts_with("stdlib/internal/")) {
        let mut entries = Vec::new();
        for decl in module.decls.iter().filter(|d| d.export) {
            match &decl.kind {
                DeclKind::Fn(f) => undefaulted(syms, "", f, &mut entries),
                DeclKind::Interface(i) => {
                    let owner = syms.str(i.name).to_string();
                    for m in &i.methods {
                        undefaulted(syms, &owner, &m.func, &mut entries);
                    }
                }
                _ => {}
            }
        }
        // Methods of an impl are public when the receiver type is exported.
        let exported: BTreeSet<&str> = module
            .decls
            .iter()
            .filter(|d| d.export)
            .filter_map(|d| match &d.kind {
                DeclKind::Type(r) => Some(syms.str(r.name)),
                DeclKind::Alternative(a) => Some(syms.str(a.name)),
                _ => None,
            })
            .collect();
        for decl in &module.decls {
            if let DeclKind::Impl(i) = &decl.kind {
                let owner = i.receiver.name(syms);
                if exported.contains(owner) {
                    for m in &i.methods {
                        undefaulted(syms, owner, &m.func, &mut entries);
                    }
                }
            }
        }
        found.extend(entries.into_iter().map(|e| (path.to_string(), e)));
    }
    check_shrinking(
        &allow_list(ALLOWED),
        found,
        |path, entry| {
            format!(
                "{path}: `{entry}` is optional or an options type with no default; add `= none` or `= Options()` so callers never pass it explicitly"
            )
        },
        |entry| {
            format!(
                "crates/ms-repo-check/optional-defaults-allowed.txt: `{entry}` no longer needs an exception; delete the line"
            )
        },
    )
}

/// `owner.function parameter` for each parameter that must have a default and lacks one.
fn undefaulted(syms: ms_syntax::Names, owner: &str, func: &Func, found: &mut Vec<String>) {
    let name = syms.str(func.name);
    let function = if owner.is_empty() {
        name.to_string()
    } else {
        format!("{owner}.{name}")
    };
    for param in &func.params {
        if param.default.is_some() {
            continue;
        }
        let pname = syms.str(param.name);
        let optional = param
            .ty
            .as_ref()
            .is_some_and(|t| t.name(syms) == "Optional");
        let options_like = pname == "options" || pname == "limits";
        if optional || options_like {
            found.push(format!("{function} {pname}"));
        }
    }
}

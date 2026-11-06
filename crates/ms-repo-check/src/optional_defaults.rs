//! The optional-parameter rule: an exported standard-library function never requires a caller to write
//! `none`. A parameter of type `T?` therefore declares `= none` (or another default), and a parameter
//! named `options` or `limits` carries a default too (`options: FooOptions = FooOptions()`).
//! Modules in `stdlib/internal/` are extern glue and are not checked.
//!
//! `optional-defaults-allowed.txt` lists the parameters that predate the rule as `path owner.function
//! parameter` lines (`owner` is the function name, or `Type.method`). An entry is deleted by the change
//! that gives the parameter a default, and an entry whose parameter is gone or already defaulted fails
//! the check, so the list only shrinks.

use ms_syntax::ast::{DeclKind, Func};
use ms_syntax::parser::parse;
use std::collections::BTreeSet;
use std::sync::Arc;

const ALLOWED: &str = include_str!("../optional-defaults-allowed.txt");

pub fn check(syms: ms_syntax::Names, files: &[String]) -> Vec<String> {
    let allowed: BTreeSet<&str> = ALLOWED
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with("//"))
        .collect();
    let mut seen = BTreeSet::new();
    let mut issues = Vec::new();
    for path in files {
        if !path.starts_with("stdlib/")
            || !path.ends_with(".ms")
            || path.starts_with("stdlib/internal/")
        {
            continue;
        }
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: Arc<str> = Arc::from(path.as_str());
        let Ok(module) = parse(&file, &source) else {
            continue;
        };
        let mut found = Vec::new();
        for decl in module.decls.iter().filter(|d| d.export) {
            match &decl.kind {
                DeclKind::Fn(f) => undefaulted(syms, "", f, &mut found),
                DeclKind::Interface(i) => {
                    let owner = syms.str(i.name).to_string();
                    for m in &i.methods {
                        undefaulted(syms, &owner, &m.func, &mut found);
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
                DeclKind::Record(r) => Some(syms.str(r.name)),
                DeclKind::Alternative(a) => Some(syms.str(a.name)),
                _ => None,
            })
            .collect();
        for decl in &module.decls {
            if let DeclKind::Impl(i) = &decl.kind {
                let owner = i.receiver.name(syms);
                if exported.contains(owner) {
                    for m in &i.methods {
                        undefaulted(syms, owner, &m.func, &mut found);
                    }
                }
            }
        }
        for entry in found {
            let key = format!("{path} {entry}");
            if allowed.contains(key.as_str()) {
                seen.insert(key);
            } else {
                issues.push(format!(
                    "{path}: `{entry}` is optional or an options record with no default; add `= none` or `= Options()` so callers never pass it explicitly"
                ));
            }
        }
    }
    for entry in allowed {
        if !seen.contains(entry) {
            issues.push(format!(
                "crates/ms-repo-check/optional-defaults-allowed.txt: `{entry}` no longer needs an exception; delete the line"
            ));
        }
    }
    issues
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
        let record = pname == "options" || pname == "limits";
        if optional || record {
            found.push(format!("{function} {pname}"));
        }
    }
}

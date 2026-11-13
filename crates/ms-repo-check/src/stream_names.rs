//! The stream-shape rule: anything that yields or accepts values over time is a `ReadStream[T]` or
//! `WriteStream[T]`, so no exported standard-library type has a method named `next`, `receive`, `feed` or
//! `write_bytes` outside the stream modules. (`Source.next` and `Transform.feed` are the stream
//! implementation interfaces; types that implement them stay private.)
//!
//! `stream-names-allowed.txt` lists the methods that predate the rule as `path Type.method` lines. An entry
//! is deleted by the change that removes the method, and an entry whose method is gone fails the check, so
//! the list only shrinks.

use crate::stdlib_modules::{allow_list, check_shrinking, parsed};
use ms_syntax::ast::{DeclKind, Method, Module};
use std::collections::BTreeSet;

// `Iterator` is for sequences that never wait, so its `next` is not a stream method.
const ITERATOR: &str = "Iterator";
const BANNED: [&str; 4] = ["next", "receive", "feed", "write_bytes"];
const STREAM_MODULES: [&str; 2] = ["stdlib/io/io.ms", "stdlib/io/streams.ms"];
const ALLOWED: &str = include_str!("../stream-names-allowed.txt");

pub fn check(syms: ms_syntax::Names, files: &[String]) -> Vec<String> {
    let found = parsed(files)
        .filter(|(p, _)| !STREAM_MODULES.contains(p))
        .flat_map(|(path, module)| {
            exported_methods(syms, &module)
                .into_iter()
                .map(move |entry| (path.to_string(), entry))
        });
    check_shrinking(
        &allow_list(ALLOWED),
        found,
        |path, entry| {
            format!(
                "{path}: exported `{entry}` has a stream-shaped name; return a ReadStream[T] or take a WriteStream[T] instead (see proposals/stream-redesign.md)"
            )
        },
        |entry| {
            format!(
                "crates/ms-repo-check/stream-names-allowed.txt: `{entry}` no longer exists; delete the line"
            )
        },
    )
}

/// `Type.method` for each banned method of an exported interface or of an impl on an exported type.
fn exported_methods(syms: ms_syntax::Names, module: &Module) -> Vec<String> {
    let exported: BTreeSet<&str> = module
        .decls
        .iter()
        .filter(|d| d.export)
        .filter_map(|d| match &d.kind {
            DeclKind::Type(r) => Some(syms.str(r.name)),
            DeclKind::Alternative(a) => Some(syms.str(a.name)),
            DeclKind::Interface(i) => Some(syms.str(i.name)),
            _ => None,
        })
        .collect();
    let mut found = Vec::new();
    for decl in &module.decls {
        match &decl.kind {
            DeclKind::Interface(i) if decl.export && syms.str(i.name) != ITERATOR => {
                banned(syms, syms.str(i.name), &i.methods, &mut found);
            }
            DeclKind::Impl(i)
                if exported.contains(i.receiver.name(syms))
                    && i.contract.as_ref().is_none_or(|c| c.name(syms) != ITERATOR) =>
            {
                banned(syms, i.receiver.name(syms), &i.methods, &mut found);
            }
            _ => {}
        }
    }
    found
}

fn banned(syms: ms_syntax::Names, owner: &str, methods: &[Method], found: &mut Vec<String>) {
    for method in methods {
        let name = syms.str(method.func.name);
        if BANNED.contains(&name) {
            found.push(format!("{owner}.{name}"));
        }
    }
}

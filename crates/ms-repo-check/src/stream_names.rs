//! The stream-shape rule: anything that yields or accepts values over time is a `ReadStream[T]` or
//! `WriteStream[T]`, so no exported standard-library type has a method named `next`, `receive`, `feed` or
//! `write_bytes` outside the stream modules. (`Source.next` and `Transform.feed` are the stream
//! implementation interfaces; types that implement them stay private.)
//!
//! `stream-names-allowed.txt` lists the methods that predate the rule as `path Type.method` lines. An entry
//! is deleted by the change that removes the method, and an entry whose method is gone fails the check, so
//! the list only shrinks.

use ms_syntax::ast::{DeclKind, Method, Module};
use ms_syntax::parser::parse;
use std::collections::BTreeSet;
use std::sync::Arc;

// `Iterator` is for sequences that never wait, so its `next` is not a stream method.
const ITERATOR: &str = "Iterator";
const BANNED: [&str; 4] = ["next", "receive", "feed", "write_bytes"];
const STREAM_MODULES: [&str; 2] = ["stdlib/io/io.ms", "stdlib/io/streams.ms"];
const ALLOWED: &str = include_str!("../stream-names-allowed.txt");

pub fn check(files: &[String]) -> Vec<String> {
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
            || STREAM_MODULES.contains(&path.as_str())
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
        for entry in exported_methods(&module) {
            let key = format!("{path} {entry}");
            if allowed.contains(key.as_str()) {
                seen.insert(key);
            } else {
                issues.push(format!(
                    "{path}: exported `{entry}` has a stream-shaped name; return a ReadStream[T] or take a WriteStream[T] instead (see proposals/stream-redesign.md)"
                ));
            }
        }
    }
    for entry in allowed {
        if !seen.contains(entry) {
            issues.push(format!(
                "crates/ms-repo-check/stream-names-allowed.txt: `{entry}` no longer exists; delete the line"
            ));
        }
    }
    issues
}

/// `Type.method` for each banned method of an exported interface or of an impl on an exported type.
fn exported_methods(module: &Module) -> Vec<String> {
    let exported: BTreeSet<&str> = module
        .decls
        .iter()
        .filter(|d| d.export)
        .filter_map(|d| match &d.kind {
            DeclKind::Record(r) => Some(r.name.as_str()),
            DeclKind::Alternative(a) => Some(a.name.as_str()),
            DeclKind::Interface(i) => Some(i.name.as_str()),
            _ => None,
        })
        .collect();
    let mut found = Vec::new();
    for decl in &module.decls {
        match &decl.kind {
            DeclKind::Interface(i) if decl.export && i.name.as_str() != ITERATOR => {
                banned(i.name.as_str(), &i.methods, &mut found);
            }
            DeclKind::Impl(i)
                if exported.contains(i.receiver.name())
                    && i.contract.as_ref().is_none_or(|c| c.name() != ITERATOR) =>
            {
                banned(i.receiver.name(), &i.methods, &mut found);
            }
            _ => {}
        }
    }
    found
}

fn banned(owner: &str, methods: &[Method], found: &mut Vec<String>) {
    for method in methods {
        let name = method.func.name.as_str();
        if BANNED.contains(&name) {
            found.push(format!("{owner}.{name}"));
        }
    }
}

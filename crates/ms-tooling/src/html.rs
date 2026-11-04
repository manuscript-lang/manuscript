//! The interactive page: one self-contained HTML file that embeds the fact
//! model, so it opens offline and needs no server or library.
//!
//! The data is compact so a program with thousands of functions stays small:
//! files are interned, entities are arrays that refer to each other by index,
//! and flows are arrays of `[kind, label, callee, children]`.

use crate::facts::{Fact, Facts, Slot};
use crate::json::{Escape, Json};
use crate::review::Finding;
use crate::tree::Node;
use std::collections::HashMap;

const PAGE: &str = include_str!("page.html");
/// Labels are source lines; longer ones add bytes without adding meaning.
const LABEL_CAP: usize = 100;

struct Index<'a> {
    files: Vec<&'a str>,
    file_ix: HashMap<&'a str, usize>,
    entity_ix: HashMap<&'a str, usize>,
}

fn indices(ix: &Index, keys: &[String]) -> Json {
    Json::Arr(
        keys.iter()
            .filter_map(|k| ix.entity_ix.get(k.as_str()))
            .map(|i| Json::from(*i))
            .collect(),
    )
}

fn slot_json(ix: &Index, s: &Slot) -> Json {
    Json::Arr(vec![
        Json::str(&s.name),
        Json::str(&s.ty),
        Json::from(usize::from(s.var)),
        indices(ix, &s.refs),
    ])
}

fn flow_json(ix: &Index, nodes: &[Node]) -> Json {
    Json::Arr(
        nodes
            .iter()
            .map(|n| {
                let label: String = n.label.chars().take(LABEL_CAP).collect();
                let callee = ix
                    .entity_ix
                    .get(n.reference.as_str())
                    .map_or(-1, |i| *i as i64);
                Json::Arr(vec![
                    Json::str(&n.kind),
                    Json::str(label),
                    Json::int(callee),
                    flow_json(ix, &n.children),
                ])
            })
            .collect(),
    )
}

fn entity_json(facts: &Facts, ix: &Index, f: &Fact) -> Json {
    let flow = facts.flows.get(&f.key).map_or(&[][..], Vec::as_slice);
    Json::Arr(vec![
        Json::from(ix.file_ix[f.file.as_str()]),
        Json::str(&f.kind),
        Json::str(&f.name),
        Json::from(f.line),
        Json::from(usize::from(f.exported)),
        Json::strings(&f.effects),
        Json::str(&f.error),
        Json::from(f.scopes),
        indices(ix, &f.calls),
        Json::strings(&f.external),
        Json::Arr(f.slots.iter().map(|s| slot_json(ix, s)).collect()),
        f.result.as_ref().map_or(Json::from(0usize), |r| {
            Json::Arr(vec![Json::str(&r.ty), indices(ix, &r.refs)])
        }),
        flow_json(ix, flow),
    ])
}

/// The whole program as one interactive page. `changes` are a diff's findings:
/// the page marks those entities and lists what changed. The data is escaped
/// for embedding in a script element, so no program text can close it.
pub fn html_page(facts: &Facts, changes: Option<&[Finding]>) -> String {
    let mut ix = Index {
        files: Vec::new(),
        file_ix: HashMap::new(),
        entity_ix: HashMap::new(),
    };
    for f in facts.entities.values() {
        if !ix.file_ix.contains_key(f.file.as_str()) {
            ix.file_ix.insert(&f.file, ix.files.len());
            ix.files.push(&f.file);
        }
    }
    for file in facts.imports.keys() {
        if !ix.file_ix.contains_key(file.as_str()) {
            ix.file_ix.insert(file, ix.files.len());
            ix.files.push(file);
        }
    }
    for (i, key) in facts.entities.keys().enumerate() {
        ix.entity_ix.insert(key, i);
    }
    let modules = facts
        .imports
        .iter()
        .map(|(file, imports)| {
            Json::Arr(vec![
                Json::from(ix.file_ix[file.as_str()]),
                Json::strings(imports),
            ])
        })
        .collect();
    let entities = facts
        .entities
        .values()
        .map(|f| entity_json(facts, &ix, f))
        .collect();
    let mut data = Json::object()
        .with(
            "f",
            Json::strings(&ix.files.iter().map(|f| f.to_string()).collect::<Vec<_>>()),
        )
        .with("m", Json::Arr(modules))
        .with("e", Json::Arr(entities));
    if let Some(findings) = changes {
        // [entity index or -1 when removed, name, tier, what changed]
        let rows = findings
            .iter()
            .map(|f| {
                Json::Arr(vec![
                    Json::int(ix.entity_ix.get(f.id.as_str()).map_or(-1, |i| *i as i64)),
                    Json::str(&f.entity),
                    Json::str(&f.tier),
                    Json::strings(&f.changes),
                ])
            })
            .collect();
        data = data.with("x", Json::Arr(rows));
    }
    PAGE.replacen("__DATA__", &data.compact(Escape::HtmlSafe), 1)
}

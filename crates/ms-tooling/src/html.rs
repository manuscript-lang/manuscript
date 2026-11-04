//! The interactive page: one self-contained HTML file that embeds the fact
//! model, so it opens offline and needs no server or library.

use crate::facts::{Fact, Facts, Slot};
use crate::json::{Escape, Json, obj};

const PAGE: &str = include_str!("page.html");

fn slot_json(s: &Slot) -> Json {
    obj([
        ("name", Json::str(&s.name)),
        ("ty", Json::str(&s.ty)),
        ("var", Json::Bool(s.var)),
        ("refs", Json::strings(&s.refs)),
    ])
}

fn entity_json(facts: &Facts, f: &Fact) -> Json {
    let flow = facts
        .flows
        .get(&f.key)
        .map(|steps| steps.iter().map(|n| n.to_json()).collect())
        .unwrap_or_default();
    obj([
        ("key", Json::str(&f.key)),
        ("file", Json::str(&f.file)),
        ("kind", Json::str(&f.kind)),
        ("name", Json::str(&f.name)),
        ("line", Json::from(f.line)),
        ("effects", Json::strings(&f.effects)),
        ("error", Json::str(&f.error)),
        ("scopes", Json::from(f.scopes)),
        ("calls", Json::strings(&f.calls)),
        ("external", Json::strings(&f.external)),
        ("slots", Json::Arr(f.slots.iter().map(slot_json).collect())),
        ("result", f.result.as_ref().map_or(Json::Null, slot_json)),
        ("flow", Json::Arr(flow)),
    ])
}

/// The whole program as one interactive page. The data is escaped for embedding
/// in a script element, so no program text can close it.
pub fn html_page(facts: &Facts) -> String {
    let modules = facts
        .imports
        .iter()
        .map(|(file, imports)| {
            obj([
                ("file", Json::str(file)),
                ("imports", Json::strings(imports)),
            ])
        })
        .collect();
    let data = obj([
        ("modules", Json::Arr(modules)),
        (
            "entities",
            Json::Arr(
                facts
                    .entities
                    .values()
                    .map(|f| entity_json(facts, f))
                    .collect(),
            ),
        ),
    ]);
    PAGE.replacen("__DATA__", &data.compact(Escape::HtmlSafe), 1)
}

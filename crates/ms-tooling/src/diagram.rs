//! The plain-text call graph.

use crate::collect::InspectionRows;
use std::collections::{BTreeMap, HashMap};
use std::fmt::Write;

/// Renders the static call graph as a plain-text outline: owners in the
/// inspection's (ID) order, each followed by its distinct callees with a count.
/// The text depends only on the inspection, so equal programs print equal bytes.
pub fn diagram_ascii(inspection: &InspectionRows) -> String {
    let labels: HashMap<&str, String> = inspection
        .entities
        .iter()
        .map(|e| (e.id.as_str(), format!("{}::{}", e.file, e.name)))
        .collect();
    let label = |id: &str| labels.get(id).cloned().unwrap_or_else(|| id.to_string());
    // Edges per owner, ordered by (target label, kind) as the output requires.
    let mut edges: HashMap<&str, BTreeMap<(String, &str), usize>> = HashMap::new();
    for call in &inspection.calls {
        *edges
            .entry(call.owner.as_str())
            .or_default()
            .entry((label(&call.target), call.kind.as_str()))
            .or_default() += 1;
    }
    let mut out = String::from("CALL GRAPH\n");
    for entity in &inspection.entities {
        let _ = writeln!(out, "{} [{}]", label(&entity.id), entity.kind);
        for ((target, kind), n) in edges.get(entity.id.as_str()).into_iter().flatten() {
            let count = if *n > 1 {
                format!(" x{n}")
            } else {
                String::new()
            };
            let _ = writeln!(out, "  -> {target} ({kind}){count}");
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::collect::{CallRow, EntityRow};

    #[test]
    fn outline_is_ordered_and_counted() {
        let entity = |id: &str, name: &str| EntityRow {
            id: id.into(),
            kind: "fn".into(),
            name: name.into(),
            file: "d.ms".into(),
            ..EntityRow::default()
        };
        let call = |id: &str| CallRow {
            id: id.into(),
            owner: "d.ms#fn#two".into(),
            target: "d.ms#fn#one".into(),
            kind: "function".into(),
        };
        let inspection = InspectionRows {
            entities: vec![entity("d.ms#fn#one", "one"), entity("d.ms#fn#two", "two")],
            calls: vec![call("a"), call("b")],
        };
        assert_eq!(
            diagram_ascii(&inspection),
            "CALL GRAPH\nd.ms::one [fn]\nd.ms::two [fn]\n  -> d.ms::one (function) x2\n"
        );
    }
}

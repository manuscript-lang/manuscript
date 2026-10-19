//! Annotates views with what a diff changed, and explains one finding.

use crate::diff::atoi;
use crate::facts::Facts;
use crate::report::REPORT_FORMAT;
use crate::review::{Finding, TIER_INTERNAL};
use crate::tree::Node;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt::Write;

/// Entity nodes and calls to changed entities carry the finding's tier and
/// number, and flow steps on changed lines carry "changed". The marks are
/// fixed templates.
pub fn mark_changes(tree: &mut Node, findings: &[Finding], touched: &BTreeMap<String, Vec<i64>>) {
    let mut by_key: HashMap<&str, String> = HashMap::new();
    let mut rank = 0;
    for f in findings {
        if f.tier != TIER_INTERNAL {
            rank += 1;
            by_key.insert(&f.id, format!("  <- {} #{rank}", f.tier));
        } else {
            by_key.insert(&f.id, "  <- INTERNAL".to_string());
        }
    }
    let lines: BTreeMap<&str, BTreeSet<i64>> = touched
        .iter()
        .map(|(file, list)| (file.as_str(), list.iter().copied().collect()))
        .collect();
    walk(tree, &by_key, &lines);
}

fn walk(n: &mut Node, by_key: &HashMap<&str, String>, lines: &BTreeMap<&str, BTreeSet<i64>>) {
    if let Some(mark) = by_key
        .get(n.reference.as_str())
        .filter(|_| !n.reference.is_empty())
    {
        n.label.push_str(mark);
    } else if n.line > 0
        && lines
            .get(n.file.as_str())
            .is_some_and(|set| set.contains(&(n.line as i64)))
    {
        n.label.push_str("  <- changed");
    }
    for child in &mut n.children {
        walk(child, by_key, lines);
    }
}

/// Renders one finding's full score derivation, evidence, and callers.
/// `selector` is the display number from LOOK HERE FIRST or a stable finding id.
pub fn explain(findings: &[Finding], head: &Facts, selector: &str) -> Result<String, String> {
    let attention: Vec<&Finding> = findings
        .iter()
        .filter(|f| f.tier != TIER_INTERNAL)
        .collect();
    let found: &Finding;
    let mut number = 0;
    if let Some(n) = atoi(selector) {
        if n < 1 || n > attention.len() as i64 {
            return Err(format!(
                "no finding {n}; LOOK HERE FIRST numbers run 1 to {}",
                attention.len()
            ));
        }
        found = attention[(n - 1) as usize];
        number = n;
    } else {
        found = findings
            .iter()
            .find(|f| f.id == selector || f.entity == selector)
            .ok_or_else(|| {
                format!(
                    "no finding {selector:?}; pass a number from LOOK HERE FIRST or a finding id"
                )
            })?;
        for (i, f) in attention.iter().enumerate() {
            if f.id == found.id {
                number = i as i64 + 1;
            }
        }
    }
    let mut b = String::new();
    let title = if number > 0 {
        format!("EXPLAIN #{number} {}", found.entity)
    } else {
        format!("EXPLAIN {}", found.entity)
    };
    let _ = write!(b, "{title}\nreport format {REPORT_FORMAT}\n\n");
    let _ = write!(
        b,
        "id       {}\ntier     {}\nwhere    {}\nreach    {}\nscore    {}\n",
        found.id, found.tier, found.location, found.reach, found.score
    );
    b.push_str("\nWHY\n");
    for c in &found.changes {
        let _ = writeln!(b, "  change   {c}");
    }
    for t in &found.terms {
        let _ = writeln!(b, "  term     {t}");
    }
    b.push_str("\nEVIDENCE\n");
    if found.evidence.is_empty() {
        b.push_str("  none\n");
    }
    for e in &found.evidence {
        let _ = writeln!(b, "  {e}");
    }
    b.push_str("\nCALLERS\n");
    let mut callers: Vec<String> = Vec::new();
    for fact in head.entities.values() {
        for callee in &fact.calls {
            if *callee == found.id {
                callers.push(format!("{}  {}:{}", fact.name, fact.file, fact.line));
            }
        }
    }
    callers.sort();
    if callers.is_empty() {
        b.push_str("  none\n");
    }
    for c in &callers {
        let _ = writeln!(b, "  {c}");
    }
    let _ = write!(
        b,
        "\nNEXT\n  ms diagram <project> --view flow --entity {} --diff <diff>\n",
        found.entity
    );
    Ok(b)
}

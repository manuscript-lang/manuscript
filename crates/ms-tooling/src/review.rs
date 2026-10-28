//! Classifies what changed between a base and a head program and ranks it.

mod reach;

use crate::facts::{Fact, Facts};
use crate::json::Json;
use crate::views::{effect_list, or_none};
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};

pub const TIER_CONTRACT: &str = "CONTRACT";
pub const TIER_EFFECT: &str = "EFFECT+";
pub const TIER_ERROR: &str = "ERROR";
pub const TIER_RESOURCE: &str = "RESOURCE";
pub const TIER_INTERNAL: &str = "INTERNAL";

/// Tiers, highest attention first. The weights are the whole ranking policy.
pub fn tier_rank(tier: &str) -> usize {
    [
        TIER_CONTRACT,
        TIER_EFFECT,
        TIER_ERROR,
        TIER_RESOURCE,
        TIER_INTERNAL,
    ]
    .iter()
    .position(|t| *t == tier)
    .unwrap_or(0)
}

/// One changed entity with every reason it needs attention.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Finding {
    pub id: String,
    pub tier: String,
    pub entity: String,
    pub location: String,
    pub changes: Vec<String>,
    pub reach: usize,
    pub score: i64,
    pub terms: Vec<String>,
    pub evidence: Vec<String>,
}

impl Finding {
    pub fn to_json(&self) -> Json {
        let mut fields = vec![
            ("id".to_string(), Json::str(&self.id)),
            ("tier".to_string(), Json::str(&self.tier)),
            ("entity".to_string(), Json::str(&self.entity)),
            ("where".to_string(), Json::str(&self.location)),
            ("changes".to_string(), Json::strings_or_null(&self.changes)),
            ("reach".to_string(), Json::int(self.reach as i64)),
            ("score".to_string(), Json::int(self.score)),
            ("terms".to_string(), Json::strings_or_null(&self.terms)),
        ];
        if !self.evidence.is_empty() {
            fields.push(("evidence".to_string(), Json::strings(&self.evidence)));
        }
        Json::Obj(fields)
    }
}

/// The changed-file information a diff review needs.
#[derive(Clone, Debug, Default)]
pub struct DiffInput {
    /// Files in the diff.
    pub files: usize,
    /// `.ms` files inside the project.
    pub sources: usize,
    /// Project-relative files that did not exist before.
    pub added: BTreeSet<String>,
    pub touched: BTreeMap<String, Vec<i64>>,
    pub insertions: usize,
    pub deletions: usize,
    pub base_checked: bool,
}

/// Classifies what changed between base and head. Both are produced by the
/// same checker; `input.touched` maps a file to its changed head lines.
pub fn compare_facts(base: &Facts, head: &Facts, input: &DiffInput) -> Vec<Finding> {
    let mut callers: HashMap<&str, Vec<&str>> = HashMap::new();
    for (key, fact) in &head.entities {
        for callee in &fact.calls {
            callers.entry(callee).or_default().push(key);
        }
    }
    let keys: BTreeSet<&String> = head.entities.keys().chain(base.entities.keys()).collect();
    let touched = touched_keys(head, &input.touched);
    let mut findings = Vec::new();
    let mut scored_keys = Vec::new();
    for key in keys {
        let h = head.entities.get(key);
        let mut b = base.entities.get(key);
        if b.is_some_and(|b| input.added.contains(&b.file)) {
            b = None;
        }
        let (mut f, scored) = classify(key, h, b, input.base_checked, head);
        if scored && callers.contains_key(key.as_str()) {
            scored_keys.push(key.as_str());
        } else if scored && h.is_some_and(|h| h.exported) {
            // A target without incoming edges has exact reach zero. Finish its
            // score here instead of allocating a deferred count entry.
            f.terms.push("exported +3".to_string());
            f.score += 3;
        }
        if f.changes.is_empty() && touched.contains(key) {
            f.changes = vec!["body changed".to_string()];
        }
        if f.changes.is_empty() {
            continue;
        }
        findings.push(f);
    }
    let reaches = reach::counts(&scored_keys, &callers, head);
    for f in &mut findings {
        let Some(&r) = reaches.get(f.id.as_str()) else {
            continue;
        };
        f.reach = r;
        if r > 0 {
            let weight = 2 * (usize::BITS - r.leading_zeros()) as i64;
            f.terms.push(format!("reach({r}) +{weight}"));
            f.score += weight;
        }
        if head.entities[&f.id].exported {
            f.terms.push("exported +3".to_string());
            f.score += 3;
        }
    }
    findings.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then_with(|| tier_rank(&a.tier).cmp(&tier_rank(&b.tier)))
            .then_with(|| a.id.cmp(&b.id))
    });
    findings
}

struct Scorer {
    finding: Finding,
    by_tier: HashMap<&'static str, i64>,
}

impl Scorer {
    fn add(&mut self, tier: &'static str, change: String, term: &str, weight: i64) {
        self.finding.changes.push(change);
        self.finding.terms.push(format!("{term} +{weight}"));
        *self.by_tier.entry(tier).or_default() += weight;
        self.finding.score += weight;
    }

    fn tier(&self) -> &'static str {
        let mut best = TIER_INTERNAL;
        for (tier, weight) in &self.by_tier {
            if *weight > 1 && tier_rank(tier) < tier_rank(best) {
                best = tier;
            }
        }
        best
    }
}

fn classify(
    key: &str,
    h: Option<&Fact>,
    b: Option<&Fact>,
    base_checked: bool,
    head: &Facts,
) -> (Finding, bool) {
    let subject = h.or(b).expect("a key comes from base or head");
    let mut s = Scorer {
        finding: Finding {
            id: key.to_string(),
            entity: subject.name.clone(),
            location: format!("{}:{}", subject.file, subject.line),
            ..Finding::default()
        },
        by_tier: HashMap::new(),
    };
    match (h, b) {
        (Some(h), None) if base_checked => {
            s.add(TIER_INTERNAL, "added".into(), "added", 1);
            if h.exported {
                s.add(
                    TIER_CONTRACT,
                    format!("added exported {}", h.kind),
                    "contract",
                    8,
                );
            }
        }
        (None, Some(b)) => {
            s.add(TIER_INTERNAL, "removed".into(), "removed", 1);
            if b.exported {
                s.add(
                    TIER_CONTRACT,
                    format!("removed exported {}", b.kind),
                    "contract",
                    8,
                );
            }
        }
        (Some(h), Some(b)) => compare(h, b, &mut s),
        _ => {}
    }
    let Some(h) = h else {
        s.finding.tier = s.tier().to_string();
        return (s.finding, false);
    };
    if let Some(b) = b {
        let gained = gained_effects(h, Some(b));
        if !gained.is_empty() {
            s.finding.evidence.push(effect_path(h, &gained, head));
        }
    }
    let scored = !s.finding.changes.is_empty() && s.finding.score > 1;
    s.finding.tier = s.tier().to_string();
    (s.finding, scored)
}

fn compare(h: &Fact, b: &Fact, s: &mut Scorer) {
    if h.exported != b.exported {
        s.add(
            TIER_CONTRACT,
            format!(
                "visibility: {} -> {}",
                visibility(b.exported),
                visibility(h.exported)
            ),
            "contract",
            8,
        );
    }
    if h.ty != b.ty {
        if h.exported {
            s.add(
                TIER_CONTRACT,
                format!("type: {} -> {}", b.ty, h.ty),
                "contract",
                8,
            );
        } else {
            s.add(
                TIER_INTERNAL,
                format!("private type: {} -> {}", b.ty, h.ty),
                "signature",
                1,
            );
        }
    }
    if !gained_effects(h, Some(b)).is_empty() {
        let change = format!(
            "effects: {} -> {}",
            effect_list(&b.effects),
            effect_list(&h.effects)
        );
        s.add(TIER_EFFECT, change, "effect_gain", 6);
    } else if effect_list(&h.effects) != effect_list(&b.effects) {
        let change = format!(
            "effects: {} -> {}",
            effect_list(&b.effects),
            effect_list(&h.effects)
        );
        s.add(TIER_INTERNAL, change, "effect_loss", 1);
    }
    if h.error != b.error {
        s.add(
            TIER_ERROR,
            format!("error type: {} -> {}", or_none(&b.error), or_none(&h.error)),
            "error_flow",
            5,
        );
    }
    if h.tries != b.tries {
        s.add(
            TIER_ERROR,
            format!("try sites: {} -> {}", b.tries, h.tries),
            "error_flow",
            5,
        );
    }
    if h.withs != b.withs {
        s.add(
            TIER_RESOURCE,
            format!("with scopes: {} -> {}", b.withs, h.withs),
            "resource",
            4,
        );
    }
}

fn visibility(exported: bool) -> &'static str {
    if exported { "exported" } else { "private" }
}

fn gained_effects(h: &Fact, b: Option<&Fact>) -> Vec<String> {
    h.effects
        .iter()
        .filter(|e| !b.is_some_and(|b| b.effects.contains(e)))
        .cloned()
        .collect()
}

/// Follows callees that carry a gained effect down to the native operation or
/// boundary where it enters, choosing the first name at each step.
fn effect_path(start: &Fact, gained: &[String], head: &Facts) -> String {
    let mut path = vec![start.name.clone()];
    let mut seen = BTreeSet::from([start.key.clone()]);
    let mut current = start;
    loop {
        let next = current.calls.iter().find_map(|key| {
            let callee = head.entities.get(key)?;
            (!seen.contains(key) && has_any(&callee.effects, gained)).then_some(callee)
        });
        let Some(next) = next else { break };
        seen.insert(next.key.clone());
        path.push(next.name.clone());
        current = next;
    }
    if let Some(external) = current.external.first() {
        path.push(external.clone());
    }
    format!("path: {}", path.join(" -> "))
}

fn has_any(have: &[String], want: &[String]) -> bool {
    want.iter().any(|w| have.contains(w))
}

/// The number of distinct project entities that transitively call this entity.
/// Only scored changes need a traversal; unchanged and body-only entities do not.
fn reach_count(key: &str, callers: &HashMap<&str, Vec<&str>>) -> usize {
    let mut seen: BTreeSet<&str> = BTreeSet::from([key]);
    let mut queue = VecDeque::from([key]);
    while let Some(next) = queue.pop_front() {
        for caller in callers.get(next).into_iter().flatten() {
            if seen.insert(caller) {
                queue.push_back(caller);
            }
        }
    }
    seen.len() - 1
}

/// Maps changed head lines to the most specific entity containing them.
pub fn touched_keys(head: &Facts, touched: &BTreeMap<String, Vec<i64>>) -> BTreeSet<String> {
    let mut by_file: HashMap<&str, Vec<&Fact>> = HashMap::new();
    for fact in head.entities.values().filter(|f| f.first > 0) {
        by_file.entry(&fact.file).or_default().push(fact);
    }
    let mut result = BTreeSet::new();
    for (file, lines) in touched {
        let facts = by_file.get(file.as_str()).map(Vec::as_slice).unwrap_or(&[]);
        for &line in lines {
            let best = facts
                .iter()
                .filter(|f| line >= f.first as i64 && line <= f.last as i64)
                .min_by(|a, b| {
                    (a.last as i64 - a.first as i64)
                        .cmp(&(b.last as i64 - b.first as i64))
                        .then_with(|| a.key.cmp(&b.key))
                });
            if let Some(best) = best {
                result.insert(best.key.clone());
            }
        }
    }
    result
}

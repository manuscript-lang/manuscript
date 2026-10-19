//! JSON and markdown reports for a corpus run.

use crate::fixture::Phase;
use crate::json::Json;
use crate::runner::{Case, Outcome};
use std::collections::BTreeMap;
use std::fmt::Write as _;

#[derive(Debug, Default, Clone, Copy)]
pub struct Tally {
    pub total: usize,
    pub pass: usize,
    pub fail: usize,
    pub expected_fail: usize,
    pub unexpected_pass: usize,
    pub unrecorded: usize,
}

impl Tally {
    fn add(&mut self, outcome: &Outcome) {
        self.total += 1;
        match outcome {
            Outcome::Pass => self.pass += 1,
            Outcome::Fail => self.fail += 1,
            Outcome::ExpectedFail => self.expected_fail += 1,
            Outcome::UnexpectedPass => self.unexpected_pass += 1,
            Outcome::Unrecorded => self.unrecorded += 1,
        }
    }

    /// Fixtures that matched the oracle, counting allowlisted ones that now pass.
    pub fn passing(&self) -> usize {
        self.pass + self.unexpected_pass
    }

    pub fn rate(&self) -> f64 {
        if self.total == 0 {
            100.0
        } else {
            100.0 * self.passing() as f64 / self.total as f64
        }
    }

    fn to_json(self) -> Json {
        let mut o = Json::obj();
        o.set("total", Json::int(self.total as i64));
        o.set("pass", Json::int(self.passing() as i64));
        o.set("fail", Json::int(self.fail as i64));
        o.set("expected_fail", Json::int(self.expected_fail as i64));
        o.set("unexpected_pass", Json::int(self.unexpected_pass as i64));
        o.set("unrecorded", Json::int(self.unrecorded as i64));
        o.set("pass_rate", Json::Num(format!("{:.2}", self.rate())));
        o
    }
}

pub struct Summary {
    pub all: Tally,
    pub by_phase: BTreeMap<Phase, Tally>,
    pub by_tag: BTreeMap<String, Tally>,
}

pub fn summarize(cases: &[Case]) -> Summary {
    let mut s = Summary {
        all: Tally::default(),
        by_phase: BTreeMap::new(),
        by_tag: BTreeMap::new(),
    };
    for c in cases {
        s.all.add(&c.outcome);
        s.by_phase.entry(c.phase).or_default().add(&c.outcome);
        for t in &c.tags {
            s.by_tag.entry(t.clone()).or_default().add(&c.outcome);
        }
    }
    s
}

/// True when the run should exit non-zero: a failure that is not allowlisted.
pub fn has_regressions(cases: &[Case]) -> bool {
    cases
        .iter()
        .any(|c| matches!(c.outcome, Outcome::Fail | Outcome::Unrecorded))
}

pub fn to_json(ms: &str, cases: &[Case]) -> Json {
    let s = summarize(cases);
    let mut o = Json::obj();
    o.set("ms", Json::str(ms));
    o.set("summary", s.all.to_json());
    let mut phases = Json::obj();
    for (p, t) in &s.by_phase {
        phases.set(p.name(), t.to_json());
    }
    o.set("by_phase", phases);
    let mut tags = Json::obj();
    for (t, tally) in &s.by_tag {
        tags.set(t, tally.to_json());
    }
    o.set("by_tag", tags);
    let failures = cases
        .iter()
        .filter(|c| c.outcome != Outcome::Pass && c.outcome != Outcome::UnexpectedPass)
        .map(|c| {
            let mut f = Json::obj();
            f.set("id", Json::str(c.id.clone()));
            f.set("phase", Json::str(c.phase.name()));
            f.set("outcome", Json::str(format!("{:?}", c.outcome)));
            f.set(
                "tags",
                Json::Arr(c.tags.iter().cloned().map(Json::Str).collect()),
            );
            f.set("diff", Json::str(c.diff.clone()));
            f
        })
        .collect();
    o.set("failures", Json::Arr(failures));
    o.set(
        "unexpected_passes",
        Json::Arr(
            cases
                .iter()
                .filter(|c| c.outcome == Outcome::UnexpectedPass)
                .map(|c| Json::str(c.id.clone()))
                .collect(),
        ),
    );
    o
}

fn row(out: &mut String, name: &str, t: &Tally) {
    let _ = writeln!(
        out,
        "| {name} | {} | {} | {} | {} | {} | {:.1}% |",
        t.total,
        t.passing(),
        t.fail,
        t.expected_fail,
        t.unrecorded,
        t.rate()
    );
}

const HEADER: &str = "| | total | pass | fail | expected fail | unrecorded | rate |\n|---|---:|---:|---:|---:|---:|---:|\n";

/// Markdown report; at most `max_failures` failing fixtures get a diff excerpt.
pub fn to_markdown(ms: &str, cases: &[Case], max_failures: usize) -> String {
    let s = summarize(cases);
    let mut out = String::new();
    let _ = writeln!(out, "# Conformance report\n\nBinary: `{ms}`\n");
    let _ = writeln!(out, "## Overall\n\n{HEADER}");
    row(&mut out, "all", &s.all);
    let _ = writeln!(out, "\n## By phase\n\n{HEADER}");
    for (p, t) in &s.by_phase {
        row(&mut out, p.name(), t);
    }
    let _ = writeln!(out, "\n## By tag\n\n{HEADER}");
    for (tag, t) in &s.by_tag {
        row(&mut out, tag, t);
    }
    let failing: Vec<&Case> = cases
        .iter()
        .filter(|c| matches!(c.outcome, Outcome::Fail | Outcome::Unrecorded))
        .collect();
    let _ = writeln!(out, "\n## Failing fixtures ({})\n", failing.len());
    for c in failing.iter().take(max_failures) {
        let _ = writeln!(
            out,
            "### `{}` ({}, {})\n\n```diff\n{}```\n",
            c.id,
            c.phase.name(),
            c.tags.join(", "),
            c.diff
        );
    }
    if failing.len() > max_failures {
        let _ = writeln!(out, "... {} more not shown\n", failing.len() - max_failures);
    }
    let unexpected: Vec<&Case> = cases
        .iter()
        .filter(|c| c.outcome == Outcome::UnexpectedPass)
        .collect();
    if !unexpected.is_empty() {
        let _ = writeln!(out, "## Unexpected passes ({})\n", unexpected.len());
        let _ = writeln!(out, "Remove these from the expect-fail file:\n");
        for c in unexpected {
            let _ = writeln!(out, "- `{}`", c.id);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn case(id: &str, tag: &str, phase: Phase, outcome: Outcome) -> Case {
        Case {
            id: id.into(),
            tags: vec![tag.into()],
            phase,
            outcome,
            millis: 1,
            diff: "- a\n+ b\n".into(),
        }
    }

    #[test]
    fn tallies_by_tag_and_phase() {
        let cases = vec![
            case("a", "lists", Phase::Run, Outcome::Pass),
            case("b", "lists", Phase::Run, Outcome::Fail),
            case("c", "maps", Phase::Check, Outcome::ExpectedFail),
            case("d", "maps", Phase::Check, Outcome::UnexpectedPass),
        ];
        let s = summarize(&cases);
        assert_eq!(s.all.total, 4);
        assert_eq!(s.by_tag["lists"].passing(), 1);
        assert_eq!(s.by_phase[&Phase::Check].passing(), 1);
        assert!(has_regressions(&cases));
        assert!(!has_regressions(&cases[2..]));
    }

    #[test]
    fn markdown_lists_failures() {
        let cases = vec![case("go/x", "lists", Phase::Run, Outcome::Fail)];
        let md = to_markdown("./ms", &cases, 10);
        assert!(md.contains("### `go/x`"));
        assert!(md.contains("```diff\n- a\n+ b\n```"));
        let j = to_json("./ms", &cases);
        assert_eq!(
            j.get("failures").and_then(Json::as_array).map(<[_]>::len),
            Some(1)
        );
    }
}

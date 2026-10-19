//! The review report: fixed templates filled with checker facts; nothing is
//! written by a model.

use crate::facts::Facts;
use crate::json::Json;
use crate::review::{
    DiffInput, Finding, TIER_CONTRACT, TIER_EFFECT, TIER_ERROR, TIER_INTERNAL, TIER_RESOURCE,
    compare_facts,
};
use crate::sha256;
use crate::views::effect_list;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write;

/// The version of the report template set. Any wording change bumps it, so
/// two reports with the same format are comparable.
pub const REPORT_FORMAT: i64 = 1;

const ROW_CAP: usize = 5;

/// One numbered report section: a table, plain lines, or both.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Section {
    pub title: String,
    pub headers: Vec<String>,
    pub rows: Vec<Vec<String>>,
    pub lines: Vec<String>,
    pub more: usize,
}

impl Section {
    fn to_json(&self) -> Json {
        let mut fields = vec![("title".to_string(), Json::str(&self.title))];
        if !self.headers.is_empty() {
            fields.push(("headers".to_string(), Json::strings(&self.headers)));
        }
        if !self.rows.is_empty() {
            fields.push((
                "rows".to_string(),
                Json::Arr(self.rows.iter().map(|r| Json::strings(r)).collect()),
            ));
        }
        if !self.lines.is_empty() {
            fields.push(("lines".to_string(), Json::strings(&self.lines)));
        }
        if self.more > 0 {
            fields.push(("more".to_string(), Json::int(self.more as i64)));
        }
        Json::Obj(fields)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Report {
    pub format: i64,
    pub mode: String,
    pub input: String,
    pub result: String,
    pub sections: Vec<Section>,
    pub findings: Vec<Finding>,
    pub digest: String,
}

/// Selects how much of each section is shown.
#[derive(Clone, Copy, Debug, Default)]
pub struct ReviewOptions {
    pub all: bool,
}

fn capped(rows: Vec<Vec<String>>, options: ReviewOptions) -> (Vec<Vec<String>>, usize) {
    if options.all || rows.len() <= ROW_CAP {
        return (rows, 0);
    }
    let more = rows.len() - ROW_CAP;
    (rows.into_iter().take(ROW_CAP).collect(), more)
}

fn cap_lines(lines: Vec<String>, options: ReviewOptions) -> (Vec<String>, usize) {
    if options.all || lines.len() <= ROW_CAP {
        return (lines, 0);
    }
    let more = lines.len() - ROW_CAP;
    (lines.into_iter().take(ROW_CAP).collect(), more)
}

fn strings(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
}

/// Builds the report for a change: head facts, base facts, and input.
pub fn diff_report(
    base: &Facts,
    head: &Facts,
    input: &DiffInput,
    options: ReviewOptions,
) -> Report {
    let findings = compare_facts(base, head, input);
    let mut counts: BTreeMap<&str, usize> = BTreeMap::new();
    let mut attention = 0;
    for f in &findings {
        *counts.entry(f.tier.as_str()).or_default() += 1;
        if f.tier != TIER_INTERNAL {
            attention += 1;
        }
    }
    let count = |tier: &str| counts.get(tier).copied().unwrap_or(0);
    let internal = count(TIER_INTERNAL);
    let mut r = Report {
        format: REPORT_FORMAT,
        mode: "diff".into(),
        ..Report::default()
    };
    r.input = format!(
        "diff ({} files, {} source, +{} -{})",
        input.files, input.sources, input.insertions, input.deletions
    );
    r.result = if !input.base_checked {
        "base did not check; semantic comparison unavailable".to_string()
    } else if findings.is_empty() {
        "no semantic change".to_string()
    } else {
        format!("{attention} need attention, {internal} internal")
    };
    let summary = Section {
        title: "SUMMARY".into(),
        lines: vec![
            format!("changed entities      {}", findings.len()),
            format!("contract              {}", count(TIER_CONTRACT)),
            format!("effect                {}", count(TIER_EFFECT)),
            format!("error flow            {}", count(TIER_ERROR)),
            format!("resource              {}", count(TIER_RESOURCE)),
            format!("internal only         {internal}"),
        ],
        ..Section::default()
    };
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut evidence: Vec<Vec<String>> = Vec::new();
    for f in findings.iter().filter(|f| f.tier != TIER_INTERNAL) {
        rows.push(vec![
            (rows.len() + 1).to_string(),
            f.tier.clone(),
            f.entity.clone(),
            f.changes.join("; "),
            f.reach.to_string(),
            f.location.clone(),
            f.score.to_string(),
        ]);
        let mut detail = f.evidence.clone();
        detail.push(format!("score: {}", f.terms.join(", ")));
        evidence.push(vec![rows.len().to_string(), detail.join(" | ")]);
    }
    let (shown, more) = capped(rows, options);
    let look = Section {
        title: "LOOK HERE FIRST".into(),
        headers: strings(&["#", "TIER", "ENTITY", "CHANGE", "REACH", "WHERE", "SCORE"]),
        rows: shown,
        more,
        ..Section::default()
    };
    let (shown_evidence, _) = capped(evidence, options);
    let ev = Section {
        title: "EVIDENCE".into(),
        headers: strings(&["#", "DETAIL"]),
        rows: shown_evidence,
        ..Section::default()
    };
    r.sections = vec![
        summary,
        look,
        ev,
        tier_section("EFFECTS", TIER_EFFECT, &findings, options),
        tier_section("ERROR FLOW", TIER_ERROR, &findings, options),
        tier_section("RESOURCES", TIER_RESOURCE, &findings, options),
        import_section(base, head),
        internal_section(&findings, options),
    ];
    r.findings = findings;
    r.digest = r.compute_digest();
    r
}

/// Lists entities whose reasons include the tier, including those ranked into
/// other tiers, so a section answers its question completely.
fn tier_section(title: &str, tier: &str, findings: &[Finding], options: ReviewOptions) -> Section {
    let prefixes: &[&str] = match tier {
        TIER_EFFECT => &["effects:"],
        TIER_ERROR => &["error type:", "try sites:"],
        TIER_RESOURCE => &["with scopes:"],
        _ => &[],
    };
    let mut lines = Vec::new();
    for f in findings {
        for change in &f.changes {
            for p in prefixes {
                if change.starts_with(p) {
                    lines.push(format!("{} {change}", f.entity));
                }
            }
        }
    }
    let (shown, more) = cap_lines(lines, options);
    Section {
        title: title.into(),
        lines: shown,
        more,
        ..Section::default()
    }
}

fn import_section(base: &Facts, head: &Facts) -> Section {
    let names: BTreeSet<&String> = base.imports.keys().chain(head.imports.keys()).collect();
    let mut lines = Vec::new();
    let none = Vec::new();
    for file in names {
        let old: BTreeSet<&String> = base.imports.get(file).unwrap_or(&none).iter().collect();
        let now: BTreeSet<&String> = head.imports.get(file).unwrap_or(&none).iter().collect();
        for path in now.difference(&old) {
            lines.push(format!("+ {file} imports {path}"));
        }
        for path in old.difference(&now) {
            lines.push(format!("- {file} imports {path}"));
        }
    }
    Section {
        title: "DEPENDENCIES".into(),
        lines,
        ..Section::default()
    }
}

fn internal_section(findings: &[Finding], options: ReviewOptions) -> Section {
    let mut lines: Vec<String> = findings
        .iter()
        .filter(|f| f.tier == TIER_INTERNAL)
        .map(|f| format!("{} ({})", f.entity, f.changes.join("; ")))
        .collect();
    lines.sort();
    let (shown, more) = cap_lines(lines, options);
    Section {
        title: "INTERNAL".into(),
        lines: shown,
        more,
        ..Section::default()
    }
}

/// Describes the head alone: the same template without a diff.
pub fn project_report(head: &Facts, options: ReviewOptions) -> Report {
    let mut r = Report {
        format: REPORT_FORMAT,
        mode: "project".into(),
        input: "project (no diff)".into(),
        ..Report::default()
    };
    let (mut exported, mut tests, mut withs) = (0, 0, 0);
    for f in head.entities.values() {
        exported += usize::from(f.exported);
        tests += usize::from(f.kind == "test");
        withs += usize::from(f.withs > 0);
    }
    let files: BTreeSet<&String> = head.entities.values().map(|f| &f.file).collect();
    r.result = format!("{} modules, {} entities", files.len(), head.entities.len());
    let summary = Section {
        title: "SUMMARY".into(),
        lines: vec![
            format!("modules               {}", files.len()),
            format!("entities              {}", head.entities.len()),
            format!("exported              {exported}"),
            format!("tests                 {tests}"),
            format!("with scopes           {withs}"),
        ],
        ..Section::default()
    };
    let (mut surface, mut entries, mut resources) = (Vec::new(), Vec::new(), Vec::new());
    let mut error_types: BTreeMap<&str, usize> = BTreeMap::new();
    for f in head.entities.values() {
        let at = format!("{}:{}", f.file, f.line);
        if f.exported {
            surface.push(vec![
                f.name.clone(),
                f.kind.clone(),
                f.ty.clone(),
                at.clone(),
            ]);
        }
        if (f.name == "main" && f.exported) || f.kind == "test" {
            entries.push(vec![
                f.name.clone(),
                f.kind.clone(),
                effect_list(&f.effects),
                at.clone(),
            ]);
        }
        if f.withs > 0 {
            resources.push(vec![f.name.clone(), f.withs.to_string(), at]);
        }
        if !f.error.is_empty() {
            *error_types.entry(&f.error).or_default() += 1;
        }
    }
    let error_rows: Vec<Vec<String>> = error_types
        .iter()
        .map(|(e, n)| vec![(*e).to_string(), n.to_string()])
        .collect();
    let section = |title: &str, headers: &[&str], rows: Vec<Vec<String>>| {
        let (shown, more) = capped(rows, options);
        Section {
            title: title.into(),
            headers: strings(headers),
            rows: shown,
            more,
            ..Section::default()
        }
    };
    r.sections = vec![
        summary,
        section(
            "PUBLIC SURFACE",
            &["ENTITY", "KIND", "TYPE", "WHERE"],
            surface,
        ),
        section(
            "ENTRY POINTS",
            &["ENTITY", "KIND", "EFFECTS", "WHERE"],
            entries,
        ),
        section("ERROR TYPES", &["TYPE", "FUNCTIONS"], error_rows),
        section("RESOURCES", &["ENTITY", "WITH", "WHERE"], resources),
        import_map(head),
    ];
    r.digest = r.compute_digest();
    r
}

fn import_map(head: &Facts) -> Section {
    let lines = head
        .imports
        .iter()
        .map(|(file, paths)| format!("{file} imports {}", paths.join(", ")))
        .collect();
    Section {
        title: "DEPENDENCIES".into(),
        lines,
        ..Section::default()
    }
}

impl Report {
    /// Hashes the ascii body, so equal digests mean equal reports.
    fn compute_digest(&self) -> String {
        format!("sha256:{}", sha256::hex(self.body("ascii").as_bytes()))
    }

    pub fn to_json(&self) -> Json {
        let mut fields = vec![
            ("format".to_string(), Json::int(self.format)),
            ("mode".to_string(), Json::str(&self.mode)),
            ("input".to_string(), Json::str(&self.input)),
            ("result".to_string(), Json::str(&self.result)),
            (
                "sections".to_string(),
                Json::Arr(self.sections.iter().map(Section::to_json).collect()),
            ),
        ];
        if !self.findings.is_empty() {
            fields.push((
                "findings".to_string(),
                Json::Arr(self.findings.iter().map(Finding::to_json).collect()),
            ));
        }
        fields.push(("digest".to_string(), Json::str(&self.digest)));
        Json::Obj(fields)
    }

    /// Writes the report as ascii, markdown, or json.
    pub fn render(&self, format: &str) -> String {
        if format == "json" {
            return self.to_json().encode() + "\n";
        }
        format!("{}\ndigest {}\n", self.body(format), self.digest)
    }

    fn body(&self, format: &str) -> String {
        let mut b = String::new();
        let md = format == "markdown";
        if md {
            let _ = write!(
                b,
                "# Manuscript review report (format {})\n\n- input: {}\n- result: {}\n",
                self.format, self.input, self.result
            );
        } else {
            let _ = write!(
                b,
                "MANUSCRIPT REVIEW REPORT  format {}\ninput   {}\nresult  {}\n",
                self.format, self.input, self.result
            );
        }
        for (i, s) in self.sections.iter().enumerate() {
            if md {
                let _ = write!(b, "\n## {}. {}\n\n", i + 1, s.title);
            } else {
                let _ = write!(b, "\n{}. {}\n", i + 1, s.title);
            }
            write_section(&mut b, s, md);
        }
        let mut trimmed = b.trim_end_matches('\n').to_string();
        trimmed.push('\n');
        trimmed
    }
}

fn write_section(b: &mut String, s: &Section, md: bool) {
    if s.rows.is_empty() && s.lines.is_empty() {
        b.push_str(indent(md));
        b.push_str("none\n");
        return;
    }
    if !s.rows.is_empty() {
        write_table(b, s, md);
    }
    for line in &s.lines {
        let _ = writeln!(b, "{}{line}", indent(md));
    }
    if s.more > 0 {
        let _ = writeln!(b, "{}+{} more (use --all)", indent(md), s.more);
    }
}

fn indent(md: bool) -> &'static str {
    if md { "- " } else { "   " }
}

fn write_table(b: &mut String, s: &Section, md: bool) {
    if md {
        let _ = writeln!(b, "| {} |", s.headers.join(" | "));
        let _ = writeln!(b, "|{}", " --- |".repeat(s.headers.len()));
        for row in &s.rows {
            let cells: Vec<String> = row.iter().map(|c| c.replace('|', "\\|")).collect();
            let _ = writeln!(b, "| {} |", cells.join(" | "));
        }
        return;
    }
    // Go pads by byte length, so widths count bytes.
    let mut widths: Vec<usize> = s.headers.iter().map(String::len).collect();
    for row in &s.rows {
        for (i, cell) in row.iter().enumerate() {
            widths[i] = widths[i].max(cell.len());
        }
    }
    let line = |b: &mut String, cells: &[String]| {
        let parts: Vec<String> = cells
            .iter()
            .enumerate()
            .map(|(i, cell)| {
                if i + 1 == cells.len() {
                    cell.clone()
                } else {
                    format!("{cell}{}", " ".repeat(widths[i] - cell.len()))
                }
            })
            .collect();
        let _ = writeln!(b, "   {}", parts.join("  "));
    };
    line(b, &s.headers);
    for row in &s.rows {
        line(b, row);
    }
}

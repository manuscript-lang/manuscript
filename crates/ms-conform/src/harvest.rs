//! Turn the repository's existing Manuscript sources into corpus fixtures.
//!
//! Candidates come from `.ms` files and projects in the tree, from
//! ```` ```manuscript ```` fences in `documentation/`.
//! Each candidate is classified by asking the oracle to check it: parse errors
//! become `parse` fixtures, type errors `check` fixtures, clean programs with
//! `main` become `run` fixtures, clean programs with `test` blocks `test`
//! fixtures. Expectations are recorded afterwards by `record --prune`.

use crate::exec;
use crate::fixture::{Meta, Phase, render_meta};
use crate::json::{self, Json};
use crate::runner;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Debug, Clone)]
pub enum Body {
    Source(String),
    /// A project directory (has `ms.toml`).
    Project(PathBuf),
}

#[derive(Debug, Clone)]
pub struct Candidate {
    /// Where it came from, recorded in the fixture header.
    pub origin: String,
    /// Directory (`snippets`, `e2e`, ...) and slug that make the fixture id.
    pub category: String,
    pub slug: String,
    pub body: Body,
}

const SKIP_DIRS: &[&str] = &[
    ".git",
    "vendor",
    "toolchain",
    "target",
    "node_modules",
    "website",
    ".ms-cache",
    "dist",
];

/// Projects that bind sockets, wait for signals or spawn processes; they are checked, not run.
const HOSTILE_IMPORTS: &[&str] = &[
    "http",
    "net",
    "tls",
    "websocket",
    "sse",
    "fetch",
    "process",
    "terminal",
    "system",
    "random",
    "time",
];

/// Modules that read or write the host; they put a fixture in the `io` tier.
const IO_IMPORTS: &[&str] = &["fs", "path", "log", "system"];

fn slugify(text: &str) -> String {
    let mut out = String::new();
    let mut dash = true;
    for c in text.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c.to_ascii_lowercase());
            dash = false;
        } else if !dash {
            out.push('-');
            dash = true;
        }
    }
    out.trim_matches('-').chars().take(60).collect()
}

fn skip_dir(name: &str) -> bool {
    SKIP_DIRS.contains(&name) || name.starts_with('.')
}

fn walk_files(dir: &Path, out: &mut Vec<PathBuf>, projects: &mut Vec<PathBuf>) {
    if dir.join("ms.toml").exists() {
        projects.push(dir.to_path_buf());
        return;
    }
    let Ok(read) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = read.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let path = e.path();
        let name = e.file_name().to_string_lossy().into_owned();
        if path.is_dir() {
            if !skip_dir(&name) {
                walk_files(&path, out, projects);
            }
        } else if name.ends_with(".ms") {
            out.push(path);
        }
    }
}

/// Candidates found by walking the repository.
pub fn scan_tree(repo: &Path) -> Vec<Candidate> {
    let mut files = Vec::new();
    let mut projects = Vec::new();
    walk_files(repo, &mut files, &mut projects);
    let mut out = Vec::new();
    for path in files {
        let rel = path.strip_prefix(repo).unwrap_or(&path);
        let rel_text = rel.to_string_lossy().replace('\\', "/");
        if rel_text.starts_with("stdlib/") || rel_text.starts_with("tests/conformance/") {
            continue; // declaration files and the corpus itself
        }
        let Ok(source) = fs::read_to_string(&path) else {
            continue;
        };
        let (category, slug) = category_of(&rel_text);
        out.push(Candidate {
            origin: rel_text,
            category,
            slug,
            body: Body::Source(source),
        });
    }
    for dir in projects {
        let rel = dir.strip_prefix(repo).unwrap_or(&dir);
        let rel_text = rel.to_string_lossy().replace('\\', "/");
        if rel_text.starts_with("tests/conformance/") {
            continue;
        }
        let (category, slug) = category_of(&rel_text);
        out.push(Candidate {
            origin: rel_text,
            category,
            slug,
            body: Body::Project(dir),
        });
    }
    out
}

fn category_of(rel: &str) -> (String, String) {
    let rel = rel.strip_suffix(".ms").unwrap_or(rel);
    let rel = rel.strip_prefix("tests/e2e/testdata/").unwrap_or(rel);
    let parts: Vec<&str> = rel.split('/').collect();
    let category = if rel.starts_with("accept/")
        || rel.starts_with("reject/")
        || rel.starts_with("stdlib/")
        || rel.starts_with("projects/")
        || rel.starts_with("shutdown/")
    {
        format!("e2e/{}", parts[0])
    } else if parts[0] == "bench" || parts[0] == "examples" {
        parts[0].to_string()
    } else {
        "repo".to_string()
    };
    let rest = if category.starts_with("e2e/") {
        parts[1..].join("-")
    } else if category == "repo" || parts.len() == 1 {
        parts.join("-")
    } else {
        parts[1..].join("-")
    };
    (category, slugify(&rest))
}

/// Candidates from ```` ```manuscript ```` fences under `documentation/`.
pub fn scan_docs(repo: &Path) -> Vec<Candidate> {
    let mut out = Vec::new();
    let mut stack = vec![repo.join("documentation")];
    let mut files = Vec::new();
    while let Some(dir) = stack.pop() {
        let Ok(read) = fs::read_dir(&dir) else {
            continue;
        };
        for e in read.flatten() {
            let path = e.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|x| x == "md") {
                files.push(path);
            }
        }
    }
    files.sort();
    for path in files {
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        let rel = path.strip_prefix(repo).unwrap_or(&path);
        let rel_text = rel.to_string_lossy().replace('\\', "/");
        let stem = slugify(
            rel_text
                .trim_start_matches("documentation/")
                .trim_end_matches(".md"),
        );
        let mut n = 0;
        let mut current: Option<(usize, String)> = None;
        for (i, line) in text.lines().enumerate() {
            match &mut current {
                None => {
                    if line.starts_with("```manuscript") {
                        current = Some((i + 1, String::new()));
                    }
                }
                Some((start, body)) => {
                    if line.starts_with("```") {
                        n += 1;
                        out.push(Candidate {
                            origin: format!("{rel_text}:{start}"),
                            category: "docs".to_string(),
                            slug: format!("{stem}-{n}"),
                            body: Body::Source(std::mem::take(body)),
                        });
                        current = None;
                    } else {
                        body.push_str(line);
                        body.push('\n');
                    }
                }
            }
        }
    }
    out
}

/// What the oracle said about a candidate.
#[derive(Debug, Default, Clone)]
struct Verdict {
    parse_errors: bool,
    type_errors: bool,
    unusable: Option<String>,
}

fn check_candidate(ms: &Path, scratch: &Path, id: usize, cand: &Candidate) -> Verdict {
    let work = scratch.join(format!("c{id}"));
    let _ = fs::remove_dir_all(&work);
    let entry = match &cand.body {
        Body::Source(text) => {
            if fs::create_dir_all(&work).is_err() || fs::write(work.join("main.ms"), text).is_err()
            {
                return unusable("cannot write scratch file");
            }
            "main.ms".to_string()
        }
        Body::Project(dir) => {
            if let Err(e) = copy_project(dir, &work) {
                return unusable(&e.to_string());
            }
            "ms.toml".to_string()
        }
    };
    let out = exec::run(
        ms,
        &["check".into(), entry, "--json".into()],
        &work,
        b"",
        Duration::from_secs(120),
        &[],
    );
    let _ = fs::remove_dir_all(&work);
    if out.timed_out {
        return unusable("check timed out");
    }
    let Ok(report) = json::parse(out.stdout_text()) else {
        return unusable("check printed no JSON");
    };
    let mut v = Verdict::default();
    for d in report
        .get("diagnostics")
        .and_then(Json::as_array)
        .unwrap_or(&[])
    {
        match d.get("phase").and_then(Json::as_str) {
            Some("parse") => v.parse_errors = true,
            _ => v.type_errors = true,
        }
    }
    v
}

fn unusable(reason: &str) -> Verdict {
    Verdict {
        unusable: Some(reason.to_string()),
        ..Verdict::default()
    }
}

pub fn copy_project(from: &Path, to: &Path) -> std::io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if skip_dir(&name) && entry.file_type()?.is_dir() {
            continue;
        }
        if name.ends_with(".expected.json") || name == "conform.meta" {
            continue;
        }
        let target = to.join(&name);
        if entry.file_type()?.is_dir() {
            copy_project(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

fn imports_of(text: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let mut rest = text;
    while let Some(i) = rest.find("\"@std/") {
        rest = &rest[i + 6..];
        let end = rest.find(['.', '"']).unwrap_or(rest.len());
        let name = &rest[..end];
        if !name.is_empty()
            && name
                .chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        {
            out.insert(name.to_string());
        }
    }
    out
}

fn project_text(dir: &Path) -> String {
    let mut text = String::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(read) = fs::read_dir(&d) else { continue };
        for e in read.flatten() {
            let p = e.path();
            let name = e.file_name().to_string_lossy().into_owned();
            if p.is_dir() {
                if !skip_dir(&name) {
                    stack.push(p);
                }
            } else if name.ends_with(".ms") || name == "ms.toml" {
                text.push_str(&fs::read_to_string(&p).unwrap_or_default());
                text.push('\n');
            }
        }
    }
    text
}

fn has_word(text: &str, word: &str) -> bool {
    text.match_indices(word).any(|(i, _)| {
        let before = text[..i].chars().next_back();
        let after = text[i + word.len()..].chars().next();
        !before.is_some_and(|c| c.is_alphanumeric() || c == '_')
            && !after.is_some_and(|c| c.is_alphanumeric() || c == '_')
    })
}

/// The milestone tier of a program: stdout and the test harness are part of the core language
/// experience, so `io` and `testing` do not raise it.
pub fn tier_of(imports: &BTreeSet<String>) -> &'static str {
    let others: Vec<&String> = imports
        .iter()
        .filter(|m| !matches!(m.as_str(), "io" | "testing"))
        .collect();
    if others.is_empty() {
        "tier-core"
    } else if others
        .iter()
        .any(|m| IO_IMPORTS.contains(&m.as_str()) || HOSTILE_IMPORTS.contains(&m.as_str()))
    {
        "tier-io"
    } else {
        "tier-stdlib"
    }
}

/// Recompute `tier-*` tags on every fixture under `corpus`; returns how many files changed.
pub fn retag_tiers(corpus: &Path) -> usize {
    let (fixtures, _) = crate::fixture::discover(corpus);
    let mut changed = 0;
    for f in fixtures {
        let (meta_path, source, text) = match &f.root {
            crate::fixture::FixtureRoot::File(p) => {
                let Ok(t) = fs::read_to_string(p) else {
                    continue;
                };
                (p.clone(), Some(t.clone()), t)
            }
            crate::fixture::FixtureRoot::Dir(d) => {
                let Ok(_) = fs::read_to_string(d.join("conform.meta")) else {
                    continue;
                };
                (d.join("conform.meta"), None, project_text(d))
            }
        };
        let meta_text = source
            .clone()
            .unwrap_or_else(|| fs::read_to_string(&meta_path).unwrap_or_default());
        let Ok(mut meta) = crate::fixture::parse_meta(&meta_text) else {
            continue;
        };
        let mut tags: Vec<String> = meta
            .tags
            .iter()
            .filter(|t| !t.starts_with("tier-"))
            .cloned()
            .collect();
        tags.push(tier_of(&imports_of(&text)).to_string());
        tags.sort();
        tags.dedup();
        if tags == meta.tags {
            continue;
        }
        meta.tags = tags;
        let header = render_meta(&meta);
        let out = match source {
            Some(t) => {
                header
                    + &t[t
                        .lines()
                        .take_while(|l| l.starts_with("# conform:"))
                        .map(|l| l.len() + 1)
                        .sum::<usize>()..]
            }
            None => header,
        };
        if fs::write(&meta_path, out).is_ok() {
            changed += 1;
        }
    }
    changed
}

/// Feature tags from the source text (conservative keyword rules).
pub fn tags_for(text: &str, phase: Phase) -> Vec<String> {
    let mut tags: BTreeSet<String> = BTreeSet::new();
    let rules: &[(&str, &str)] = &[
        ("match ", "match"),
        ("try ", "try-result"),
        ("Result[", "try-result"),
        ("?", "optional"),
        ("some(", "optional"),
        ("interface ", "interfaces"),
        ("impl ", "interfaces"),
        ("case ", "alternatives"),
        ("fn(", "closures"),
        (" -> ", "closures"),
        ("List[", "lists"),
        ("Map[", "maps"),
        ("Set[", "sets"),
        ("Decimal", "decimal"),
        ("Float", "numbers"),
        ("panic", "faults"),
        (".get(", "faults"),
        ("for ", "control-flow"),
        ("while ", "control-flow"),
        ("if ", "control-flow"),
        ("type ", "records"),
        ("var ", "mutation"),
        ("test \"", "testing"),
        ("import ", "modules"),
    ];
    for (needle, tag) in rules {
        if text.contains(needle) {
            tags.insert((*tag).to_string());
        }
    }
    if text.contains("fn ") && text.contains("[T") {
        tags.insert("generics".into());
    }
    if has_word(text, "let") && text.contains(", ") && text.contains("let (") {
        tags.insert("destructuring".into());
    }
    if text
        .lines()
        .any(|l| l.find('"').is_some_and(|q| l[q..].contains('{')))
    {
        tags.insert("interpolation".into());
    }
    if text.contains("String") {
        tags.insert("strings".into());
    }
    let imports = imports_of(text);
    for m in &imports {
        tags.insert(format!("stdlib-{m}"));
    }
    tags.insert(tier_of(&imports).into());
    if aliasing_dependent(text) {
        tags.insert("aliasing".into());
    }
    match phase {
        Phase::Parse => {
            tags.insert("parser".into());
        }
        Phase::Check => {
            tags.insert("diagnostics".into());
        }
        Phase::Test => {
            tags.insert("testing".into());
        }
        Phase::Run => {}
    }
    if tags.iter().all(|t| t.starts_with("tier-")) {
        tags.insert("functions".into());
    }
    tags.into_iter().collect()
}

/// Programs whose answer can depend on assignment sharing: explicit `.clone()`, or a
/// binding of one name to another next to an in-place mutation. Over-tagging is safe;
/// these fixtures leave the Rust gate until they are migrated.
pub fn aliasing_dependent(text: &str) -> bool {
    if text.contains(".clone()") {
        return true;
    }
    let mutates = [
        ".add(", ".append(", ".push(", ".insert(", ".remove(", ".set(", ".clear(",
    ]
    .iter()
    .any(|m| text.contains(m))
        || text.lines().any(|l| {
            let t = l.trim_start();
            let Some((lhs, _)) = t.split_once(" = ") else {
                return false;
            };
            lhs.contains('.') && !lhs.contains(' ') && !t.starts_with("let ")
        })
        || text.contains("[0] = ")
        || text.contains("] = ");
    if !mutates {
        return false;
    }
    text.lines().any(|l| {
        let t = l.trim();
        let Some(rest) = t.strip_prefix("let ").or_else(|| t.strip_prefix("var ")) else {
            return false;
        };
        let Some((_, rhs)) = rest.split_once(" = ") else {
            return false;
        };
        let rhs = rhs.trim();
        !rhs.is_empty()
            && rhs
                .chars()
                .all(|c| c.is_alphanumeric() || c == '_' || c == '.')
    })
}

#[derive(Debug, Default)]
pub struct HarvestSummary {
    pub written: usize,
    pub duplicates: usize,
    pub unusable: Vec<(String, String)>,
    pub by_phase: BTreeMap<&'static str, usize>,
}

pub struct HarvestOpts {
    pub jobs: usize,
    /// Also write a `parse` fixture (formatter output) next to each clean single-file program.
    pub formatter_twins: bool,
}

fn header(origin: &str, phase: Phase, text: &str, extra: &[&str]) -> Meta {
    let mut tags = tags_for(text, phase);
    tags.extend(extra.iter().map(|s| s.to_string()));
    tags.sort();
    tags.dedup();
    Meta {
        tags,
        phase: Some(phase),
        origin: origin.to_string(),
        deterministic: false,
        ..Meta::default()
    }
}

fn strip_headers(source: &str) -> &str {
    let mut rest = source;
    while rest.starts_with("# conform:") {
        rest = rest.split_once('\n').map_or("", |(_, r)| r);
    }
    rest
}

/// Classify and write fixtures for `candidates` under `corpus`.
pub fn harvest(
    ms: &Path,
    scratch: &Path,
    corpus: &Path,
    candidates: Vec<Candidate>,
    opts: &HarvestOpts,
) -> HarvestSummary {
    let _ = fs::create_dir_all(scratch);
    let mut summary = HarvestSummary::default();
    let mut seen_text: BTreeSet<String> = BTreeSet::new();
    let mut unique = Vec::new();
    for c in candidates {
        if let Body::Source(text) = &c.body {
            let key = text.trim().to_string();
            if key.is_empty() || !seen_text.insert(key) {
                summary.duplicates += 1;
                continue;
            }
        }
        unique.push(c);
    }
    let refs: Vec<&Candidate> = unique.iter().collect();
    let verdicts =
        runner::parallel_map(&refs, opts.jobs, |i, c| check_candidate(ms, scratch, i, c));
    let mut used_ids: BTreeSet<String> = BTreeSet::new();
    for (cand, verdict) in unique.iter().zip(verdicts) {
        if let Some(reason) = verdict.unusable {
            summary.unusable.push((cand.origin.clone(), reason));
            continue;
        }
        let mut id = format!("{}/{}", cand.category, cand.slug);
        let mut n = 1;
        while !used_ids.insert(id.clone()) {
            n += 1;
            id = format!("{}/{}-{n}", cand.category, cand.slug);
        }
        let written = match &cand.body {
            Body::Source(text) => write_single(corpus, &id, cand, text, &verdict, opts),
            Body::Project(dir) => write_project(corpus, &id, cand, dir, &verdict),
        };
        match written {
            Ok(phases) => {
                for p in phases {
                    summary.written += 1;
                    *summary.by_phase.entry(p).or_default() += 1;
                }
            }
            Err(e) => summary.unusable.push((cand.origin.clone(), e)),
        }
    }
    summary
}

fn single_phase(text: &str, v: &Verdict, hostile: bool) -> Phase {
    if v.parse_errors {
        Phase::Parse
    } else if v.type_errors {
        Phase::Check
    } else if text.contains("\ntest \"") || text.starts_with("test \"") {
        Phase::Test
    } else if !hostile && has_main(text) {
        Phase::Run
    } else {
        Phase::Check
    }
}

fn has_main(text: &str) -> bool {
    text.contains("export fn main(")
}

fn hostile(text: &str) -> bool {
    imports_of(text)
        .iter()
        .any(|m| HOSTILE_IMPORTS.contains(&m.as_str()))
}

fn write_single(
    corpus: &Path,
    id: &str,
    cand: &Candidate,
    text: &str,
    v: &Verdict,
    opts: &HarvestOpts,
) -> Result<Vec<&'static str>, String> {
    let body = strip_headers(text);
    let phase = single_phase(body, v, hostile(body));
    let mut written = vec![write_source(corpus, id, &cand.origin, phase, body, &[])?];
    // A run/test/check program that is syntactically valid also pins the formatter.
    if opts.formatter_twins && !v.parse_errors {
        written.push(write_source(
            corpus,
            &format!("{id}-fmt"),
            &cand.origin,
            Phase::Parse,
            body,
            &["formatter"],
        )?);
    }
    if phase == Phase::Test && has_main(body) {
        written.push(write_source(
            corpus,
            &format!("{id}-run"),
            &cand.origin,
            Phase::Run,
            body,
            &[],
        )?);
    }
    Ok(written)
}

fn write_source(
    corpus: &Path,
    id: &str,
    origin: &str,
    phase: Phase,
    body: &str,
    extra: &[&str],
) -> Result<&'static str, String> {
    let path = corpus.join(format!("{id}.ms"));
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let meta = header(origin, phase, body, extra);
    let mut text = render_meta(&meta);
    text.push_str(body);
    if !text.ends_with('\n') {
        text.push('\n');
    }
    fs::write(&path, text).map_err(|e| e.to_string())?;
    Ok(phase.name())
}

fn write_project(
    corpus: &Path,
    id: &str,
    cand: &Candidate,
    dir: &Path,
    v: &Verdict,
) -> Result<Vec<&'static str>, String> {
    let text = project_text(dir);
    let phase = if v.parse_errors || v.type_errors {
        Phase::Check
    } else if text.contains("\ntest \"") || text.starts_with("test \"") {
        Phase::Test
    } else if !hostile(&text) && has_main(&text) {
        Phase::Run
    } else {
        Phase::Check
    };
    let mut phases = vec![phase];
    if phase == Phase::Test && !hostile(&text) && has_main(&text) {
        phases.push(Phase::Run);
    }
    let mut written = Vec::new();
    for (i, p) in phases.into_iter().enumerate() {
        let target = if i == 0 {
            corpus.join(id)
        } else {
            corpus.join(format!("{id}-run"))
        };
        let _ = fs::remove_dir_all(&target);
        copy_project(dir, &target).map_err(|e| e.to_string())?;
        let mut meta = header(&cand.origin, p, &text, &["projects"]);
        if matches!(p, Phase::Run) {
            meta.timeout_secs = Some(120);
        }
        fs::write(target.join("conform.meta"), render_meta(&meta)).map_err(|e| e.to_string())?;
        written.push(p.name());
    }
    Ok(written)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tier_ignores_io_and_testing() {
        let set = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<BTreeSet<_>>();
        assert_eq!(tier_of(&set(&["io", "testing"])), "tier-core");
        assert_eq!(tier_of(&set(&["io", "json"])), "tier-stdlib");
        assert_eq!(tier_of(&set(&["fs"])), "tier-io");
    }

    #[test]
    fn slugs_are_stable() {
        assert_eq!(slugify("TestFoo/Bar baz"), "testfoo-bar-baz");
    }

    #[test]
    fn imports_and_tiers() {
        let text = "import a from \"@std/json.ms\"\nimport b from \"@std/fs.ms\"\n";
        let tags = tags_for(text, Phase::Run);
        assert!(tags.contains(&"stdlib-json".to_string()));
        assert!(tags.contains(&"tier-io".to_string()));
        assert!(tags_for("fn f() Int:\n    return 1\n", Phase::Run).contains(&"tier-core".into()));
    }

    #[test]
    fn aliasing_heuristic() {
        assert!(aliasing_dependent("let b = a.clone()\n"));
        assert!(aliasing_dependent("let b = a\nb.add(1)\n"));
        assert!(!aliasing_dependent("let b = a + 1\n"));
        assert!(!aliasing_dependent("let xs = [1]\nxs.add(1)\n"));
    }

    #[test]
    fn header_stripping() {
        assert_eq!(
            strip_headers("# conform: tags=x\n# conform: phase=run\nfn f"),
            "fn f"
        );
    }

    #[test]
    fn category_paths() {
        assert_eq!(
            category_of("tests/e2e/testdata/accept/cl-01.ms"),
            ("e2e/accept".into(), "cl-01".into())
        );
        assert_eq!(
            category_of("bench/perf/kernels/ms"),
            ("bench".into(), "perf-kernels-ms".into())
        );
    }
}

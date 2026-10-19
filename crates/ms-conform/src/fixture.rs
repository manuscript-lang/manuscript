//! Fixture discovery and metadata.
//!
//! A single-file fixture is `name.ms` with a `name.expected.json` beside it; a
//! project fixture is a directory holding `conform.meta` and `expected.json`.
//! Metadata lives in `# conform: key=value` lines (at the top of a single
//! file, or in `conform.meta`) so the corpus needs no side database.

use std::fs;
use std::path::{Path, PathBuf};

/// The phase a fixture exercises; each phase compares different observations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Phase {
    /// Lexer, parser and formatter: parse-phase diagnostics and `ms fmt` output.
    Parse,
    /// `ms check`: diagnostics (JSON and terminal text) and exit status.
    Check,
    /// `ms run`: stdout, stderr and exit status.
    Run,
    /// `ms test --json`: per-test results, summary and report shape.
    Test,
}

impl Phase {
    pub const ALL: [Phase; 4] = [Phase::Parse, Phase::Check, Phase::Run, Phase::Test];

    pub fn name(self) -> &'static str {
        match self {
            Phase::Parse => "parse",
            Phase::Check => "check",
            Phase::Run => "run",
            Phase::Test => "test",
        }
    }

    pub fn from_name(name: &str) -> Option<Phase> {
        Phase::ALL.into_iter().find(|p| p.name() == name)
    }
}

/// Feature-area tags. Stdlib modules are `stdlib-<module>`; anything else is rejected by `lint`.
pub const TAGS: &[&str] = &[
    "lexer",
    "layout",
    "parser",
    "formatter",
    "types",
    "generics",
    "interfaces",
    "closures",
    "match",
    "destructuring",
    "try-result",
    "optional",
    "with-cleanup",
    "faults",
    "strings",
    "lists",
    "maps",
    "sets",
    "numbers",
    "decimal",
    "interpolation",
    "records",
    "alternatives",
    "control-flow",
    "functions",
    "modules",
    "projects",
    "diagnostics",
    "mutation",
    "json-protocol",
    "docs",
    "examples",
    "perf",
    "fuzz",
    "bench",
    "stdlib",
    "cli",
    "testing",
];

pub fn tag_allowed(tag: &str) -> bool {
    TAGS.contains(&tag) || tag.strip_prefix("stdlib-").is_some_and(|m| !m.is_empty())
}

#[derive(Debug, Clone)]
pub struct Fixture {
    /// Stable id: path under the fixtures root without extension, `/` separated.
    pub id: String,
    pub root: FixtureRoot,
    pub tags: Vec<String>,
    pub phase: Phase,
    pub origin: String,
    pub args: Vec<String>,
    pub stdin: Vec<u8>,
    pub timeout_secs: Option<u64>,
    /// File (relative to the work dir) passed to `ms`.
    pub entry: String,
    /// The oracle gives the same answer on every run (skipped by the stability check when set).
    pub deterministic: bool,
    pub expected_path: PathBuf,
}

#[derive(Debug, Clone)]
pub enum FixtureRoot {
    File(PathBuf),
    Dir(PathBuf),
}

impl Fixture {
    /// Copy the fixture's inputs into `work` and return the entry path argument.
    pub fn materialize(&self, work: &Path) -> std::io::Result<String> {
        fs::create_dir_all(work)?;
        match &self.root {
            FixtureRoot::File(path) => {
                let name = path.file_name().expect("fixture file name");
                fs::copy(path, work.join(name))?;
            }
            FixtureRoot::Dir(dir) => copy_tree(dir, work)?,
        }
        Ok(self.entry.clone())
    }
}

fn copy_tree(from: &Path, to: &Path) -> std::io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let name = entry.file_name();
        let name_text = name.to_string_lossy();
        if matches!(
            name_text.as_ref(),
            "conform.meta" | "expected.json" | "conform.stdin"
        ) {
            continue;
        }
        let target = to.join(&name);
        if entry.file_type()?.is_dir() {
            copy_tree(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

/// Parsed `# conform:` header lines.
#[derive(Debug, Default, Clone)]
pub struct Meta {
    pub tags: Vec<String>,
    pub phase: Option<Phase>,
    pub origin: String,
    pub args: Vec<String>,
    pub timeout_secs: Option<u64>,
    pub entry: Option<String>,
    pub deterministic: bool,
}

const PREFIX: &str = "# conform:";

/// Number of leading header lines in `source` (including none).
pub fn header_len(source: &str) -> usize {
    source.lines().take_while(|l| l.starts_with(PREFIX)).count()
}

pub fn parse_meta(text: &str) -> Result<Meta, String> {
    let mut meta = Meta::default();
    for line in text.lines() {
        let Some(rest) = line.strip_prefix(PREFIX) else {
            if line.trim().is_empty() || line.starts_with('#') {
                continue;
            }
            break;
        };
        let rest = rest.trim();
        let (key, value) = rest
            .split_once('=')
            .ok_or_else(|| format!("bad conform line: {line}"))?;
        let value = value.trim();
        match key.trim() {
            "tags" => {
                meta.tags = value
                    .split(',')
                    .map(|t| t.trim().to_string())
                    .filter(|t| !t.is_empty())
                    .collect()
            }
            "phase" => {
                meta.phase = Some(Phase::from_name(value).ok_or(format!("unknown phase {value}"))?)
            }
            "origin" => meta.origin = value.to_string(),
            "args" => {
                let parsed = crate::json::parse(value).map_err(|e| format!("args: {e}"))?;
                meta.args = parsed
                    .as_array()
                    .ok_or("args must be a JSON array")?
                    .iter()
                    .map(|v| v.as_str().map(str::to_string).ok_or("args must be strings"))
                    .collect::<Result<_, _>>()?;
            }
            "timeout" => meta.timeout_secs = Some(value.parse().map_err(|_| "bad timeout")?),
            "entry" => meta.entry = Some(value.to_string()),
            "deterministic" => meta.deterministic = value == "true",
            other => return Err(format!("unknown conform key {other}")),
        }
    }
    Ok(meta)
}

/// Render metadata back into header lines (used by the harvester and the fuzzer).
pub fn render_meta(meta: &Meta) -> String {
    use crate::json::Json;
    let mut out = String::new();
    out.push_str(&format!("{PREFIX} tags={}\n", meta.tags.join(",")));
    if let Some(p) = meta.phase {
        out.push_str(&format!("{PREFIX} phase={}\n", p.name()));
    }
    if !meta.origin.is_empty() {
        out.push_str(&format!("{PREFIX} origin={}\n", meta.origin));
    }
    if !meta.args.is_empty() {
        let arr = Json::Arr(meta.args.iter().map(|a| Json::str(a.clone())).collect());
        out.push_str(&format!("{PREFIX} args={}\n", arr.compact()));
    }
    if let Some(t) = meta.timeout_secs {
        out.push_str(&format!("{PREFIX} timeout={t}\n"));
    }
    if let Some(e) = &meta.entry {
        out.push_str(&format!("{PREFIX} entry={e}\n"));
    }
    if meta.deterministic {
        out.push_str(&format!("{PREFIX} deterministic=true\n"));
    }
    out
}

/// Find every fixture under `root`, sorted by id. Problems are returned as warnings.
pub fn discover(root: &Path) -> (Vec<Fixture>, Vec<String>) {
    let mut fixtures = Vec::new();
    let mut warnings = Vec::new();
    walk(root, root, &mut fixtures, &mut warnings);
    fixtures.sort_by(|a, b| a.id.cmp(&b.id));
    (fixtures, warnings)
}

fn walk(root: &Path, dir: &Path, out: &mut Vec<Fixture>, warnings: &mut Vec<String>) {
    let Ok(read) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = read.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if path.is_dir() {
            if path.join("conform.meta").exists() {
                match load_dir(root, &path) {
                    Ok(f) => out.push(f),
                    Err(e) => warnings.push(format!("{}: {e}", path.display())),
                }
            } else {
                walk(root, &path, out, warnings);
            }
        } else if name.ends_with(".ms") {
            match load_file(root, &path) {
                Ok(f) => out.push(f),
                Err(e) => warnings.push(format!("{}: {e}", path.display())),
            }
        }
    }
}

fn id_of(root: &Path, path: &Path) -> String {
    let rel = path.strip_prefix(root).unwrap_or(path);
    let text = rel.to_string_lossy().replace('\\', "/");
    text.strip_suffix(".ms").unwrap_or(&text).to_string()
}

fn load_file(root: &Path, path: &Path) -> Result<Fixture, String> {
    let source = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let meta = parse_meta(&source)?;
    let stem = path.with_extension("");
    let expected_path = PathBuf::from(format!("{}.expected.json", stem.display()));
    let stdin = fs::read(format!("{}.stdin", stem.display())).unwrap_or_default();
    finish(
        id_of(root, path),
        FixtureRoot::File(path.to_path_buf()),
        meta,
        stdin,
        expected_path,
        path.file_name().unwrap().to_string_lossy().into_owned(),
    )
}

fn load_dir(root: &Path, dir: &Path) -> Result<Fixture, String> {
    let meta_text = fs::read_to_string(dir.join("conform.meta")).map_err(|e| e.to_string())?;
    let meta = parse_meta(&meta_text)?;
    let stdin = fs::read(dir.join("conform.stdin")).unwrap_or_default();
    let default_entry = if dir.join("ms.toml").exists() {
        "ms.toml".to_string()
    } else {
        String::new()
    };
    finish(
        id_of(root, dir),
        FixtureRoot::Dir(dir.to_path_buf()),
        meta,
        stdin,
        dir.join("expected.json"),
        default_entry,
    )
}

fn finish(
    id: String,
    root: FixtureRoot,
    meta: Meta,
    stdin: Vec<u8>,
    expected_path: PathBuf,
    default_entry: String,
) -> Result<Fixture, String> {
    let phase = meta.phase.ok_or("missing phase")?;
    let entry = meta.entry.unwrap_or(default_entry);
    if entry.is_empty() {
        return Err("project fixture needs entry= (no ms.toml)".into());
    }
    Ok(Fixture {
        id,
        root,
        tags: meta.tags,
        phase,
        origin: meta.origin,
        args: meta.args,
        stdin,
        timeout_secs: meta.timeout_secs,
        entry,
        deterministic: meta.deterministic,
        expected_path,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn meta_round_trip() {
        let meta = Meta {
            tags: vec!["lists".into(), "stdlib-math".into()],
            phase: Some(Phase::Run),
            origin: "x/y.go:Test".into(),
            args: vec!["a b".into(), "c".into()],
            timeout_secs: Some(9),
            entry: None,
            deterministic: true,
        };
        let text = render_meta(&meta) + "fn main() Int:\n";
        let back = parse_meta(&text).unwrap();
        assert_eq!(back.tags, meta.tags);
        assert_eq!(back.phase, meta.phase);
        assert_eq!(back.args, meta.args);
        assert_eq!(back.timeout_secs, Some(9));
        assert!(back.deterministic);
        assert_eq!(header_len(&text), 6);
    }

    #[test]
    fn unknown_keys_fail() {
        assert!(parse_meta("# conform: wat=1\n").is_err());
    }

    #[test]
    fn tag_rules() {
        assert!(tag_allowed("stdlib-json"));
        assert!(tag_allowed("match"));
        assert!(!tag_allowed("nonsense"));
    }
}

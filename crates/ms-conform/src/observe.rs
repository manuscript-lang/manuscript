//! Run one fixture against an `ms` binary and reduce what happened to a
//! normalized JSON observation. Recording stores an observation; checking
//! compares a fresh observation with the stored one.

use crate::exec::{self, Output};
use crate::fixture::{Fixture, Phase};
use crate::json::Json;
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

/// Settings shared by every observation in one invocation.
#[derive(Debug, Clone)]
pub struct Ctx {
    pub ms: PathBuf,
    pub scratch: PathBuf,
    /// Multiplies every timeout (slow machines, debug builds).
    pub timeout_scale: f64,
    pub env: Vec<(String, String)>,
}

static COUNTER: AtomicU64 = AtomicU64::new(0);

/// Default timeouts in seconds; a first `ms run` may also build the toolchain cache.
fn default_timeout(phase: Phase) -> u64 {
    match phase {
        Phase::Parse => 30,
        Phase::Check => 60,
        Phase::Run => 120,
        Phase::Test => 180,
    }
}

impl Ctx {
    pub fn new(ms: PathBuf) -> Ctx {
        Ctx {
            ms,
            scratch: std::env::temp_dir().join(format!("ms-conform-{}", std::process::id())),
            timeout_scale: 1.0,
            env: Vec::new(),
        }
    }

    fn timeout(&self, fx: &Fixture) -> Duration {
        let secs = fx.timeout_secs.unwrap_or_else(|| default_timeout(fx.phase)) as f64;
        Duration::from_secs_f64(secs * self.timeout_scale)
    }

    fn invoke(&self, fx: &Fixture, args: &[&str], cwd: &Path, stdin: &[u8]) -> Output {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        exec::run(&self.ms, &args, cwd, stdin, self.timeout(fx), &self.env)
    }
}

/// Replace every spelling of the work directory with `<DIR>`.
pub fn normalize_text(text: &str, work: &Path) -> String {
    let mut out = replace_spellings(text, work, "<DIR>");
    // Imports such as `../a.ms` name the scratch root, whose name carries a process id.
    if let Some(root) = work.parent() {
        out = replace_spellings(&out, root, "<SCRATCH>");
    }
    out
}

/// Replace every spelling of `path` in `text`: as given, canonical (`/private/var/...` for
/// `/var/...`, `\\?\C:\...` on Windows), and with `/` separators, which `ms` prints on Windows.
fn replace_spellings(text: &str, path: &Path, with: &str) -> String {
    let mut spellings = vec![path.to_string_lossy().into_owned()];
    if let Ok(real) = fs::canonicalize(path) {
        let real = real.to_string_lossy().into_owned();
        spellings.push(real.strip_prefix(r"\\?\").unwrap_or(&real).to_string());
        spellings.push(real);
    }
    let slashed: Vec<String> = spellings.iter().map(|s| s.replace('\\', "/")).collect();
    spellings.extend(slashed);
    // The longer spelling goes first: a canonical one can extend the plain one.
    spellings.sort_by_key(|s| std::cmp::Reverse(s.len()));
    spellings.dedup();
    let mut out = text.to_string();
    for s in spellings {
        out = out.replace(&s, with);
    }
    out
}

/// Observe `fx` using `ctx.ms`. The observation is deterministic for deterministic programs.
pub fn observe(ctx: &Ctx, fx: &Fixture) -> Json {
    let work = ctx
        .scratch
        .join(format!("w{}", COUNTER.fetch_add(1, Ordering::Relaxed)));
    let _ = fs::remove_dir_all(&work);
    let result = match fx.materialize(&work) {
        Ok(entry) => match fx.phase {
            Phase::Parse => parse_phase(ctx, fx, &work, &entry),
            Phase::Check => check_phase(ctx, fx, &work, &entry),
            Phase::Run => run_phase(ctx, fx, &work, &entry),
            Phase::Test => test_phase(ctx, fx, &work, &entry),
        },
        Err(e) => {
            let mut o = Json::object();
            o.set("harness_error", Json::str(e.to_string()));
            o
        }
    };
    let _ = fs::remove_dir_all(&work);
    result
}

fn process_fields(o: &mut Json, out: &Output, work: &Path) {
    o.set("exit_code", Json::int(out.code as i64));
    if out.timed_out {
        o.set("timed_out", Json::Bool(true));
    }
    if let Some(e) = &out.spawn_error {
        o.set("spawn_error", Json::str(e.clone()));
    }
    let _ = work;
}

fn run_phase(ctx: &Ctx, fx: &Fixture, work: &Path, entry: &str) -> Json {
    let mut args: Vec<&str> = vec!["run", entry];
    if !fx.args.is_empty() {
        args.push("--");
        args.extend(fx.args.iter().map(String::as_str));
    }
    let out = ctx.invoke(fx, &args, work, &fx.stdin);
    let mut o = Json::object();
    process_fields(&mut o, &out, work);
    o.set(
        "stdout",
        Json::str(normalize_text(&out.stdout_text(), work)),
    );
    o.set(
        "stderr",
        Json::str(normalize_text(&out.stderr_text(), work)),
    );
    o
}

fn parse_json_output(out: &Output, work: &Path) -> Json {
    match crate::json::parse(out.stdout_text()) {
        Ok(mut j) => {
            j.map_strings(&|s| normalize_text(s, work));
            j
        }
        Err(e) => {
            let mut o = Json::object();
            o.set("unparsable_json", Json::str(e));
            o.set(
                "stdout",
                Json::str(normalize_text(&out.stdout_text(), work)),
            );
            o
        }
    }
}

fn diagnostics_of(report: &Json) -> Json {
    report
        .get("diagnostics")
        .cloned()
        .unwrap_or(Json::Arr(Vec::new()))
}

fn check_phase(ctx: &Ctx, fx: &Fixture, work: &Path, entry: &str) -> Json {
    let json_out = ctx.invoke(fx, &["check", entry, "--json"], work, b"");
    let report = parse_json_output(&json_out, work);
    let text_out = ctx.invoke(fx, &["check", entry], work, b"");
    let mut o = Json::object();
    process_fields(&mut o, &json_out, work);
    if let Some(v) = report.get("format") {
        o.set("format", v.clone());
    }
    o.set("diagnostics", diagnostics_of(&report));
    if report.get("unparsable_json").is_some() {
        o.set("raw", report);
    }
    let mut text = Json::object();
    text.set("exit_code", Json::int(text_out.code as i64));
    text.set(
        "stdout",
        Json::str(normalize_text(&text_out.stdout_text(), work)),
    );
    text.set(
        "stderr",
        Json::str(normalize_text(&text_out.stderr_text(), work)),
    );
    o.set("text", text);
    o
}

fn parse_phase(ctx: &Ctx, fx: &Fixture, work: &Path, entry: &str) -> Json {
    let json_out = ctx.invoke(fx, &["check", entry, "--json"], work, b"");
    let report = parse_json_output(&json_out, work);
    let parse_diags: Vec<Json> = diagnostics_of(&report)
        .as_array()
        .unwrap_or(&[])
        .iter()
        .filter(|d| d.get("phase").and_then(Json::as_str) == Some("parse"))
        .cloned()
        .collect();
    let mut o = Json::object();
    o.set("diagnostics", Json::Arr(parse_diags));
    if report.get("unparsable_json").is_some() {
        o.set("raw", report);
    }
    let fmt_out = ctx.invoke(fx, &["fmt", entry], work, b"");
    if fmt_out.code == 0 {
        let formatted = fs::read_to_string(work.join(entry)).unwrap_or_default();
        // The metadata header is a comment block at the top; retagging must not move expectations.
        let skip: usize = formatted
            .lines()
            .take(crate::fixture::header_len(&formatted))
            .map(|l| l.len() + 1)
            .sum();
        o.set("fmt", Json::str(&formatted[skip.min(formatted.len())..]));
    } else {
        o.set("fmt", Json::Null);
        o.set("fmt_exit_code", Json::int(fmt_out.code as i64));
    }
    o
}

/// Key paths of a report, e.g. `tests[].status`, so a missing or extra field is a protocol break.
fn shape(value: &Json, path: &str, out: &mut BTreeSet<String>) {
    match value {
        Json::Obj(fields) => {
            for (k, v) in fields {
                let next = if path.is_empty() {
                    k.clone()
                } else {
                    format!("{path}.{k}")
                };
                out.insert(next.clone());
                shape(v, &next, out);
            }
        }
        Json::Arr(items) => {
            for item in items {
                shape(item, &format!("{path}[]"), out);
            }
        }
        _ => {}
    }
}

fn strip_durations(report: &mut Json) {
    report.remove("duration_ns");
    if let Json::Obj(fields) = report {
        for (_, v) in fields.iter_mut() {
            match v {
                Json::Arr(items) => items.iter_mut().for_each(strip_durations),
                Json::Obj(_) => strip_durations(v),
                _ => {}
            }
        }
    }
}

/// Drops the structured `fault` that `ms test --json` adds beside the failure text; the
/// recorded oracle never reported it, and the failure text already carries the same facts.
fn strip_faults(report: &mut Json) {
    report.remove("fault");
    if let Json::Obj(fields) = report {
        for (_, v) in fields.iter_mut() {
            match v {
                Json::Arr(items) => items.iter_mut().for_each(strip_faults),
                Json::Obj(_) => strip_faults(v),
                _ => {}
            }
        }
    }
}

fn test_phase(ctx: &Ctx, fx: &Fixture, work: &Path, entry: &str) -> Json {
    let mut args: Vec<&str> = vec!["test", entry, "--json"];
    if !fx.args.is_empty() {
        args.push("--");
        args.extend(fx.args.iter().map(String::as_str));
    }
    let out = ctx.invoke(fx, &args, work, &fx.stdin);
    let mut report = parse_json_output(&out, work);
    strip_faults(&mut report);
    let mut keys = BTreeSet::new();
    shape(&report, "", &mut keys);
    strip_durations(&mut report);
    let mut o = Json::object();
    process_fields(&mut o, &out, work);
    o.set("report", report);
    o.set(
        "shape",
        Json::Arr(keys.into_iter().map(Json::Str).collect()),
    );
    o.set(
        "stderr",
        Json::str(normalize_text(&out.stderr_text(), work)),
    );
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_replaces_dir() {
        let work = Path::new("/tmp/ms-conform-x/w1");
        assert_eq!(
            normalize_text("at /tmp/ms-conform-x/w1/a.ms:3", work),
            "at <DIR>/a.ms:3"
        );
        assert_eq!(
            normalize_text("looked for /tmp/ms-conform-x/a.ms", work),
            "looked for <SCRATCH>/a.ms"
        );
    }

    #[test]
    fn shape_lists_key_paths() {
        let j = crate::json::parse(r#"{"a":{"b":1},"t":[{"n":1},{"n":2,"f":"x"}]}"#).unwrap();
        let mut keys = BTreeSet::new();
        shape(&j, "", &mut keys);
        let v: Vec<_> = keys.into_iter().collect();
        assert_eq!(v, ["a", "a.b", "t", "t[].f", "t[].n"]);
    }

    #[test]
    fn durations_are_stripped_recursively() {
        let mut j = crate::json::parse(
            r#"{"summary":{"duration_ns":5,"x":1},"tests":[{"duration_ns":1}]}"#,
        )
        .unwrap();
        strip_durations(&mut j);
        assert_eq!(
            j.compact(ms_json::Escape::Plain),
            r#"{"summary":{"x":1},"tests":[{}]}"#
        );
    }
}

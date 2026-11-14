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
    /// `CONFORM_LEAKS` is set: programs run against the runtime that counts live heap blocks
    /// (`MS_RT_LIB`). Its count line is removed from stderr, and a program of the leak-checked
    /// fixture directories that exits with live blocks records `leaked_blocks`, so it differs from
    /// its expectation.
    pub leaks: bool,
}

/// Fixture directories whose programs must free every block they allocate.
const LEAK_CHECKED: [&str; 3] = ["fuzz/run/", "e2e/", "examples/"];

const LIVE_BLOCKS: &str = "ms-rt live blocks at exit: ";
const COUNTS: &str = "ms-rt counts: ";
const LIVE_BY_SIZE: &str = "ms-rt live blocks by size: ";
const RUST_HEAP: &str = "ms-rt rust heap at exit: ";

/// `text` without the counting runtime's lines (live blocks, Rust heap and counts), and the sum of the live counts.
fn split_live_blocks(text: &str) -> (String, i64) {
    let mut kept = String::with_capacity(text.len());
    let mut live = 0;
    for line in text.split_inclusive('\n') {
        let line_text = line.trim_end();
        if let Some(count) = line_text.strip_prefix(LIVE_BLOCKS) {
            live += count.trim().parse::<i64>().unwrap_or(0);
        } else if !line_text.starts_with(COUNTS)
            && !line_text.starts_with(LIVE_BY_SIZE)
            && !line_text.starts_with(RUST_HEAP)
        {
            kept.push_str(line);
        }
    }
    (kept, live)
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
            leaks: std::env::var_os("CONFORM_LEAKS").is_some(),
        }
    }

    fn timeout(&self, fx: &Fixture) -> Duration {
        let secs = fx.timeout_secs.unwrap_or_else(|| default_timeout(fx.phase)) as f64;
        Duration::from_secs_f64(secs * self.timeout_scale)
    }

    fn invoke(&self, fx: &Fixture, args: &[&str], cwd: &Path, stdin: &[u8]) -> Output {
        self.invoke_within(self.timeout(fx), args, cwd, stdin)
    }

    fn invoke_within(&self, timeout: Duration, args: &[&str], cwd: &Path, stdin: &[u8]) -> Output {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        exec::run(&self.ms, &args, cwd, stdin, timeout, &self.env)
    }
}

/// Replace every spelling of the work directory with `<DIR>`.
pub fn normalize_text(text: &str, work: &Path) -> String {
    let mut out = replace_spellings(text, work, "<DIR>");
    // Imports such as `../a.ms` name the scratch root, whose name carries a process id.
    if let Some(root) = work.parent() {
        out = replace_spellings(&out, root, "<SCRATCH>");
    }
    mask_stdlib_lines(&out)
}

/// Replace the line of a standard-library frame (`@std/concurrency/promise.ms:312`) with `<LINE>`, so editing a
/// standard-library file does not change the expectation of every fixture that faults through it.
fn mask_stdlib_lines(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find("@std/") {
        let (head, tail) = rest.split_at(at);
        out.push_str(head);
        let Some(dot) = tail.find(".ms:") else {
            out.push_str(tail);
            return out;
        };
        let name_ok = tail[..dot]
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"@/_-".contains(&b));
        let after = &tail[dot + 4..];
        let digits = after.bytes().take_while(u8::is_ascii_digit).count();
        if name_ok && digits > 0 {
            out.push_str(&tail[..dot + 4]);
            out.push_str("<LINE>");
            rest = &after[digits..];
        } else {
            out.push_str("@std/");
            rest = &tail[5..];
        }
    }
    out.push_str(rest);
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
    let mut args: Vec<&str> = vec!["run", entry, "--build-type", "Release"];
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
    set_stderr(ctx, fx, &out, &mut o, work);
    o
}

/// Records the process's stderr, without the runtime's live-block lines when `ctx.leaks`, and
/// `leaked_blocks` when a leak-checked fixture left any.
fn set_stderr(ctx: &Ctx, fx: &Fixture, out: &Output, o: &mut Json, work: &Path) {
    let mut stderr = out.stderr_text();
    if ctx.leaks {
        let (kept, live) = split_live_blocks(&stderr);
        stderr = kept;
        if live != 0 && LEAK_CHECKED.iter().any(|dir| fx.id.starts_with(dir)) {
            o.set("leaked_blocks", Json::int(live));
        }
    }
    o.set("stderr", Json::str(normalize_text(&stderr, work)));
}

/// Keys added to the JSON output after the corpus was recorded. They are additive, so the
/// frozen expectations compare without them.
fn drop_additive_keys(value: &mut Json) {
    match value {
        Json::Obj(fields) => {
            fields.retain(|(k, _)| k != "subcode");
            fields.iter_mut().for_each(|(_, v)| drop_additive_keys(v));
        }
        Json::Arr(items) => items.iter_mut().for_each(drop_additive_keys),
        _ => {}
    }
}

fn parse_json_output(out: &Output, work: &Path) -> Json {
    match crate::json::parse(out.stdout_text()) {
        Ok(mut j) => {
            j.map_strings(&|s| normalize_text(s, work));
            drop_additive_keys(&mut j);
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
    // `--with-text` carries the terminal output in the same document, so one `ms check` (and one
    // standard-library load) observes both. A run that wrote no document, such as a usage error,
    // is repeated without `--json` for its terminal output.
    let json_out = ctx.invoke(fx, &["check", entry, "--json", "--with-text"], work, b"");
    let report = parse_json_output(&json_out, work);
    let text_out = match report.get("text") {
        Some(text) => Output {
            code: json_out.code,
            stdout: text_field(text, "stdout"),
            stderr: text_field(text, "stderr"),
            ..Output::default()
        },
        None => ctx.invoke(fx, &["check", entry], work, b""),
    };
    check_observation(
        report,
        &json_out,
        text_out.code,
        &normalize_text(&text_out.stdout_text(), work),
        &normalize_text(&text_out.stderr_text(), work),
        work,
    )
}

/// The check observation: the JSON report (normalized) beside the terminal output (normalized).
fn check_observation(
    report: Json,
    json_out: &Output,
    text_code: i32,
    stdout: &str,
    stderr: &str,
    work: &Path,
) -> Json {
    let mut o = Json::object();
    process_fields(&mut o, json_out, work);
    if let Some(v) = report.get("format") {
        o.set("format", v.clone());
    }
    o.set("diagnostics", diagnostics_of(&report));
    if report.get("unparsable_json").is_some() {
        o.set("raw", report);
    }
    let mut text = Json::object();
    text.set("exit_code", Json::int(i64::from(text_code)));
    text.set("stdout", Json::str(stdout));
    text.set("stderr", Json::str(stderr));
    o.set("text", text);
    o
}

/// Observe several check fixtures with one `ms check --each`, which loads the standard library
/// once. A fixture the batch could not report is observed on its own, so a crash or timeout in
/// one fixture still names that fixture.
pub fn observe_check_batch(ctx: &Ctx, fixtures: &[&Fixture]) -> Vec<Json> {
    let root = ctx
        .scratch
        .join(format!("b{}", COUNTER.fetch_add(1, Ordering::Relaxed)));
    let _ = fs::remove_dir_all(&root);
    let mut targets = Vec::new();
    let mut slots: Vec<Option<usize>> = Vec::new();
    for (i, fx) in fixtures.iter().enumerate() {
        let work = root.join(format!("w{i}"));
        match fx.materialize(&work) {
            // A path that leaves the fixture directory prints differently from a batch root.
            Ok(entry) if !mentions_parent_path(&work) => {
                slots.push(Some(targets.len()));
                targets.push(format!("w{i}/{entry}"));
            }
            _ => slots.push(None),
        }
    }
    let mut args: Vec<&str> = vec!["check"];
    args.extend(targets.iter().map(String::as_str));
    args.extend(["--json", "--with-text", "--each"]);
    let timeout = fixtures.iter().map(|fx| ctx.timeout(fx)).sum();
    let out = ctx.invoke_within(timeout, &args, &root, b"");
    let results = crate::json::parse(out.stdout_text())
        .ok()
        .and_then(|doc| {
            doc.get("results")
                .and_then(Json::as_array)
                .map(<[_]>::to_vec)
        })
        .filter(|results| results.len() == targets.len());
    let observed = fixtures
        .iter()
        .enumerate()
        .map(|(i, fx)| {
            let from_batch = match (&results, slots[i]) {
                (Some(results), Some(slot)) => batch_check_result(&results[slot], &root, i),
                _ => None,
            };
            from_batch.unwrap_or_else(|| observe(ctx, fx))
        })
        .collect();
    let _ = fs::remove_dir_all(&root);
    observed
}

/// True when a file under `dir` names a `../` path, which can reach outside the fixture.
fn mentions_parent_path(dir: &Path) -> bool {
    let Ok(entries) = fs::read_dir(dir) else {
        return false;
    };
    entries.flatten().any(|entry| {
        let path = entry.path();
        if path.is_dir() {
            mentions_parent_path(&path)
        } else {
            fs::read_to_string(&path).is_ok_and(|text| text.contains("../"))
        }
    })
}

/// The check observation of fixture `i` of a batch run in `root`, or `None` when the run wrote no
/// document with the terminal output for it.
fn batch_check_result(result: &Json, root: &Path, i: usize) -> Option<Json> {
    let work = root.join(format!("w{i}"));
    let code = i32::try_from(result.get("exit_code").and_then(Json::as_i64)?).ok()?;
    let mut report = result
        .get("document")
        .filter(|d| d.get("text").is_some())?
        .clone();
    // Windows prints the relative paths of the batch with either separator.
    let (slash, backslash) = (format!("w{i}/"), format!("w{i}\\"));
    report.map_strings(&|s| normalize_text(&strip_dir(&strip_dir(s, &slash), &backslash), &work));
    drop_additive_keys(&mut report);
    let text = report.get("text")?.clone();
    let stream = |name: &str| {
        text.get(name)
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string()
    };
    let json_out = Output {
        code,
        ..Output::default()
    };
    Some(check_observation(
        report,
        &json_out,
        code,
        &stream("stdout"),
        &stream("stderr"),
        &work,
    ))
}

/// `text` without the batch directory prefix `dir` of a relative path, so a path reads as it does
/// when the fixture is checked from its own directory.
fn strip_dir(text: &str, dir: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find(dir) {
        let (head, tail) = rest.split_at(at);
        out.push_str(head);
        let starts_path = out
            .chars()
            .next_back()
            .is_none_or(|c| !(c.is_alphanumeric() || "/._-".contains(c)));
        if !starts_path {
            out.push_str(dir);
        }
        rest = &tail[dir.len()..];
    }
    out.push_str(rest);
    out
}

/// One stream of a `--with-text` document as bytes.
fn text_field(text: &Json, stream: &str) -> Vec<u8> {
    let value = text.get(stream).and_then(Json::as_str).unwrap_or("");
    value.as_bytes().to_vec()
}

fn parse_phase(ctx: &Ctx, fx: &Fixture, work: &Path, entry: &str) -> Json {
    // `fmt --check` parses without loading and checking the standard library, which `check`
    // does for every file that parses (about 127 ms); the parse diagnostics are the same.
    let json_out = ctx.invoke(fx, &["fmt", entry, "--check", "--json"], work, b"");
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
    let mut args: Vec<&str> = vec!["test", entry, "--json", "--build-type", "Release"];
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
    set_stderr(ctx, fx, &out, &mut o, work);
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
    fn normalize_masks_stdlib_lines() {
        let work = Path::new("/tmp/ms-conform-x/w1");
        assert_eq!(
            normalize_text(
                "at @std/concurrency/promise.ms:283 in run\nat a.ms:3 in f @std/x.ms:1 @std/y",
                work
            ),
            "at @std/concurrency/promise.ms:<LINE> in run\nat a.ms:3 in f @std/x.ms:<LINE> @std/y"
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

#[cfg(test)]
mod live_block_tests {
    use super::split_live_blocks;

    #[test]
    fn live_block_lines_are_removed_and_summed() {
        let (kept, live) = split_live_blocks(
            "a\nms-rt rust heap at exit: blocks=3 bytes=236\nms-rt live blocks at exit: 2\nb\nms-rt counts: allocs=1\nms-rt live blocks at exit: 3\n",
        );
        assert_eq!((kept.as_str(), live), ("a\nb\n", 5));
    }
}

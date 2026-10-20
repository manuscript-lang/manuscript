//! Recording expectations from the oracle, and comparing two binaries directly.

use crate::compare;
use crate::exec;
use crate::fixture::Fixture;
use crate::json::Json;
use crate::observe::{self, Ctx};
use crate::runner::{self, Case, Outcome};
use std::fs;
use std::path::Path;
use std::time::Duration;

#[derive(Debug, Clone, Copy)]
pub struct RecordOpts {
    pub jobs: usize,
    /// Observe twice and refuse fixtures whose answers differ.
    pub check_stable: bool,
    /// Delete fixtures that are unstable or cannot be recorded.
    pub prune: bool,
    /// Keep existing expectations; only record fixtures without one.
    pub only_missing: bool,
}

#[derive(Debug, Default)]
pub struct RecordSummary {
    pub written: usize,
    pub unchanged: usize,
    pub rejected: Vec<(String, String)>,
}

/// The oracle's `ms version` text, stored in each expectation for provenance.
pub fn oracle_version(ms: &Path) -> String {
    let out = exec::run(
        ms,
        &["version".to_string()],
        Path::new("."),
        b"",
        Duration::from_secs(30),
        &[],
    );
    out.stdout_text().trim().to_string()
}

fn unrecordable(obs: &Json) -> Option<String> {
    for key in [
        "harness_error",
        "spawn_error",
        "timed_out",
        "unparsable_json",
    ] {
        if obs.get(key).is_some() {
            return Some(format!(
                "observation has {key}: {}",
                obs.compact(ms_json::Escape::Plain)
                    .chars()
                    .take(300)
                    .collect::<String>()
            ));
        }
    }
    if let Some(report) = obs.get("report")
        && report.get("unparsable_json").is_some()
    {
        return Some("ms test did not print JSON".into());
    }
    None
}

fn record_one(
    ctx: &Ctx,
    fx: &Fixture,
    version: &str,
    opts: &RecordOpts,
) -> Result<(Json, bool), String> {
    if opts.only_missing && fx.expected_path.exists() {
        return Ok((Json::Null, false));
    }
    let first = observe::observe(ctx, fx);
    if let Some(reason) = unrecordable(&first) {
        return Err(reason);
    }
    if opts.check_stable && !fx.deterministic {
        let second = observe::observe(ctx, fx);
        if let Some(d) = compare::diff(&first, &second, 4) {
            return Err(format!("unstable between runs:\n{d}"));
        }
    }
    let mut doc = Json::object();
    doc.set("format", Json::int(1));
    doc.set("phase", Json::str(fx.phase.name()));
    doc.set("oracle", Json::str(version));
    doc.set("expected", first);
    Ok((doc, true))
}

pub fn record(ctx: &Ctx, fixtures: &[&Fixture], opts: RecordOpts) -> RecordSummary {
    let version = oracle_version(&ctx.ms);
    let _ = fs::create_dir_all(&ctx.scratch);
    let results = runner::parallel_map(fixtures, opts.jobs, |i, fx| {
        let r = record_one(ctx, fx, &version, &opts);
        if i % 25 == 0 {
            eprintln!("[{}/{}] recorded {}", i + 1, fixtures.len(), fx.id);
        }
        r
    });
    let _ = fs::remove_dir_all(&ctx.scratch);
    let mut summary = RecordSummary::default();
    for (fx, result) in fixtures.iter().zip(results) {
        match result {
            Ok((_, false)) => summary.unchanged += 1,
            Ok((doc, true)) => {
                let text = doc.pretty_line(ms_json::Escape::Plain);
                if fs::read_to_string(&fx.expected_path).is_ok_and(|old| old == text) {
                    summary.unchanged += 1;
                } else if fs::write(&fx.expected_path, text).is_ok() {
                    summary.written += 1;
                } else {
                    summary
                        .rejected
                        .push((fx.id.clone(), "cannot write expectation".into()));
                }
            }
            Err(reason) => {
                if opts.prune {
                    delete_fixture(fx);
                }
                summary.rejected.push((fx.id.clone(), reason));
            }
        }
    }
    summary
}

fn delete_fixture(fx: &Fixture) {
    use crate::fixture::FixtureRoot;
    match &fx.root {
        FixtureRoot::Dir(dir) => {
            let _ = fs::remove_dir_all(dir);
        }
        FixtureRoot::File(path) => {
            let _ = fs::remove_file(path);
            let _ = fs::remove_file(&fx.expected_path);
            let _ = fs::remove_file(path.with_extension("stdin"));
        }
    }
}

/// Run two binaries on each fixture and compare their observations (no stored expectation).
pub fn diff_binaries(a: &Ctx, b: &Ctx, fixtures: &[&Fixture], jobs: usize) -> Vec<Case> {
    let _ = fs::create_dir_all(&a.scratch);
    let _ = fs::create_dir_all(&b.scratch);
    let cases = runner::parallel_map(fixtures, jobs, |_, fx| {
        let oa = observe::observe(a, fx);
        let ob = observe::observe(b, fx);
        let (outcome, diff) = match compare::diff(&oa, &ob, 8) {
            None => (Outcome::Pass, String::new()),
            Some(d) => (Outcome::Fail, d),
        };
        Case {
            id: fx.id.clone(),
            tags: fx.tags.clone(),
            phase: fx.phase,
            outcome,
            millis: 0,
            diff,
        }
    });
    let _ = fs::remove_dir_all(&a.scratch);
    let _ = fs::remove_dir_all(&b.scratch);
    cases
}

//! Selecting fixtures, running them in parallel and judging the outcome.

use crate::compare;
use crate::fixture::{Fixture, Phase};
use crate::json::{self, Json};
use crate::observe::{self, Ctx};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

/// Which fixtures to run.
#[derive(Debug, Clone, Default)]
pub struct Filter {
    /// A fixture matches when it has any of these tags (empty means all).
    pub tags: Vec<String>,
    pub exclude_tags: Vec<String>,
    pub phases: Vec<Phase>,
    /// Substring match on the fixture id (any of).
    pub ids: Vec<String>,
    /// `(index, count)`: keep fixtures whose position modulo `count` is `index`.
    pub shard: Option<(usize, usize)>,
}

pub fn select<'a>(all: &'a [Fixture], filter: &Filter) -> Vec<&'a Fixture> {
    all.iter()
        .filter(|f| {
            (filter.tags.is_empty() || f.tags.iter().any(|t| filter.tags.contains(t)))
                && !f.tags.iter().any(|t| filter.exclude_tags.contains(t))
                && (filter.phases.is_empty() || filter.phases.contains(&f.phase))
                && (filter.ids.is_empty() || filter.ids.iter().any(|i| f.id.contains(i.as_str())))
        })
        .enumerate()
        .filter(|(i, _)| filter.shard.is_none_or(|(n, c)| i % c == n))
        .map(|(_, f)| f)
        .collect()
}

/// Map `f` over `items` on up to `jobs` threads, preserving order.
pub fn parallel_map<T: Sync, R: Send>(
    items: &[T],
    jobs: usize,
    f: impl Fn(usize, &T) -> R + Sync,
) -> Vec<R> {
    let next = AtomicUsize::new(0);
    let slots: Mutex<Vec<Option<R>>> = Mutex::new((0..items.len()).map(|_| None).collect());
    thread::scope(|scope| {
        for _ in 0..jobs.max(1).min(items.len().max(1)) {
            scope.spawn(|| {
                loop {
                    let i = next.fetch_add(1, Ordering::SeqCst);
                    if i >= items.len() {
                        break;
                    }
                    let r = f(i, &items[i]);
                    slots.lock().expect("slots")[i] = Some(r);
                }
            });
        }
    });
    slots
        .into_inner()
        .expect("slots")
        .into_iter()
        .map(|r| r.expect("every slot filled"))
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Pass,
    /// Failed and not on the allowlist.
    Fail,
    /// Failed but listed in the expect-fail file.
    ExpectedFail,
    /// Passed although listed in the expect-fail file.
    UnexpectedPass,
    /// The fixture has no recorded expectation.
    Unrecorded,
}

#[derive(Debug, Clone)]
pub struct Case {
    pub id: String,
    pub tags: Vec<String>,
    pub phase: Phase,
    pub outcome: Outcome,
    pub millis: u128,
    pub diff: String,
}

/// Allowlist of known failures: ids, `prefix*` patterns, `#` comments.
#[derive(Debug, Default, Clone)]
pub struct ExpectFail {
    exact: BTreeSet<String>,
    prefixes: Vec<String>,
}

impl ExpectFail {
    pub fn parse(text: &str) -> ExpectFail {
        let mut e = ExpectFail::default();
        for line in text.lines() {
            let line = line.split('#').next().unwrap_or("").trim();
            if line.is_empty() {
                continue;
            }
            match line.strip_suffix('*') {
                Some(prefix) => e.prefixes.push(prefix.to_string()),
                None => {
                    e.exact.insert(line.to_string());
                }
            }
        }
        e
    }

    pub fn load(path: &Path) -> Result<ExpectFail, String> {
        fs::read_to_string(path)
            .map(|t| ExpectFail::parse(&t))
            .map_err(|e| format!("{}: {e}", path.display()))
    }

    pub fn contains(&self, id: &str) -> bool {
        self.exact.contains(id) || self.prefixes.iter().any(|p| id.starts_with(p.as_str()))
    }
}

pub fn load_expected(fx: &Fixture) -> Result<Json, String> {
    let text = fs::read_to_string(&fx.expected_path)
        .map_err(|e| format!("{}: {e}", fx.expected_path.display()))?;
    let doc = json::parse(&text)?;
    doc.get("expected")
        .cloned()
        .ok_or_else(|| format!("{}: no \"expected\" key", fx.expected_path.display()))
}

/// Run one fixture on `ctx.ms` and judge it against the recorded expectation.
pub fn check_one(ctx: &Ctx, fx: &Fixture, allow: &ExpectFail) -> Case {
    let started = std::time::Instant::now();
    judge(fx, allow, started, |_| observe::observe(ctx, fx))
}

/// Judge `fx` against its recorded expectation, observing it with `observe` once the expectation loads.
fn judge(
    fx: &Fixture,
    allow: &ExpectFail,
    started: std::time::Instant,
    observe: impl FnOnce(&Fixture) -> Json,
) -> Case {
    let (passed, diff) = match load_expected(fx) {
        Err(e) => {
            return Case {
                id: fx.id.clone(),
                tags: fx.tags.clone(),
                phase: fx.phase,
                outcome: Outcome::Unrecorded,
                millis: 0,
                diff: e,
            };
        }
        Ok(expected) => {
            let actual = observe(fx);
            match compare::diff(&expected, &actual, 8) {
                None => (true, String::new()),
                Some(d) => (false, d),
            }
        }
    };
    let listed = allow.contains(&fx.id);
    let outcome = match (passed, listed) {
        (true, false) => Outcome::Pass,
        (true, true) => Outcome::UnexpectedPass,
        (false, false) => Outcome::Fail,
        (false, true) => Outcome::ExpectedFail,
    };
    Case {
        id: fx.id.clone(),
        tags: fx.tags.clone(),
        phase: fx.phase,
        outcome,
        millis: started.elapsed().as_millis(),
        diff,
    }
}

/// Check fixtures observed by one `ms check --each` process. Each load of the standard library
/// costs more than checking a fixture, so a batch is a few dozen, small enough to spread over the
/// workers.
const CHECK_BATCH: usize = 24;

/// Cases of `batch`, which are all check fixtures, from one process.
fn check_batch(ctx: &Ctx, batch: &[&Fixture], allow: &ExpectFail) -> Vec<Case> {
    let started = std::time::Instant::now();
    let observed = observe::observe_check_batch(ctx, batch);
    let share = started.elapsed() / batch.len().max(1) as u32;
    batch
        .iter()
        .zip(observed)
        .map(|(fx, actual)| {
            let mut case = judge(fx, allow, std::time::Instant::now(), |_| actual);
            if case.outcome != Outcome::Unrecorded {
                case.millis = share.as_millis();
            }
            case
        })
        .collect()
}

/// Run all selected fixtures. `progress` prints one line per finished fixture to stderr.
pub fn run_all(
    ctx: &Ctx,
    fixtures: &[&Fixture],
    allow: &ExpectFail,
    jobs: usize,
    progress: bool,
) -> Vec<Case> {
    let total = fixtures.len();
    let done = AtomicUsize::new(0);
    let _ = fs::create_dir_all(&ctx.scratch);
    // One work item is a fixture, or a batch of check fixtures; `at` maps its cases back to
    // positions in `fixtures`.
    let mut items: Vec<Vec<usize>> = Vec::new();
    let mut checks: Vec<usize> = Vec::new();
    for (i, fx) in fixtures.iter().enumerate() {
        if fx.phase == Phase::Check {
            checks.push(i);
        } else {
            items.push(vec![i]);
        }
    }
    // A batch is sized so every worker gets some, however few the check fixtures are.
    let size = checks.len().div_ceil(jobs.max(1)).clamp(1, CHECK_BATCH);
    items.extend(checks.chunks(size).map(<[usize]>::to_vec));
    let finished = parallel_map(&items, jobs, |_, at| {
        let cases: Vec<Case> = if fixtures[at[0]].phase == Phase::Check {
            let batch: Vec<&Fixture> = at.iter().map(|&i| fixtures[i]).collect();
            check_batch(ctx, &batch, allow)
        } else {
            vec![check_one(ctx, fixtures[at[0]], allow)]
        };
        for case in &cases {
            let n = done.fetch_add(1, Ordering::SeqCst) + 1;
            if progress && (case.outcome != Outcome::Pass || n.is_multiple_of(50)) {
                eprintln!("[{n}/{total}] {:?} {}", case.outcome, case.id);
            }
        }
        cases
    });
    let mut slots: Vec<Option<Case>> = (0..fixtures.len()).map(|_| None).collect();
    for (at, cases) in items.iter().zip(finished) {
        for (&i, case) in at.iter().zip(cases) {
            slots[i] = Some(case);
        }
    }
    let cases: Vec<Case> = slots
        .into_iter()
        .map(|c| c.expect("every fixture ran"))
        .collect();
    let _ = fs::remove_dir_all(&ctx.scratch);
    cases
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixture::FixtureRoot;
    use std::path::PathBuf;

    fn fx(id: &str, tags: &[&str], phase: Phase) -> Fixture {
        Fixture {
            id: id.into(),
            root: FixtureRoot::File(PathBuf::from("x.ms")),
            tags: tags.iter().map(|t| t.to_string()).collect(),
            phase,
            origin: String::new(),
            args: vec![],
            stdin: vec![],
            timeout_secs: None,
            entry: "x.ms".into(),
            deterministic: false,
            expected_path: PathBuf::from("x.expected.json"),
        }
    }

    #[test]
    fn select_filters_and_shards() {
        let all = vec![
            fx("a/1", &["lists"], Phase::Run),
            fx("a/2", &["maps"], Phase::Run),
            fx("a/3", &["lists"], Phase::Check),
            fx("a/4", &["lists", "faults"], Phase::Run),
        ];
        let f = Filter {
            tags: vec!["lists".into()],
            phases: vec![Phase::Run],
            ..Filter::default()
        };
        let ids: Vec<_> = select(&all, &f).iter().map(|f| f.id.clone()).collect();
        assert_eq!(ids, ["a/1", "a/4"]);
        let f = Filter {
            exclude_tags: vec!["faults".into()],
            shard: Some((1, 2)),
            ..Filter::default()
        };
        let ids: Vec<_> = select(&all, &f).iter().map(|f| f.id.clone()).collect();
        assert_eq!(ids, ["a/2"]);
    }

    #[test]
    fn shards_partition() {
        let all: Vec<_> = (0..10)
            .map(|i| fx(&format!("f/{i}"), &[], Phase::Run))
            .collect();
        let mut seen = 0;
        for n in 0..3 {
            let f = Filter {
                shard: Some((n, 3)),
                ..Filter::default()
            };
            seen += select(&all, &f).len();
        }
        assert_eq!(seen, 10);
    }

    #[test]
    fn expect_fail_patterns() {
        let e = ExpectFail::parse("# c\nx/one\ny/*  # many\n\n");
        assert!(e.contains("x/one"));
        assert!(e.contains("y/deep/two"));
        assert!(!e.contains("x/two"));
    }

    #[test]
    fn parallel_map_keeps_order() {
        let items: Vec<usize> = (0..50).collect();
        let out = parallel_map(&items, 4, |_, n| n * 2);
        assert_eq!(out, (0..50).map(|n| n * 2).collect::<Vec<_>>());
    }
}

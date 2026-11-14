//! `ms test` and `ms bench`. Tests run together in one process; each bench runs in its own.
//!
//! # Tests
//!
//! The lowering builds one executable per `ms test` ([`ms_build::Lower::lower_tests`]) whose
//! entry calls `run_test_files` in `@std/test/runner.ms`: every test file runs at once in its
//! own promise, a file's tests in order around one fixture. `MS_TEST_SELECT` names the test
//! indices to run, `MS_TEST_TIMEOUT_NS` bounds each test's waits, and the harness appends
//! records (start, output, result, fault) to the file `MS_TEST_RESULTS` names; see the
//! runner's doc comment for the format. This side reads them as they arrive, prints each
//! test's output between its `RUN` and result lines in plan order, and stops the process when
//! a test runs past `--timeout` without waiting. A fault ends its file: the running test fails
//! and the file's later tests are not run. A crash fails the running tests and leaves the rest
//! not run. Selection (`--test=`, `--match=`, `--exclude=`, `--filter=`), `--repeat=`,
//! `--shuffle=`, `--fail-fast` and `--timeout=` are applied here.
//!
//! # Benches
//!
//! `exe <index> [program arguments]` runs bench number `index` under the
//! `@std/test/bench.ms` driver, which calibrates, repeats and times the body, reads its
//! settings from `MS_BENCH_TIME_MS`, `MS_BENCH_SAMPLES` and `MS_BENCH_ITERATIONS`, and writes
//! one `MSBENCH {json}` line of per-iteration statistics to standard output; its other output
//! is discarded. Status 1 means the bench returned an error, whose message and source site
//! the process wrote as a [`ms_rt_abi::record::Record`] to the file `MS_FAULT_RECORD` names;
//! any other failing status is described by how the process ended.

use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use ms_build::Lower;
use ms_driver::project::pathops;

use super::{Engine, Target, TempDir, compile_target};
use crate::backend::{BackendResult, Io, TestRequest};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::fault::{EXIT_FAULT, Fault, RecordFile};
use crate::json::Json;
use crate::process::{Stops, wait_supervised};
use crate::profile::base64;
use crate::util::emit_json;
use ms_rt_abi::record::FaultKind;

/// Each test gets this long unless `--timeout` says otherwise.
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

/// Each bench gets this long unless `--timeout` says otherwise: calibration and every sample count.
const DEFAULT_BENCH_TIMEOUT: Duration = Duration::from_secs(600);

/// Written to standard output by the bench driver, ahead of a JSON object of statistics.
const BENCH_MARKER: &str = "MSBENCH ";

#[derive(Debug, Default)]
struct Options {
    names: Vec<String>,
    matching: String,
    exclude: String,
    filter: String,
    list: bool,
    fail_fast: bool,
    repeat: usize,
    shuffle: Option<i64>,
    timeout: Option<Duration>,
    /// Whether `--timeout` was given, so `--fuzz` knows not to replace it.
    timeout_set: bool,
    /// Cases per property (`MS_TEST_RUNS` for `@std/test/property.ms`).
    runs: Option<u64>,
    /// First property case seed (`MS_TEST_SEED`).
    seed: Option<i64>,
    /// Per-property time budget (`MS_TEST_FUZZ_MS`); properties then run until it expires.
    fuzz: Option<Duration>,
    /// Arguments for the programs under test.
    program: Vec<String>,
    /// Running `bench` blocks (`ms bench`) instead of tests.
    bench: bool,
    /// Target duration of one sample (`--time`).
    bench_time: Option<Duration>,
    /// Timed samples per bench (`--samples`).
    bench_samples: Option<u64>,
    /// Fixed iterations per sample (`--iterations`); calibrated when unset.
    bench_iterations: Option<u64>,
}

/// Reads the selection options the CLI forwards; the first unrecognized
/// argument starts the program's own arguments.
fn parse_options(args: &[String]) -> Result<Options, String> {
    let mut options = Options {
        repeat: 1,
        timeout: Some(DEFAULT_TIMEOUT),
        ..Options::default()
    };
    let mut index = 0;
    while index < args.len() {
        let arg = &args[index];
        match arg.as_str() {
            "--" => {
                index += 1;
                break;
            }
            "--list" => options.list = true,
            "--fail-fast" => options.fail_fast = true,
            _ => {
                let Some((name, value)) = arg.split_once('=') else {
                    break;
                };
                match name {
                    "--test" => options.names.push(value.to_string()),
                    "--match" => options.matching = value.to_string(),
                    "--exclude" => options.exclude = value.to_string(),
                    "--filter" => options.filter = value.to_string(),
                    "--repeat" => {
                        options.repeat = value
                            .parse::<usize>()
                            .ok()
                            .filter(|n| *n > 0)
                            .ok_or("invalid --repeat; use a positive integer")?;
                    }
                    "--shuffle" => {
                        options.shuffle = Some(
                            value
                                .parse::<i64>()
                                .map_err(|_| "invalid --shuffle; use an integer seed")?,
                        );
                    }
                    "--runs" => {
                        options.runs = Some(
                            value
                                .parse::<u64>()
                                .ok()
                                .filter(|n| *n > 0)
                                .ok_or("invalid --runs; use a positive integer")?,
                        );
                    }
                    "--seed" => {
                        options.seed = Some(
                            value
                                .parse::<i64>()
                                .map_err(|_| "invalid --seed; use an integer seed")?,
                        );
                    }
                    "--fuzz" => {
                        let nanos = crate::duration::parse(value)
                            .filter(|n| *n > 0)
                            .ok_or_else(|| {
                                format!(
                                    "invalid --fuzz {value:?}; use a positive duration such as 30s or 5m"
                                )
                            })?;
                        options.fuzz =
                            Some(Duration::from_nanos(nanos.min(u64::MAX as i128) as u64));
                    }
                    "--time" => {
                        let nanos = crate::duration::parse(value)
                            .filter(|n| *n >= 1_000_000)
                            .ok_or_else(|| {
                                format!(
                                    "invalid --time {value:?}; use a duration of at least 1ms such as 200ms or 1s"
                                )
                            })?;
                        options.bench_time =
                            Some(Duration::from_nanos(nanos.min(u64::MAX as i128) as u64));
                    }
                    "--samples" => {
                        options.bench_samples = Some(
                            value
                                .parse::<u64>()
                                .ok()
                                .filter(|n| *n > 0)
                                .ok_or("invalid --samples; use a positive integer")?,
                        );
                    }
                    "--iterations" => {
                        options.bench_iterations = Some(
                            value
                                .parse::<u64>()
                                .ok()
                                .filter(|n| *n > 0)
                                .ok_or("invalid --iterations; use a positive integer")?,
                        );
                    }
                    "--timeout" => {
                        options.timeout_set = true;
                        let nanos = crate::duration::parse(value)
                            .filter(|n| *n >= 0)
                            .ok_or_else(|| {
                                format!(
                                    "invalid --timeout {value:?}; use a duration such as 30s or 2m, or 0 to disable"
                                )
                            })?;
                        options.timeout = (nanos > 0)
                            .then(|| Duration::from_nanos(nanos.min(u64::MAX as i128) as u64));
                    }
                    _ => break,
                }
            }
        }
        index += 1;
    }
    for pattern in [&options.matching, &options.exclude] {
        crate::regexp::validate(pattern)?;
    }
    // A fuzz budget applies to every property in a test, so the default limit would cut it short.
    if options.fuzz.is_some() && !options.timeout_set {
        options.timeout = None;
    }
    options.program = args[index..].to_vec();
    Ok(options)
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Status {
    NotRun,
    Passed,
    Failed,
    Skipped,
}

impl Status {
    fn as_str(&self) -> &'static str {
        match self {
            Status::NotRun => "not_run",
            Status::Passed => "passed",
            Status::Failed => "failed",
            Status::Skipped => "skipped",
        }
    }
}

struct Case {
    name: String,
    status: Status,
    failure: String,
    /// Where the failed expectation was built.
    position: Option<Position>,
    fault: Option<Fault>,
    duration: Duration,
    /// The bench driver's statistics (`ms bench`).
    stats: Option<Json>,
}

/// Where the command's own output goes: the terminal, or the `--json` document.
struct Out<'a, 'b> {
    io: &'a mut Io<'b>,
    captured: Option<Vec<u8>>,
}

impl Out<'_, '_> {
    fn write(&mut self, bytes: &[u8]) {
        match &mut self.captured {
            Some(buffer) => buffer.extend_from_slice(bytes),
            None => {
                let _ = self.io.stdout.write_all(bytes);
                let _ = self.io.stdout.flush();
            }
        }
    }

    fn line(&mut self, text: impl AsRef<str>) {
        let mut bytes = text.as_ref().as_bytes().to_vec();
        bytes.push(b'\n');
        self.write(&bytes);
    }
}

pub(super) fn test<L: Lower>(
    syms: ms_syntax::Names,
    backend: &Engine<L>,
    request: &TestRequest,
    io: &mut Io,
) -> BackendResult {
    run(syms, backend, request, io, false)
}

/// `ms bench`: the same run over `bench` blocks; `request.arguments` also carries `--time=`,
/// `--samples=` and `--iterations=`.
pub(super) fn bench<L: Lower>(
    syms: ms_syntax::Names,
    backend: &Engine<L>,
    request: &TestRequest,
    io: &mut Io,
) -> BackendResult {
    run(syms, backend, request, io, true)
}

fn run<L: Lower>(
    syms: ms_syntax::Names,
    backend: &Engine<L>,
    request: &TestRequest,
    io: &mut Io,
    bench: bool,
) -> BackendResult {
    let structured = request.json;
    let mut options = match parse_options(&request.arguments) {
        Ok(options) => options,
        Err(message) => {
            let _ = writeln!(io.stderr, "{message}");
            return Ok(2);
        }
    };
    options.bench = bench;
    if bench && !options.timeout_set {
        options.timeout = Some(DEFAULT_BENCH_TIMEOUT);
    }
    let target = if bench {
        Target::Benches
    } else {
        Target::Tests
    };
    let mut compiled =
        match compile_target(syms, backend, &request.filename, &request.extra, target) {
            Ok(compiled) => compiled,
            Err(failure) => {
                if !structured {
                    return Ok(failure.report(io));
                }
                let mut document = Document::new(&failure.source_root, bench);
                document.reason = Some("compile_error".into());
                document.diagnostics = failure.command_diagnostics();
                return Ok(emit_json(io, &document.to_json(), 1));
            }
        };
    let mut document = Document::new(&compiled.source_root, bench);
    let failed_early = |io: &mut Io, document: &mut Document, phase: &str, message: &str| {
        let _ = writeln!(io.stderr, "{message}");
        if !structured {
            return 1;
        }
        document.reason = Some(format!("{phase}_error"));
        document.diagnostics.push(CommandDiagnostic {
            severity: String::new(),
            code: "MST001".into(),
            phase: phase.into(),
            message: message.into(),
            position: Position::new(&request.filename, 1, 1),
            end: None,
            fix: None,
        });
        emit_json(io, &document.to_json(), 1)
    };
    let directory = match TempDir::create(if bench {
        "manuscript-bench-"
    } else {
        "manuscript-test-"
    }) {
        Ok(directory) => directory,
        Err(error) => {
            return Ok(failed_early(
                io,
                &mut document,
                "execution",
                &error.to_string(),
            ));
        }
    };
    let executable = directory.0.join("program");
    if let Err(message) = backend.link(
        &mut compiled,
        &executable,
        request.build_type,
        &request.link,
    ) {
        return Ok(failed_early(io, &mut document, "build", &message));
    }
    let working = if compiled.project_root.is_empty() {
        pathops::dir(&request.filename)
    } else {
        compiled.project_root.clone()
    };
    let working = pathops::abs(&working).unwrap_or(working);

    let mut runner = Runner {
        executable: &executable,
        working: &working,
        options: &options,
    };
    let available = compiled.tests.clone();
    let mut out = Out {
        io,
        captured: structured.then(Vec::new),
    };
    let status = runner.run_all(&available, &mut document, &mut out);
    let captured = out.captured.take();
    if !structured {
        return Ok(status);
    }
    document.exit_code = status;
    if let Some(bytes) = captured {
        match String::from_utf8(bytes) {
            Ok(text) => document.stdout = text,
            Err(error) => document.stdout_base64 = Some(base64(error.as_bytes())),
        }
    }
    Ok(emit_json(io, &document.to_json(), status))
}

struct Runner<'a> {
    executable: &'a std::path::Path,
    working: &'a str,
    options: &'a Options,
}

impl Runner<'_> {
    fn run_all(&mut self, available: &[String], document: &mut Document, out: &mut Out) -> i32 {
        let options = self.options;
        let (noun, nouns) = if options.bench {
            ("bench", "benches")
        } else {
            ("test", "tests")
        };
        let total = available.len();
        let matching = regex::Regex::new(&options.matching).expect("validated pattern");
        let exclude = regex::Regex::new(&options.exclude).expect("validated pattern");
        // (index in the listing, name), in execution order.
        let mut selected: Vec<(usize, &String)> = Vec::new();
        let mut found = vec![false; options.names.len()];
        for (index, name) in available.iter().enumerate() {
            let mut exact = options.names.is_empty();
            for (n, wanted) in options.names.iter().enumerate() {
                if wanted == name {
                    exact = true;
                    found[n] = true;
                }
            }
            if exact
                && name.contains(&options.filter)
                && matching.is_match(name)
                && (options.exclude.is_empty() || !exclude.is_match(name))
            {
                selected.push((index, name));
            }
        }
        if let Some(position) = found.iter().position(|f| !f) {
            let message = format!(
                "unknown {noun} {}; use --list to find full module::name identities",
                crate::quote(&options.names[position])
            );
            let _ = writeln!(out.io.stderr, "{message}");
            document.reason = Some("no_match".into());
            document.diagnostics.push(CommandDiagnostic {
                severity: String::new(),
                code: "MST001".into(),
                phase: "execution".into(),
                message,
                position: Position::default(),
                end: None,
                fix: None,
            });
            return 1;
        }
        if let Some(seed) = options.shuffle {
            shuffle(&mut selected, seed);
            out.line(format!("shuffle seed: {seed}"));
        }
        let repeat = if options.list { 1 } else { options.repeat };
        let mut plan: Vec<(usize, &String)> = Vec::new();
        for _ in 0..repeat {
            plan.extend(selected.iter().copied());
        }
        document.begin(total, &plan, repeat, options.shuffle);
        let filtered = !options.filter.is_empty()
            || !options.matching.is_empty()
            || !options.exclude.is_empty()
            || !options.names.is_empty();
        if plan.is_empty() && filtered {
            out.line(format!(
                "no {nouns} match selection ({total} {nouns} available); use --list to find full module::name identities"
            ));
            document.finish("no_match", Duration::ZERO);
            return 1;
        }
        if options.list {
            for (_, name) in &plan {
                out.line(name.as_str());
            }
            document.listed = true;
            document.finish("listed", Duration::ZERO);
            return 0;
        }

        let started = Instant::now();
        let mut failed = 0;
        let mut reason = String::new();
        // Tests run together as promises in one process; each bench runs in its own.
        let mut together = if options.bench || plan.is_empty() {
            None
        } else {
            // Each `--repeat` round is one run of the executable, which runs a test once.
            let indices: Vec<usize> = selected.iter().map(|(index, _)| *index).collect();
            let files = file_numbers(available);
            let mut all = self.run_all_together(&indices, &files, out);
            for _ in 1..repeat {
                for (index, mut more) in self.run_all_together(&indices, &files, out) {
                    all.entry(index).or_default().append(&mut more);
                }
            }
            Some(all)
        };
        for (position, (index, name)) in plan.iter().enumerate() {
            out.line(format!("RUN {name}"));
            let began = Instant::now();
            let (result, took) = match together.as_mut() {
                Some(results) => {
                    let (result, took, printed) = results
                        .get_mut(index)
                        .and_then(|queue| queue.pop_front())
                        .unwrap_or((
                            Ran::Failed("the test reported no result".into()),
                            Duration::ZERO,
                            Vec::new(),
                        ));
                    out.write(&printed);
                    (result, took)
                }
                None => {
                    let result = self.run_one(*index, out);
                    (result, began.elapsed())
                }
            };
            let case = &mut document.tests[position];
            case.duration = took;
            match result {
                Ran::Cancelled => {
                    // The interrupted test is not a result; it stays not run.
                    reason = "cancelled".into();
                    break;
                }
                Ran::Passed => {
                    out.line(format!("PASS {name}"));
                    case.status = Status::Passed;
                }
                Ran::NotRun(why) => {
                    out.line(format!("NOT RUN {name}: {why}"));
                    case.failure = why;
                }
                Ran::Measured(stats) => {
                    out.line(format!("BENCH {name}: {}", describe_stats(&stats)));
                    case.status = Status::Passed;
                    case.stats = Some(stats);
                }
                Ran::Skipped(why) => {
                    out.line(format!("SKIP {name}: {why}"));
                    case.status = Status::Skipped;
                    case.failure = why;
                }
                Ran::Faulted(why, fault) => {
                    failed += 1;
                    out.line(format!("FAIL {name}: {why}"));
                    case.status = Status::Failed;
                    case.failure = why;
                    case.fault = Some(fault);
                }
                Ran::Failed(why) => {
                    failed += 1;
                    out.line(format!("FAIL {name}: {why}"));
                    case.status = Status::Failed;
                    case.failure = why;
                }
                Ran::Rejected(why, position) => {
                    failed += 1;
                    out.line(format!("FAIL {name}: {why}"));
                    case.status = Status::Failed;
                    case.failure = why;
                    case.position = position;
                }
            }
            if failed > 0 && options.fail_fast {
                reason = "fail_fast".into();
                break;
            }
        }
        if plan.is_empty() && options.bench {
            out.line("no bench blocks found: add bench blocks to bench.ms or *_bench.ms files in the project, or pass a .ms file");
            reason = "no_benches".into();
        } else if plan.is_empty() {
            out.line("no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a .ms file");
            reason = "no_tests".into();
        }
        let (skipped, not_run) = (
            document.count(Status::Skipped),
            document.count(Status::NotRun),
        );
        let mut summary = format!("{} {nouns}, {failed} failed", plan.len() as i64 - not_run);
        if skipped > 0 {
            summary.push_str(&format!(", {skipped} skipped"));
        }
        if not_run > 0 {
            summary.push_str(&format!(", {not_run} not run"));
        }
        out.line(summary);
        document.finish(&reason, started.elapsed());
        // Failure counts belong in the summary, not the process status: on Unix
        // 256 failed tests would otherwise wrap to a successful exit status.
        i32::from(failed > 0 || reason == "cancelled")
    }

    /// Runs `indices` together; `files[i]` numbers test `i`'s file as the harness does. A
    /// fault ends its file: the test that was running fails with it and the file's later tests
    /// are not run. A test past `--timeout` that never waits stops the process and ends its
    /// file the same way; a crash (stack overflow, abort, signal) ends the files whose tests
    /// were running, since the culprit is not known. The other files' unfinished tests run
    /// again in a new process, on a new fixture.
    fn run_all_together(
        &self,
        indices: &[usize],
        files: &[usize],
        out: &mut Out,
    ) -> std::collections::HashMap<usize, std::collections::VecDeque<Outcome>> {
        let file_of = |index: usize| files.get(index).copied().unwrap_or(usize::MAX);
        let mut all: std::collections::HashMap<usize, std::collections::VecDeque<Outcome>> =
            std::collections::HashMap::new();
        let mut remaining = indices.to_vec();
        while !remaining.is_empty() {
            let mut run = self.run_together(&remaining, out);
            for (index, mut results) in std::mem::take(&mut run.results) {
                all.entry(index).or_default().append(&mut results);
            }
            let crashed = run.timed_out.is_empty();
            // Each ended file's failure, and why its later tests did not run.
            let mut ended: std::collections::HashMap<usize, (String, String)> = run
                .faults
                .iter()
                .map(|(file, why)| {
                    (
                        *file,
                        (why.clone(), "an earlier test in this file faulted".into()),
                    )
                })
                .collect();
            for &index in &remaining {
                if all.contains_key(&index) || ended.contains_key(&file_of(index)) {
                    continue;
                }
                let why = if run.timed_out.contains(&index) {
                    let limit = self.options.timeout.unwrap_or_default();
                    (
                        format!(
                            "timed out after {limit:?}; a test that never waits is stopped with its process"
                        ),
                        "an earlier test in this file timed out".into(),
                    )
                } else if crashed && run.running.contains(&index) {
                    (
                        format!("the test process {} while this test ran", run.ended),
                        format!(
                            "the test process {} while an earlier test in this file ran",
                            run.ended
                        ),
                    )
                } else {
                    continue;
                };
                ended.insert(file_of(index), why);
            }
            let mut next = Vec::new();
            for &index in &remaining {
                if all.contains_key(&index) {
                    continue;
                }
                let file = file_of(index);
                let Some((why, later)) = ended.get(&file) else {
                    next.push(index);
                    continue;
                };
                let (ran, printed) = if !run.started.contains(&index) {
                    (Ran::NotRun(later.clone()), Vec::new())
                } else if run.faults.contains_key(&file) {
                    let ran = match Fault::from_text(why) {
                        Some(fault) => Ran::Faulted(why.clone(), fault),
                        None => Ran::Failed(why.clone()),
                    };
                    (ran, run.fault_outputs.remove(&file).unwrap_or_default())
                } else {
                    (Ran::Failed(why.clone()), Vec::new())
                };
                all.entry(index)
                    .or_default()
                    .push_back((ran, Duration::ZERO, printed));
            }
            if next.len() == remaining.len() {
                // Nothing finished: the process cannot run tests at all.
                for index in next {
                    let why = format!("the test process {} before this test started", run.ended);
                    all.entry(index).or_default().push_back((
                        Ran::Failed(why),
                        Duration::ZERO,
                        Vec::new(),
                    ));
                }
                break;
            }
            remaining = next;
        }
        all
    }

    /// Runs the tests `indices` in one process under the harness in `@std/test/runner.ms`,
    /// reading its records as they arrive. A test with no result past `--timeout` (plus a
    /// second, since the harness fails its next wait at the limit) never waits; the process is
    /// stopped.
    fn run_together(&self, indices: &[usize], out: &mut Out) -> Together {
        let mut run = Together::default();
        let stops = Stops::catch();
        let mut command = Command::new(self.executable);
        let select: Vec<String> = indices.iter().map(|i| i.to_string()).collect();
        let records = TempDir::create("ms-test-results-").ok();
        let records_path = records
            .as_ref()
            .map(|d| d.0.join("results"))
            .unwrap_or_default();
        command
            .env("MS_TEST_SELECT", select.join(","))
            .env("MS_TEST_RESULTS", &records_path)
            .args(&self.options.program)
            .current_dir(self.working);
        if let Some(timeout) = self.options.timeout {
            command.env("MS_TEST_TIMEOUT_NS", timeout.as_nanos().to_string());
        }
        if let Some(runs) = self.options.runs {
            command.env("MS_TEST_RUNS", runs.to_string());
        }
        if let Some(seed) = self.options.seed {
            command.env("MS_TEST_SEED", seed.to_string());
        }
        if let Some(fuzz) = self.options.fuzz {
            command.env("MS_TEST_FUZZ_MS", fuzz.as_millis().to_string());
        }
        let spawned = command
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn();
        let mut child = match spawned {
            Ok(child) => child,
            Err(error) => {
                run.ended = error.to_string();
                return run;
            }
        };
        let stdout = pipe_reader(child.stdout.take().expect("piped stdout"));
        let mut printed: Vec<u8> = Vec::new();
        let limit = self.options.timeout.map(|t| t + Duration::from_secs(1));
        let mut reader = RecordReader::default();
        let waited = wait_supervised(&mut child, &stops, None, &mut || {
            while let Ok(chunk) = stdout.try_recv() {
                printed.extend_from_slice(&chunk);
            }
            reader.read(&records_path, &mut run);
            let Some(limit) = limit else { return false };
            let late: Vec<usize> = reader
                .running
                .iter()
                .filter(|(_, (_, began))| began.elapsed() >= limit)
                .map(|(index, _)| *index)
                .collect();
            run.timed_out.extend(&late);
            !late.is_empty()
        });
        run.ended = match &waited {
            Ok(_) if !run.timed_out.is_empty() => {
                "was stopped because a test timed out".to_string()
            }
            Ok(w) => describe_exit(&w.status),
            Err(error) => error.to_string(),
        };
        while let Ok(chunk) = stdout.recv_timeout(Duration::from_millis(100)) {
            printed.extend_from_slice(&chunk);
        }
        out.write(&printed);
        reader.read(&records_path, &mut run);
        run.running = reader.running.keys().copied().collect();
        run
    }

    /// Run test `index` in its own process.
    fn run_one(&self, index: usize, out: &mut Out) -> Ran {
        let stops = Stops::catch();
        let record = RecordFile::create();
        let mut command = Command::new(self.executable);
        record.attach(&mut command);
        command
            .arg(index.to_string())
            .args(&self.options.program)
            .current_dir(self.working);
        if let Some(runs) = self.options.runs {
            command.env("MS_TEST_RUNS", runs.to_string());
        }
        if let Some(seed) = self.options.seed {
            command.env("MS_TEST_SEED", seed.to_string());
        }
        if let Some(fuzz) = self.options.fuzz {
            command.env("MS_TEST_FUZZ_MS", fuzz.as_millis().to_string());
        }
        if let Some(time) = self.options.bench_time {
            command.env("MS_BENCH_TIME_MS", time.as_millis().to_string());
        }
        if let Some(samples) = self.options.bench_samples {
            command.env("MS_BENCH_SAMPLES", samples.to_string());
        }
        if let Some(iterations) = self.options.bench_iterations {
            command.env("MS_BENCH_ITERATIONS", iterations.to_string());
        }
        // A bench's own output would repeat once per iteration; only its statistics are kept.
        let mut printed: Vec<u8> = Vec::new();
        let spawned = command
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let mut child = match spawned {
            Ok(child) => child,
            Err(error) => return Ran::Failed(error.to_string()),
        };
        let stdout = pipe_reader(child.stdout.take().expect("piped stdout"));
        let stderr = pipe_reader(child.stderr.take().expect("piped stderr"));
        let mut errors: Vec<u8> = Vec::new();
        let bench = self.options.bench;
        let waited = wait_supervised(&mut child, &stops, self.options.timeout, &mut || {
            while let Ok(chunk) = stdout.try_recv() {
                if bench {
                    printed.extend_from_slice(&chunk);
                } else {
                    out.write(&chunk);
                }
            }
            while let Ok(chunk) = stderr.try_recv() {
                errors.extend_from_slice(&chunk);
            }
            false
        });
        // Output written just before exit; a silent pipe held open elsewhere ends the wait.
        while let Ok(chunk) = stdout.recv_timeout(Duration::from_millis(100)) {
            if bench {
                printed.extend_from_slice(&chunk);
            } else {
                out.write(&chunk);
            }
        }
        while let Ok(chunk) = stderr.recv_timeout(Duration::from_millis(100)) {
            errors.extend_from_slice(&chunk);
        }
        let pid = child.id();
        let waited = match waited {
            Ok(waited) => waited,
            Err(error) => return Ran::Failed(error.to_string()),
        };
        if waited.timed_out {
            let limit = self.options.timeout.unwrap_or_default();
            return Ran::Failed(format!(
                "timed out after {:?}; the test was cancelled (use --timeout to change the limit, 0 disables it)",
                limit
            ));
        }
        if waited.interrupted {
            return Ran::Cancelled;
        }
        let errors = String::from_utf8_lossy(&errors).into_owned();
        let written = record.read(pid);
        if let Some(failure) = written
            .as_ref()
            .filter(|r| r.kind == FaultKind::TestFailure)
        {
            // The expectation's message and site are in the record; standard error repeats them.
            let message = String::from_utf8_lossy(&failure.message).into_owned();
            let site = failure
                .site
                .as_deref()
                .map(|site| String::from_utf8_lossy(site).into_owned());
            let shown = match &site {
                Some(site) => format!("{message}\n  at {site}"),
                None => message,
            };
            let echoed = errors.trim_end_matches('\n').strip_suffix(&shown);
            let _ = out
                .io
                .stderr
                .write_all(echoed.unwrap_or_default().as_bytes());
            let position = site.as_deref().and_then(position_of_site);
            return Ran::Rejected(shown, position);
        }
        if waited.status.success() {
            let _ = out.io.stderr.write_all(errors.as_bytes());
            if bench {
                return match measurement(&printed) {
                    Some(stats) => Ran::Measured(stats),
                    None => Ran::Failed("the bench reported no statistics".into()),
                };
            }
            return Ran::Passed;
        }
        let text = errors.trim_end_matches('\n');
        if waited.status.code() == Some(EXIT_FAULT)
            && let Some(fault) = written
                .map(Fault::from_record)
                .or_else(|| Fault::from_text(text))
        {
            return Ran::Faulted(text.to_string(), fault);
        }
        if text.is_empty() {
            Ran::Failed(format!("test process {}", describe_exit(&waited.status)))
        } else {
            Ran::Failed(text.to_string())
        }
    }
}

/// A test's result, how long it ran, and its standard output.
type Outcome = (Ran, Duration, Vec<u8>);

/// What one run of the test executable reported.
#[derive(Default)]
struct Together {
    /// Each test's results, in completion order.
    results: std::collections::HashMap<usize, std::collections::VecDeque<Outcome>>,
    /// Tests that started.
    started: std::collections::HashSet<usize>,
    /// Files whose test faulted, by the harness's file number, with the fault message.
    faults: std::collections::HashMap<usize, String>,
    /// Each test's standard output, in completion order, before its result.
    outputs: std::collections::HashMap<usize, std::collections::VecDeque<Vec<u8>>>,
    /// A faulted file's output since its last result.
    fault_outputs: std::collections::HashMap<usize, Vec<u8>>,
    /// Tests that had started and not reported when the process ended.
    running: std::collections::HashSet<usize>,
    /// Tests stopped with the process for running past `--timeout`.
    timed_out: std::collections::HashSet<usize>,
    /// How the process ended.
    ended: String,
}

/// Reads the harness's records from the results file as they are appended.
#[derive(Default)]
struct RecordReader {
    /// Bytes of the file already read.
    offset: u64,
    /// Read bytes not yet a whole record.
    pending: Vec<u8>,
    /// Tests started and not yet reported, with when the host saw them start.
    running: std::collections::HashMap<usize, (usize, Instant)>,
}

impl RecordReader {
    /// Reads what the file gained since the last call into `run`.
    fn read(&mut self, path: &std::path::Path, run: &mut Together) {
        use std::io::{Seek, SeekFrom};
        let Ok(mut file) = std::fs::File::open(path) else {
            return;
        };
        if file.seek(SeekFrom::Start(self.offset)).is_err() {
            return;
        }
        let before = self.pending.len();
        if file.read_to_end(&mut self.pending).is_err() {
            return;
        }
        self.offset += (self.pending.len() - before) as u64;
        let used = self.parse(run);
        self.pending.drain(..used);
    }

    /// Takes the whole records at the start of `pending`; returns the bytes they used.
    fn parse(&mut self, run: &mut Together) -> usize {
        let mut at = 0;
        while let Some(end) = self.pending[at..].iter().position(|&b| b == b'\n') {
            let line = String::from_utf8_lossy(&self.pending[at..at + end]).into_owned();
            let mut next = at + end + 1;
            if let Some(rest) = line.strip_prefix("\u{1}MSOUT ") {
                let (key, size) = rest.split_once(' ').unwrap_or((rest, "0"));
                let size = size.parse::<usize>().unwrap_or(0);
                if self.pending.len() < next + size + 1 {
                    break;
                }
                let printed = self.pending[next..next + size].to_vec();
                next += size + 1;
                if let Some(file) = key.strip_prefix('f').and_then(|f| f.parse().ok()) {
                    run.fault_outputs.insert(file, printed);
                } else if let Ok(index) = key.parse() {
                    run.outputs.entry(index).or_default().push_back(printed);
                }
            } else if let Some(rest) = line.strip_prefix("\u{1}MSSTART ") {
                let mut words = rest.split(' ').map(|w| w.parse::<usize>().ok());
                if let (Some(Some(index)), Some(Some(file))) = (words.next(), words.next()) {
                    run.started.insert(index);
                    self.running.insert(index, (file, Instant::now()));
                }
            } else if let Some(rest) = line.strip_prefix("\u{1}MSFAULT ") {
                let (file, message) = rest.split_once('\u{1}').unwrap_or((rest, ""));
                if let Ok(file) = file.parse::<usize>() {
                    run.faults.insert(file, message.replace('\u{2}', "\n"));
                    // The faulted file's test is no longer running.
                    self.running.retain(|_, (of, _)| *of != file);
                }
            } else if let Some(rest) = line.strip_prefix("\u{1}MSTEST ") {
                let (index, outcome) = parse_result(rest, run);
                self.running.remove(&index);
                run.results.entry(index).or_default().push_back(outcome);
            }
            at = next;
        }
        at
    }
}

/// A `MSTEST` record's test index and outcome, with the output recorded before it.
fn parse_result(rest: &str, run: &mut Together) -> (usize, Outcome) {
    let mut fields = rest.splitn(3, '\u{1}');
    let head = fields.next().unwrap_or_default();
    let message = fields.next().unwrap_or_default().to_string();
    let site = fields.next().unwrap_or_default().to_string();
    let mut words = head.split(' ');
    let index: usize = words
        .next()
        .and_then(|w| w.parse().ok())
        .unwrap_or(usize::MAX);
    let status = words.next().unwrap_or_default();
    let nanos: u64 = words.next().and_then(|w| w.parse().ok()).unwrap_or(0);
    let ran = match status {
        "pass" => Ran::Passed,
        "skip" => Ran::Skipped(message),
        _ if site.is_empty() => Ran::Failed(message),
        _ => Ran::Rejected(format!("{message}\n  at {site}"), position_of_site(&site)),
    };
    let printed = run
        .outputs
        .get_mut(&index)
        .and_then(|q| q.pop_front())
        .unwrap_or_default();
    (index, (ran, Duration::from_nanos(nanos), printed))
}

/// The harness's file number of each test: files numbered in order of their first test, as
/// lowering groups them; a name is `file::test`.
fn file_numbers(names: &[String]) -> Vec<usize> {
    let mut seen: Vec<&str> = Vec::new();
    names
        .iter()
        .map(|name| {
            let file = name.split_once("::").map_or(name.as_str(), |(f, _)| f);
            match seen.iter().position(|f| *f == file) {
                Some(at) => at,
                None => {
                    seen.push(file);
                    seen.len() - 1
                }
            }
        })
        .collect()
}

/// The statistics object of the `MSBENCH` line a bench driver wrote.
fn measurement(printed: &[u8]) -> Option<Json> {
    let text = String::from_utf8_lossy(printed);
    let line = text
        .lines()
        .rev()
        .find_map(|l| l.strip_prefix(BENCH_MARKER))?;
    crate::json::parse(line).ok()
}

/// A duration given in nanoseconds with a fitting unit: `12.3 ns`, `4.56 µs`, `7.89 ms`, `1.23 s`.
fn format_ns(nanos: f64) -> String {
    let (value, unit) = match nanos {
        n if n < 1e3 => (n, "ns"),
        n if n < 1e6 => (n / 1e3, "µs"),
        n if n < 1e9 => (n / 1e6, "ms"),
        n => (n / 1e9, "s"),
    };
    format!("{value:.3} {unit}")
}

/// The one-line summary of a bench's statistics.
fn describe_stats(stats: &Json) -> String {
    let number = |key: &str| match stats.get(key) {
        Some(Json::Num(text)) => text.parse::<f64>().unwrap_or(f64::NAN),
        _ => f64::NAN,
    };
    let count = |key: &str| stats.get(key).and_then(Json::as_i64).unwrap_or(0);
    format!(
        "{}/op median (min {}, mean {}, max {}, stddev {}; {} iterations x {} samples)",
        format_ns(number("median_ns")),
        format_ns(number("min_ns")),
        format_ns(number("mean_ns")),
        format_ns(number("max_ns")),
        format_ns(number("stddev_ns")),
        count("iterations"),
        count("samples"),
    )
}

/// Streams a child's pipe through a channel. The thread is detached: a
/// grandchild that inherits the pipe must not hold the run up.
pub(super) fn pipe_reader(mut pipe: impl Read + Send + 'static) -> mpsc::Receiver<Vec<u8>> {
    let (sender, receiver) = mpsc::channel::<Vec<u8>>();
    std::thread::spawn(move || {
        let mut buffer = [0u8; 8192];
        while let Ok(n) = pipe.read(&mut buffer) {
            if n == 0 || sender.send(buffer[..n].to_vec()).is_err() {
                break;
            }
        }
    });
    receiver
}

enum Ran {
    Passed,
    /// An earlier test of the same file faulted, which ended the file.
    NotRun(String),
    Skipped(String),
    Failed(String),
    /// An expectation failed: its message with the site appended, and the site as a position.
    Rejected(String, Option<Position>),
    /// The test process ended in a runtime fault: the report text and its parse.
    Faulted(String, Fault),
    Cancelled,
    /// A bench finished and reported these statistics.
    Measured(Json),
}

fn describe_exit(status: &std::process::ExitStatus) -> String {
    if let Some(code) = status.code() {
        return format!("exited with status {code}");
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            return format!("was terminated by signal {signal}");
        }
    }
    "ended abnormally".to_string()
}

/// Seeded Fisher-Yates. The permutation for a seed differs from Go's.
fn shuffle<T>(items: &mut [T], seed: i64) {
    let mut state = seed as u64 ^ 0x9E37_79B9_7F4A_7C15;
    let mut next = move || {
        state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    };
    for i in (1..items.len()).rev() {
        items.swap(i, (next() % (i as u64 + 1)) as usize);
    }
}

/// The position of a failed expectation's `file:line:column` site, split from the right because
/// file names may hold colons.
fn position_of_site(site: &str) -> Option<Position> {
    let (rest, column) = site.rsplit_once(':')?;
    let (file, line) = rest.rsplit_once(':')?;
    Some(Position::new(
        file,
        line.parse().ok()?,
        column.parse().ok()?,
    ))
}

/// The `--json` document of `ms test`.
struct Document {
    /// A bench run: the cases are listed under `benches`.
    bench: bool,
    listed: bool,
    repeat: usize,
    shuffle_seed: Option<i64>,
    source_root: String,
    tests: Vec<Case>,
    available: usize,
    completed: bool,
    exit_code: i32,
    reason: Option<String>,
    duration: Duration,
    stdout: String,
    stdout_base64: Option<String>,
    diagnostics: Vec<CommandDiagnostic>,
}

impl Document {
    fn new(source_root: &str, bench: bool) -> Document {
        Document {
            bench,
            listed: false,
            repeat: 0,
            shuffle_seed: None,
            source_root: source_root.to_string(),
            tests: Vec::new(),
            available: 0,
            completed: false,
            exit_code: 1,
            reason: None,
            duration: Duration::ZERO,
            stdout: String::new(),
            stdout_base64: None,
            diagnostics: Vec::new(),
        }
    }

    fn begin(
        &mut self,
        available: usize,
        plan: &[(usize, &String)],
        repeat: usize,
        shuffle: Option<i64>,
    ) {
        self.available = available;
        self.repeat = repeat;
        self.shuffle_seed = shuffle;
        self.tests = plan
            .iter()
            .map(|(_, name)| Case {
                name: (*name).clone(),
                status: Status::NotRun,
                failure: String::new(),
                position: None,
                fault: None,
                duration: Duration::ZERO,
                stats: None,
            })
            .collect();
    }

    fn finish(&mut self, reason: &str, duration: Duration) {
        self.completed = true;
        self.reason = (!reason.is_empty()).then(|| reason.to_string());
        self.duration = duration;
    }

    fn count(&self, status: Status) -> i64 {
        self.tests.iter().filter(|t| t.status == status).count() as i64
    }

    fn to_json(&self) -> Json {
        let mut document = Json::object();
        if self.listed {
            document = document.with("listed", Json::Bool(true));
        }
        if self.repeat > 0 {
            document = document.with("repeat", Json::int(self.repeat as i64));
        }
        if let Some(seed) = self.shuffle_seed {
            document = document.with("shuffle_seed", Json::int(seed));
        }
        let tests = self
            .tests
            .iter()
            .enumerate()
            .map(|(index, case)| {
                let mut item = Json::object()
                    .with("index", Json::int(index as i64))
                    .with("duration_ns", Json::int(case.duration.as_nanos() as i64))
                    .with("name", Json::str(&case.name))
                    .with("status", Json::str(case.status.as_str()));
                if !case.failure.is_empty() {
                    item = item.with("failure", Json::str(&case.failure));
                    if let Some(position) = &case.position {
                        item = item.with("position", position.to_json());
                    }
                }
                if let Some(fault) = &case.fault {
                    item = item.with("fault", fault.to_json());
                }
                if let Some(stats) = &case.stats {
                    item = item.with("stats", stats.clone());
                }
                item
            })
            .collect();
        let finished =
            self.count(Status::Passed) + self.count(Status::Failed) + self.count(Status::Skipped);
        let not_run = if self.completed {
            self.tests.len() as i64 - finished
        } else {
            0
        };
        document = document
            .with("format", Json::int(1))
            .with("source_root", Json::str(&self.source_root))
            .with(
                if self.bench { "benches" } else { "tests" },
                Json::Arr(tests),
            )
            .with(
                "summary",
                Json::object()
                    .with("available", Json::int(self.available as i64))
                    .with("selected", Json::int(self.tests.len() as i64))
                    .with("passed", Json::int(self.count(Status::Passed)))
                    .with("failed", Json::int(self.count(Status::Failed)))
                    .with("skipped", Json::int(self.count(Status::Skipped)))
                    .with("not_run", Json::int(not_run))
                    .with("duration_ns", Json::int(self.duration.as_nanos() as i64)),
            )
            .with("completed", Json::Bool(self.completed))
            .with("exit_code", Json::int(i64::from(self.exit_code)));
        if let Some(reason) = &self.reason {
            document = document.with("reason", Json::str(reason));
        }
        document = document.with("stdout", Json::str(&self.stdout));
        if let Some(encoded) = &self.stdout_base64 {
            document = document.with("stdout_base64", Json::str(encoded));
        }
        document.with(
            "diagnostics",
            Json::Arr(
                self.diagnostics
                    .iter()
                    .map(CommandDiagnostic::to_json)
                    .collect(),
            ),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn selection_then_program_arguments() {
        let options = parse_options(&args(&[
            "--test=a::b",
            "--fail-fast",
            "--repeat=3",
            "--timeout=2s",
            "x",
            "--list",
        ]))
        .unwrap();
        assert_eq!(options.names, ["a::b"]);
        assert!(options.fail_fast && !options.list);
        assert_eq!(options.repeat, 3);
        assert_eq!(options.timeout, Some(Duration::from_secs(2)));
        assert_eq!(options.program, ["x", "--list"]);
    }

    #[test]
    fn property_options_are_read_and_fuzz_replaces_the_default_timeout() {
        let options = parse_options(&args(&["--runs=500", "--seed=-7", "--fuzz=30s"])).unwrap();
        assert_eq!(options.runs, Some(500));
        assert_eq!(options.seed, Some(-7));
        assert_eq!(options.fuzz, Some(Duration::from_secs(30)));
        assert_eq!(options.timeout, None);
        let explicit = parse_options(&args(&["--fuzz=30s", "--timeout=5m"])).unwrap();
        assert_eq!(explicit.timeout, Some(Duration::from_secs(300)));
        assert!(parse_options(&args(&["--runs=0"])).is_err());
        assert!(parse_options(&args(&["--seed=x"])).is_err());
        assert!(parse_options(&args(&["--fuzz=0s"])).is_err());
    }

    #[test]
    fn zero_timeout_disables_the_limit() {
        assert_eq!(
            parse_options(&args(&["--timeout=0"])).unwrap().timeout,
            None
        );
        assert!(parse_options(&args(&["--repeat=0"])).is_err());
        assert!(parse_options(&args(&["--match=("])).is_err());
    }

    #[test]
    fn duration_options_keep_exact_nanoseconds() {
        let options = parse_options(&args(&[
            "--timeout=1.5ns2.5ns",
            "--fuzz=0.999999999999999999h",
            "--time=1.999999999999999999ms",
        ]))
        .unwrap();
        assert_eq!(options.timeout, Some(Duration::from_nanos(3)));
        assert_eq!(options.fuzz, Some(Duration::from_nanos(3_599_999_999_999)));
        assert_eq!(options.bench_time, Some(Duration::from_nanos(1_999_999)));
    }

    #[test]
    fn separator_preserves_program_options() {
        let options =
            parse_options(&args(&["--repeat=2", "--", "--list", "--repeat=3", "--"])).unwrap();
        assert_eq!(options.repeat, 2);
        assert!(!options.list);
        assert_eq!(options.program, ["--list", "--repeat=3", "--"]);
    }

    #[test]
    fn shuffle_is_a_seeded_permutation() {
        let mut a: Vec<u32> = (0..10).collect();
        let mut b = a.clone();
        shuffle(&mut a, 7);
        shuffle(&mut b, 7);
        assert_eq!(a, b);
        let mut sorted = a.clone();
        sorted.sort();
        assert_eq!(sorted, (0..10).collect::<Vec<u32>>());
    }

    #[test]
    fn failure_sites() {
        let position = position_of_site("src/a.ms:12:5").unwrap();
        assert_eq!(
            (position.file.as_str(), position.line, position.column),
            ("src/a.ms", 12, 5)
        );
        let position = position_of_site("C:\\w\\a.ms:3:9").unwrap();
        assert_eq!(position.file, "C:\\w\\a.ms");
        assert!(position_of_site("no location").is_none());
    }

    #[cfg(unix)]
    const NAMES: [&str; 4] = ["a::pass", "b::fail", "c::crash", "d::hang"];

    /// A shell script that speaks the test harness's record protocol; each test is its own file.
    #[cfg(unix)]
    fn script(dir: &std::path::Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let path = dir.join("program");
        let text = r#"#!/bin/sh
r="$MS_TEST_RESULTS"
IFS=,
for i in $MS_TEST_SELECT; do
  printf '\001MSSTART %s %s\n' "$i" "$i" >> "$r"
  case $i in
  0) printf '\001MSOUT 0 16\nhello from pass\n\n' >> "$r"; echo note >&2
     printf '\001MSTEST 0 pass 1000\001\001\n' >> "$r";;
  1) printf '\001MSTEST 1 fail 1000\001boom\001src/a.ms:3:4\n' >> "$r";;
  2) ulimit -c 0; kill -SEGV $$;;
  3) sleep 30;;
  4) printf '\001MSTEST 4 skip 1000\001not today\001\n' >> "$r";;
  esac
done
"#;
        std::fs::write(&path, text).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        // A process another test thread forked while the file was open for writing still holds
        // it until that child execs, and executing the file then fails with ETXTBSY (os error
        // 26). Wait that out so the tests under this directory never see it.
        for _ in 0..1000 {
            match std::process::Command::new(&path).arg("9").status() {
                Err(e) if e.raw_os_error() == Some(26) => {
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
                _ => break,
            }
        }
        path
    }

    #[cfg(unix)]
    fn run_script(arguments: &[&str]) -> (i32, String, Document) {
        run_names(arguments, &NAMES)
    }

    #[cfg(unix)]
    fn run_names(arguments: &[&str], names: &[&str]) -> (i32, String, Document) {
        let directory = TempDir::create("ms-tests-unit-").unwrap();
        let executable = script(&directory.0);
        let options = parse_options(&args(arguments)).unwrap();
        let mut runner = Runner {
            executable: &executable,
            working: "/",
            options: &options,
        };
        let available: Vec<String> = names.iter().map(|n| n.to_string()).collect();
        let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
        let mut input: &[u8] = &[];
        let mut io = Io {
            stdin: &mut input,
            stdout: &mut stdout,
            stderr: &mut stderr,
        };
        let mut document = Document::new("", false);
        let mut out = Out {
            io: &mut io,
            captured: Some(Vec::new()),
        };
        let status = runner.run_all(&available, &mut document, &mut out);
        let text = String::from_utf8(out.captured.take().unwrap()).unwrap();
        (status, text, document)
    }

    #[cfg(unix)]
    #[test]
    fn crashes_and_timeouts_fail_only_their_tests() {
        let (status, text, document) = run_script(&["--timeout=1s"]);
        assert_eq!(status, 1, "failed + crashed + timed out: {text}");
        let expected = [
            "RUN a::pass\nhello from pass\nPASS a::pass\n",
            "RUN b::fail\nFAIL b::fail: boom\n  at src/a.ms:3:4\n",
            "RUN c::crash\nFAIL c::crash: the test process was terminated by signal 11 while this test ran\n",
            "RUN d::hang\nFAIL d::hang: timed out after 1s; a test that never waits is stopped with its process\n",
            "4 tests, 3 failed\n",
        ];
        assert_eq!(text, expected.concat());
        let statuses: Vec<_> = document.tests.iter().map(|t| t.status.as_str()).collect();
        assert_eq!(statuses, ["passed", "failed", "failed", "failed"]);
        assert_eq!(document.count(Status::Failed), 3);
        let json = document.to_json().pretty_line(ms_json::Escape::HtmlSafe);
        assert!(json.contains("\"position\""), "{json}");
    }

    #[cfg(unix)]
    #[test]
    fn failure_count_cannot_wrap_to_a_successful_exit() {
        let (status, text, document) = run_script(&["--test=b::fail", "--repeat=256"]);
        assert_eq!(status, 1, "256 failures must not become exit status zero");
        assert_eq!(document.count(Status::Failed), 256);
        assert!(text.ends_with("256 tests, 256 failed\n"), "{text}");
    }

    #[cfg(unix)]
    #[test]
    fn a_skipping_test_is_reported_skipped() {
        let names = ["a::pass", "b::fail", "c::crash", "d::hang", "e::skip"];
        let (status, text, document) = run_names(&["--test=a::pass", "--test=e::skip"], &names);
        assert_eq!(status, 0, "{text}");
        let expected = [
            "RUN a::pass\nhello from pass\nPASS a::pass\n",
            "RUN e::skip\nSKIP e::skip: not today\n",
            "2 tests, 0 failed, 1 skipped\n",
        ];
        assert_eq!(text, expected.concat());
        let json = document.to_json().pretty_line(ms_json::Escape::HtmlSafe);
        assert!(json.contains("\"status\": \"skipped\""), "{json}");
        assert!(json.contains("\"skipped\": 1"), "{json}");
        assert!(json.contains("\"not_run\": 0"), "{json}");
    }

    #[cfg(unix)]
    #[test]
    fn selection_listing_and_fail_fast() {
        let (status, text, _) = run_script(&["--list", "--match=pass|fail"]);
        assert_eq!((status, text.as_str()), (0, "a::pass\nb::fail\n"));

        let (status, text, document) = run_script(&["--fail-fast", "--timeout=1s"]);
        assert_eq!(status, 1);
        assert!(text.ends_with("2 tests, 1 failed, 2 not run\n"), "{text}");
        assert_eq!(document.reason.as_deref(), Some("fail_fast"));
        assert_eq!(document.tests.len(), 4);
        assert_eq!(document.tests[2].status, Status::NotRun);

        let (status, text, _) = run_script(&["--test=z::missing"]);
        assert_eq!((status, text.as_str()), (1, ""));

        let (status, text, _) = run_script(&["--filter=zzz"]);
        assert_eq!(status, 1);
        assert!(
            text.starts_with("no tests match selection (4 tests available)"),
            "{text}"
        );

        let (status, text, _) = run_script(&["--test=a::pass", "--repeat=2"]);
        assert_eq!(status, 0);
        assert!(text.ends_with("2 tests, 0 failed\n"), "{text}");
    }
}

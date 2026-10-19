//! `ms test`: every test runs in its own process, so a fault, abort or hang
//! fails only that test.
//!
//! # The test executable protocol
//!
//! The lowering builds one executable per `ms test` ([`ms_driver::Lower::lower_tests`])
//! and returns the test names in index order. `exe <index> [program arguments]`
//! runs test number `index` and exits: status 0 means passed; status 1 with
//! the failure marker (`ms_lower::FAILURE_MARKER`) on standard error means
//! the test returned an error, and the text after the marker is the message;
//! any other status (a fault, abort or signal) is a failure described by how
//! the process ended, with its standard error text after the marker-free part.
//! `skip` ends the test with status 0 after writing [`SKIP_MARKER`] and the
//! reason to standard error; the test is reported skipped, not passed.
//!
//! The test's standard output goes to the command's standard output between
//! its `RUN` and result lines; standard error passes through. Selection
//! (`--test=`, `--match=`, `--exclude=`, `--filter=`), `--repeat=`,
//! `--shuffle=`, `--fail-fast` and `--timeout=` are applied here. Fixtures
//! therefore run once per test, not once per module as in the Go
//! implementation.

use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use ms_driver::Lower;
use ms_project::gopath;

use ms_lower::FAILURE_MARKER;

/// Written to standard error, ahead of the reason, by a test that skips itself and exits 0.
pub const SKIP_MARKER: &str = "\u{1}SKIP\u{1}";

use super::{RustBackend, TempDir, compile};
use crate::backend::{BackendResult, Io, TestRequest};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::json::Json;
use crate::process::wait_supervised;
use crate::profile::base64;
use crate::util::emit_json;

/// Each test gets this long unless `--timeout` says otherwise.
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

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
    /// Arguments for the programs under test.
    program: Vec<String>,
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
                    "--timeout" => {
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
    duration: Duration,
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
    backend: &RustBackend<L>,
    request: &TestRequest,
    io: &mut Io,
) -> BackendResult {
    let structured = request.json;
    let options = match parse_options(&request.arguments) {
        Ok(options) => options,
        Err(message) => {
            let _ = writeln!(io.stderr, "{message}");
            return Ok(2);
        }
    };
    let mut compiled = match compile(backend, &request.filename, request.build_type, true) {
        Ok(compiled) => compiled,
        Err(failure) => {
            if !structured {
                return Ok(failure.report(io));
            }
            let mut document = Document::new(&failure.source_root);
            document.reason = Some("compile_error".into());
            document.diagnostics = failure.command_diagnostics();
            return Ok(emit_json(io, &document.to_json(), 1));
        }
    };
    let mut document = Document::new(&compiled.source_root);
    let failed_early = |io: &mut Io, document: &mut Document, phase: &str, message: &str| {
        let _ = writeln!(io.stderr, "{message}");
        if !structured {
            return 1;
        }
        document.reason = Some(format!("{phase}_error"));
        document.diagnostics.push(CommandDiagnostic {
            code: "MST001".into(),
            phase: phase.into(),
            message: message.into(),
            position: Position::new(&request.filename, 1, 1),
            end: None,
            fix: None,
        });
        emit_json(io, &document.to_json(), 1)
    };
    let directory = match TempDir::create("manuscript-test-") {
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
    if let Err(message) = backend.link(&mut compiled, &executable, request.build_type) {
        return Ok(failed_early(io, &mut document, "build", &message));
    }
    let working = if compiled.project_root.is_empty() {
        gopath::dir(&request.filename)
    } else {
        compiled.project_root.clone()
    };
    let working = gopath::abs(&working).unwrap_or(working);

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
                "unknown test {}; use --list to find full module::name identities",
                crate::quote(&options.names[position])
            );
            let _ = writeln!(out.io.stderr, "{message}");
            document.reason = Some("no_match".into());
            document.diagnostics.push(CommandDiagnostic {
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
                "no tests match selection ({total} tests available); use --list to find full module::name identities"
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
        for (position, (index, name)) in plan.iter().enumerate() {
            out.line(format!("RUN {name}"));
            let began = Instant::now();
            let result = self.run_one(*index, out);
            let case = &mut document.tests[position];
            case.duration = began.elapsed();
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
                Ran::Skipped(why) => {
                    out.line(format!("SKIP {name}: {why}"));
                    case.status = Status::Skipped;
                    case.failure = why;
                }
                Ran::Failed(why) => {
                    failed += 1;
                    out.line(format!("FAIL {name}: {why}"));
                    case.status = Status::Failed;
                    case.failure = why;
                }
            }
            if failed > 0 && options.fail_fast {
                reason = "fail_fast".into();
                break;
            }
        }
        if plan.is_empty() {
            out.line("no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a .ms file");
            reason = "no_tests".into();
        }
        let skipped = document.count(Status::Skipped);
        if skipped > 0 {
            out.line(format!(
                "{} tests, {failed} failed, {skipped} skipped",
                plan.len()
            ));
        } else {
            out.line(format!("{} tests, {failed} failed", plan.len()));
        }
        document.finish(&reason, started.elapsed());
        if reason == "cancelled" && failed == 0 {
            1
        } else {
            failed
        }
    }

    /// Run test `index` in its own process.
    fn run_one(&self, index: usize, out: &mut Out) -> Ran {
        let spawned = Command::new(self.executable)
            .arg(index.to_string())
            .args(&self.options.program)
            .current_dir(self.working)
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
        let waited = wait_supervised(&mut child, self.options.timeout, &mut || {
            while let Ok(chunk) = stdout.try_recv() {
                out.write(&chunk);
            }
            while let Ok(chunk) = stderr.try_recv() {
                errors.extend_from_slice(&chunk);
            }
        });
        // Output written just before exit; a silent pipe held open elsewhere ends the wait.
        while let Ok(chunk) = stdout.recv_timeout(Duration::from_millis(100)) {
            out.write(&chunk);
        }
        while let Ok(chunk) = stderr.recv_timeout(Duration::from_millis(100)) {
            errors.extend_from_slice(&chunk);
        }
        let waited = match waited {
            Ok(waited) => waited,
            Err(error) => return Ran::Failed(error.to_string()),
        };
        if waited.timed_out {
            let limit = self.options.timeout.unwrap_or_default();
            return Ran::Failed(format!(
                "timed out after {}; the test was cancelled (use --timeout to change the limit, 0 disables it)",
                go_duration(limit)
            ));
        }
        if waited.interrupted {
            return Ran::Cancelled;
        }
        let errors = String::from_utf8_lossy(&errors).into_owned();
        if let Some((before, message)) = errors.split_once(FAILURE_MARKER) {
            let _ = out.io.stderr.write_all(before.as_bytes());
            return Ran::Failed(message.trim_end_matches('\n').to_string());
        }
        if waited.status.success() {
            if let Some((before, reason)) = errors.split_once(SKIP_MARKER) {
                let _ = out.io.stderr.write_all(before.as_bytes());
                return Ran::Skipped(reason.trim_end_matches('\n').to_string());
            }
            let _ = out.io.stderr.write_all(errors.as_bytes());
            return Ran::Passed;
        }
        let text = errors.trim_end_matches('\n');
        if text.is_empty() {
            Ran::Failed(format!("test process {}", describe_exit(&waited.status)))
        } else {
            Ran::Failed(text.to_string())
        }
    }
}

/// Streams a child's pipe through a channel. The thread is detached: a
/// grandchild that inherits the pipe must not hold the run up.
fn pipe_reader(mut pipe: impl Read + Send + 'static) -> mpsc::Receiver<Vec<u8>> {
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
    Skipped(String),
    Failed(String),
    Cancelled,
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

/// Go's `time.Duration.String` for the whole-second limits `--timeout` takes.
fn go_duration(limit: Duration) -> String {
    let nanos = limit.as_nanos();
    if nanos >= 1_000_000_000 {
        let seconds = limit.as_secs();
        let fraction = limit.subsec_nanos();
        let (hours, minutes, seconds) = (seconds / 3600, seconds / 60 % 60, seconds % 60);
        let mut text = String::new();
        if hours > 0 {
            text.push_str(&format!("{hours}h"));
        }
        if hours > 0 || minutes > 0 {
            text.push_str(&format!("{minutes}m"));
        }
        if fraction == 0 {
            text.push_str(&format!("{seconds}s"));
        } else {
            let digits = format!("{fraction:09}");
            text.push_str(&format!("{seconds}.{}s", digits.trim_end_matches('0')));
        }
        text
    } else if nanos >= 1_000_000 {
        format!("{}ms", nanos as f64 / 1e6)
    } else {
        format!("{nanos}ns")
    }
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

/// The first `  at file:line:column` location a failure names.
fn failure_position(failure: &str) -> Option<Position> {
    let pattern = regex::Regex::new(r"(?m)^\s+at (.+):(\d+):(\d+)(?: in |$)").ok()?;
    let found = pattern.captures(failure)?;
    Some(Position::new(
        found[1].to_string(),
        found[2].parse().ok()?,
        found[3].parse().ok()?,
    ))
}

/// The `--json` document of `ms test`.
struct Document {
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
    fn new(source_root: &str) -> Document {
        Document {
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
                duration: Duration::ZERO,
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
                    if let Some(position) = failure_position(&case.failure) {
                        item = item.with("position", position.to_json());
                    }
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
            .with("tests", Json::Arr(tests))
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
    fn zero_timeout_disables_the_limit() {
        assert_eq!(
            parse_options(&args(&["--timeout=0"])).unwrap().timeout,
            None
        );
        assert!(parse_options(&args(&["--repeat=0"])).is_err());
        assert!(parse_options(&args(&["--match=("])).is_err());
    }

    #[test]
    fn go_duration_text() {
        assert_eq!(go_duration(Duration::from_secs(60)), "1m0s");
        assert_eq!(go_duration(Duration::from_secs(30)), "30s");
        assert_eq!(go_duration(Duration::from_millis(1500)), "1.5s");
        assert_eq!(go_duration(Duration::from_secs(3661)), "1h1m1s");
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
    fn failure_locations() {
        let position = failure_position("assertion failed\n  at src/a.ms:12:5 in main::t").unwrap();
        assert_eq!(
            (position.file.as_str(), position.line, position.column),
            ("src/a.ms", 12, 5)
        );
        assert!(failure_position("no location").is_none());
    }

    #[cfg(unix)]
    const NAMES: [&str; 4] = ["m::pass", "m::fail", "m::crash", "m::hang"];

    /// A shell script that speaks the test executable protocol.
    #[cfg(unix)]
    fn script(dir: &std::path::Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let path = dir.join("program");
        let text = r#"#!/bin/sh
case "$1" in
0) echo "hello from pass"; echo "note" >&2; exit 0;;
1) printf '\001FAIL\001boom\n  at src/a.ms:3:4 in m::fail\n' >&2; exit 1;;
2) ulimit -c 0; kill -SEGV $$;;
3) sleep 30;;
4) printf '\001SKIP\001not today\n' >&2; exit 0;;
esac
"#;
        std::fs::write(&path, text).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    #[cfg(unix)]
    fn run_script(arguments: &[&str]) -> (i32, String, Document) {
        run_names(arguments, &NAMES)
    }

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
        let mut document = Document::new("");
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
    fn each_test_runs_in_its_own_process() {
        let (status, text, document) = run_script(&["--timeout=400ms"]);
        assert_eq!(status, 3, "failed + crashed + timed out: {text}");
        let expected = [
            "RUN m::pass\nhello from pass\nPASS m::pass\n",
            "RUN m::fail\nFAIL m::fail: boom\n  at src/a.ms:3:4 in m::fail\n",
            "RUN m::crash\nFAIL m::crash: test process was terminated by signal 11\n",
            "RUN m::hang\nFAIL m::hang: timed out after 400ms; the test was cancelled (use --timeout to change the limit, 0 disables it)\n",
            "4 tests, 3 failed\n",
        ];
        assert_eq!(text, expected.concat());
        let statuses: Vec<_> = document.tests.iter().map(|t| t.status.as_str()).collect();
        assert_eq!(statuses, ["passed", "failed", "failed", "failed"]);
        let json = document.to_json().encode();
        assert!(json.contains("\"position\""), "{json}");
    }

    #[cfg(unix)]
    #[test]
    fn a_skipping_test_is_reported_skipped() {
        let names = ["m::pass", "m::fail", "m::crash", "m::hang", "m::skip"];
        let (status, text, document) = run_names(&["--test=m::pass", "--test=m::skip"], &names);
        assert_eq!(status, 0, "{text}");
        let expected = [
            "RUN m::pass\nhello from pass\nPASS m::pass\n",
            "RUN m::skip\nSKIP m::skip: not today\n",
            "2 tests, 0 failed, 1 skipped\n",
        ];
        assert_eq!(text, expected.concat());
        let json = document.to_json().encode();
        assert!(json.contains("\"status\": \"skipped\""), "{json}");
        assert!(json.contains("\"skipped\": 1"), "{json}");
        assert!(json.contains("\"not_run\": 0"), "{json}");
    }

    #[test]
    fn selection_listing_and_fail_fast() {
        let (status, text, _) = run_script(&["--list", "--match=pass|fail"]);
        assert_eq!((status, text.as_str()), (0, "m::pass\nm::fail\n"));

        let (status, text, document) = run_script(&["--fail-fast", "--timeout=400ms"]);
        assert_eq!(status, 1);
        assert!(text.ends_with("4 tests, 1 failed\n"), "{text}");
        assert_eq!(document.reason.as_deref(), Some("fail_fast"));
        assert_eq!(document.tests.len(), 4);
        assert_eq!(document.tests[2].status, Status::NotRun);

        let (status, text, _) = run_script(&["--test=m::missing"]);
        assert_eq!((status, text.as_str()), (1, ""));

        let (status, text, _) = run_script(&["--filter=zzz"]);
        assert_eq!(status, 1);
        assert!(
            text.starts_with("no tests match selection (4 tests available)"),
            "{text}"
        );

        let (status, text, _) = run_script(&["--test=m::pass", "--repeat=2"]);
        assert_eq!(status, 0);
        assert!(text.ends_with("2 tests, 0 failed\n"), "{text}");
    }
}

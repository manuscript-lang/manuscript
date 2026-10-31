//! `ms profile`: build a program, run it with the runtime's sampling profiler
//! switched on, and turn what the runtime wrote into a profile bundle.
//!
//! # Contract
//!
//! ```text
//! ms profile <file.ms|ms.toml> [--out-dir directory] [--top n] [--json]
//!            [--build-type level] [-- program arguments]
//! ```
//!
//! * `--out-dir <directory>`: the bundle directory (default `./profile`). It
//!   must not exist; it is created, and removed again if the build fails.
//! * `--top <n>`: rows in the text report (default 20).
//! * `--build-type <level>`: default `Release` (frame pointers and line
//!   tables are present at every level; the level only changes optimization).
//! * `--json`: print one versioned document instead of text. The program's own
//!   standard output is captured into the document (`stdout`, or
//!   `stdout_base64` when it is not UTF-8); its standard error stays live.
//! * Arguments after `--` go to the program. `ms profile` returns the
//!   program's exit status (128 + signal when it died from a signal).
//!
//! ## What runs
//!
//! 1. the build function builds `<out-dir>/program`.
//! 2. The program is started with the environment variable
//!    `MS_PROFILE=<out-dir>/profile.folded`. The runtime samples the program
//!    while it runs and, when it exits (normally, through a fault, or through
//!    SIGINT/SIGTERM cleanup), writes the folded stacks to that path.
//! 3. The folded stacks are converted. Nothing is written if the runtime
//!    produced no file; the program's exit status is still returned.
//!
//! ## Folded-stack input (written by the runtime)
//!
//! UTF-8 text, one stack per line: frames from the outermost call to the leaf
//! separated by `;`, a single space, then the sample count (a positive
//! integer). Frame names are function names such as `main`, `list.sorted` or
//! `main.ms:Config.load`; they must not contain `;` or a newline. Blank lines
//! are ignored. Lines starting with `#` are comments, except the optional
//! header `# hz=<n>` giving the sampling frequency (default 99 Hz), which sets
//! the pprof sample period. Repeated stacks are summed.
//!
//! ```text
//! # hz=99
//! main;parse_config;read_file 40
//! main;parse_config 12
//! main;render 310
//! ```
//!
//! ## Bundle
//!
//! | file             | content                                                     |
//! |------------------|-------------------------------------------------------------|
//! | `program`        | the executable that was profiled                            |
//! | `profile.folded` | the runtime's folded stacks, unchanged                      |
//! | `profile.pb`     | pprof protobuf (`go tool pprof`, `pprof -http`, speedscope) |
//! | `top.txt`        | the text report                                             |
//! | `manifest.json`  | file names, sample count and frequency                      |
//!
//! `profile.pb` holds two sample types, `samples/count` and `cpu/nanoseconds`,
//! one function and one location per frame name, and `period` = 1e9/hz.
//!
//! ## Output
//!
//! Text mode prints the report (the same text as `top.txt`), the bundle file
//! list, and how to use `perf record` on the same program. JSON mode prints
//! the native-command document (`format`, `command`, `build_type`,
//! `source_root`, `output`, `completed`, `exit_code`, `reason`, `artifacts`,
//! `stdout`, `diagnostics`) plus `profile`: `{samples, hz, duration_ns, top:
//! [{function, flat, flat_percent, cum, cum_percent}], perf: {record, report}}`.

use std::collections::BTreeMap;
use std::io::Read;
use std::process::{Command, Stdio};

use ms_driver::project::pathops;

use crate::backend::{BackendResult, BuildRequest, BuildType, Io, finish};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::invocation::Invocation;
use crate::json::Json;
use crate::process::{Stops, exit_code, wait_with_signals};
use crate::util::emit_json;

pub const DEFAULT_OUT_DIR: &str = "profile";
pub const DEFAULT_TOP: usize = 20;
pub const DEFAULT_HZ: u64 = 99;

/// Sampled stacks, outermost frame first.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FoldedProfile {
    pub hz: u64,
    pub stacks: Vec<(Vec<String>, u64)>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TopEntry {
    pub function: String,
    pub flat: u64,
    pub cum: u64,
}

impl FoldedProfile {
    pub fn total(&self) -> u64 {
        self.stacks.iter().map(|(_, count)| count).sum()
    }

    pub fn period_nanos(&self) -> u64 {
        1_000_000_000 / self.hz.max(1)
    }

    /// Functions ordered by flat samples (descending), then cumulative, then name.
    pub fn top(&self) -> Vec<TopEntry> {
        let mut table: BTreeMap<&str, (u64, u64)> = BTreeMap::new();
        for (stack, count) in &self.stacks {
            if let Some(leaf) = stack.last() {
                table.entry(leaf).or_default().0 += count;
            }
            let mut seen: Vec<&str> = Vec::new();
            for frame in stack {
                if !seen.contains(&frame.as_str()) {
                    seen.push(frame);
                    table.entry(frame).or_default().1 += count;
                }
            }
        }
        let mut entries: Vec<TopEntry> = table
            .into_iter()
            .map(|(function, (flat, cum))| TopEntry {
                function: function.to_string(),
                flat,
                cum,
            })
            .collect();
        entries.sort_by(|a, b| {
            b.flat
                .cmp(&a.flat)
                .then(b.cum.cmp(&a.cum))
                .then(a.function.cmp(&b.function))
        });
        entries
    }
}

/// Parse the runtime's folded-stack text.
pub fn parse_folded(text: &str) -> Result<FoldedProfile, String> {
    let mut hz = DEFAULT_HZ;
    let mut merged: BTreeMap<Vec<String>, u64> = BTreeMap::new();
    let mut order: Vec<Vec<String>> = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let line = line.trim_end();
        if line.trim().is_empty() {
            continue;
        }
        if let Some(comment) = line.strip_prefix('#') {
            if let Some(value) = comment.trim().strip_prefix("hz=") {
                hz = value
                    .trim()
                    .parse::<u64>()
                    .ok()
                    .filter(|&n| n > 0)
                    .ok_or_else(|| format!("line {}: invalid hz header {line:?}", index + 1))?;
            }
            continue;
        }
        let bad = || {
            format!(
                "line {}: expected '<frame>;<frame> <count>', got {line:?}",
                index + 1
            )
        };
        let (stack, count) = line.rsplit_once(' ').ok_or_else(bad)?;
        let count: u64 = count.parse().ok().filter(|&n| n > 0).ok_or_else(bad)?;
        let frames: Vec<String> = stack.split(';').map(str::to_string).collect();
        if frames.iter().any(|frame| frame.is_empty()) {
            return Err(bad());
        }
        let slot = merged.entry(frames.clone()).or_insert_with(|| {
            order.push(frames.clone());
            0
        });
        *slot += count;
    }
    let stacks = order
        .into_iter()
        .map(|frames| {
            let count = merged[&frames];
            (frames, count)
        })
        .collect();
    Ok(FoldedProfile { hz, stacks })
}

/// The text report: a summary line and the `top` busiest functions.
pub fn render_top(profile: &FoldedProfile, top: usize) -> String {
    let entries = profile.top();
    let total = profile.total();
    let seconds = (total * profile.period_nanos()) as f64 / 1e9;
    let shown = entries.len().min(top);
    let mut out = format!(
        "Showing top {shown} of {} functions ({total} samples, {} Hz, {seconds:.2}s)\n",
        entries.len(),
        profile.hz
    );
    out.push_str(&format!(
        "{:>8} {:>7} {:>8} {:>7}  {}\n",
        "flat", "flat%", "cum", "cum%", "function"
    ));
    let percent = |n: u64| {
        if total == 0 {
            0.0
        } else {
            n as f64 * 100.0 / total as f64
        }
    };
    for entry in entries.iter().take(top) {
        out.push_str(&format!(
            "{:>8} {:>6.2}% {:>8} {:>6.2}%  {}\n",
            entry.flat,
            percent(entry.flat),
            entry.cum,
            percent(entry.cum),
            entry.function
        ));
    }
    out
}

fn perf_record(program: &str, arguments: &[String]) -> String {
    let mut command = format!("perf record -F 999 --call-graph fp -o perf.data -- {program}");
    for argument in arguments {
        command.push(' ');
        command.push_str(argument);
    }
    command
}

const PERF_REPORT: &str = "perf report -i perf.data --no-children";

fn perf_help(program: &str, arguments: &[String]) -> String {
    format!(
        "To sample with perf instead (no ms involved):\n  {}\n  {PERF_REPORT}\nBuilds keep frame pointers, DWARF line tables and a perf map (/tmp/perf-<pid>.map), so perf resolves Manuscript function names and lines.\n",
        perf_record(program, arguments)
    )
}

/// Encode a pprof `profile.proto` message (uncompressed; `go tool pprof` and
/// `pprof` accept raw protobuf as well as gzip).
pub fn encode_pprof(profile: &FoldedProfile, time_nanos: u64) -> Vec<u8> {
    let mut strings: Vec<String> = vec![String::new()];
    let index = |text: &str, strings: &mut Vec<String>| -> u64 {
        match strings.iter().position(|s| s == text) {
            Some(i) => i as u64,
            None => {
                strings.push(text.to_string());
                (strings.len() - 1) as u64
            }
        }
    };
    let samples_type = index("samples", &mut strings);
    let count_unit = index("count", &mut strings);
    let cpu_type = index("cpu", &mut strings);
    let nanos_unit = index("nanoseconds", &mut strings);

    // One function and one location per frame name, numbered from 1 in first-seen order.
    let mut ids: BTreeMap<&str, u64> = BTreeMap::new();
    let mut names: Vec<&str> = Vec::new();
    for (stack, _) in &profile.stacks {
        for frame in stack {
            if !ids.contains_key(frame.as_str()) {
                names.push(frame);
                ids.insert(frame, names.len() as u64);
            }
        }
    }
    let period = profile.period_nanos();
    let mut out = Vec::new();
    for (kind, unit) in [(samples_type, count_unit), (cpu_type, nanos_unit)] {
        message(&mut out, 1, &value_type(kind, unit));
    }
    for (stack, count) in &profile.stacks {
        let mut sample = Vec::new();
        let leaf_first: Vec<u64> = stack
            .iter()
            .rev()
            .map(|frame| ids[frame.as_str()])
            .collect();
        packed(&mut sample, 1, &leaf_first);
        packed(&mut sample, 2, &[*count, count * period]);
        message(&mut out, 2, &sample);
    }
    for (i, _) in names.iter().enumerate() {
        let id = i as u64 + 1;
        let mut line = Vec::new();
        varint_field(&mut line, 1, id);
        let mut location = Vec::new();
        varint_field(&mut location, 1, id);
        message(&mut location, 4, &line);
        message(&mut out, 4, &location);
    }
    for (i, name) in names.iter().enumerate() {
        let id = i as u64 + 1;
        let name_index = index(name, &mut strings);
        let mut function = Vec::new();
        varint_field(&mut function, 1, id);
        varint_field(&mut function, 2, name_index);
        varint_field(&mut function, 3, name_index);
        message(&mut out, 5, &function);
    }
    for text in &strings {
        message(&mut out, 6, text.as_bytes());
    }
    varint_field(&mut out, 9, time_nanos);
    varint_field(&mut out, 10, profile.total() * period);
    message(&mut out, 11, &value_type(cpu_type, nanos_unit));
    varint_field(&mut out, 12, period);
    out
}

fn value_type(kind: u64, unit: u64) -> Vec<u8> {
    let mut out = Vec::new();
    varint_field(&mut out, 1, kind);
    varint_field(&mut out, 2, unit);
    out
}

fn varint(out: &mut Vec<u8>, mut value: u64) {
    while value >= 0x80 {
        out.push((value as u8 & 0x7f) | 0x80);
        value >>= 7;
    }
    out.push(value as u8);
}

fn varint_field(out: &mut Vec<u8>, field: u32, value: u64) {
    varint(out, u64::from(field) << 3);
    varint(out, value);
}

fn message(out: &mut Vec<u8>, field: u32, body: &[u8]) {
    varint(out, u64::from(field) << 3 | 2);
    varint(out, body.len() as u64);
    out.extend_from_slice(body);
}

fn packed(out: &mut Vec<u8>, field: u32, values: &[u64]) {
    let mut body = Vec::new();
    for &value in values {
        varint(&mut body, value);
    }
    message(out, field, &body);
}

fn now_nanos() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos() as u64)
}

/// `ms profile` after option validation.
pub fn run_profile(
    inv: &Invocation,
    build_type: BuildType,
    build: &dyn Fn(&BuildRequest, &mut Io) -> BackendResult,
    io: &mut Io,
) -> i32 {
    let display_output = if inv.output.is_empty() {
        DEFAULT_OUT_DIR.to_string()
    } else {
        inv.output.clone()
    };
    let top = if inv.top == 0 { DEFAULT_TOP } else { inv.top };
    let structured = inv.structured;
    let output = match pathops::abs(&display_output) {
        Ok(path) => path,
        Err(error) => {
            return fail(
                io,
                inv,
                build_type,
                &display_output,
                "build",
                &error.to_string(),
                1,
                &[],
            );
        }
    };
    let program = pathops::join(&[&output, "program"]);
    let folded_path = pathops::join(&[&output, "profile.folded"]);

    if let Err(error) = std::fs::create_dir(&output) {
        let cause = ms_driver::project::error::errno_message(error.raw_os_error().unwrap_or(0));
        let message = format!(
            "profile directory must be new: mkdir {output}: {cause}; choose a path that does not exist with --out-dir <directory>"
        );
        return fail(io, inv, build_type, &output, "artifact", &message, 1, &[]);
    }
    // Build with stderr captured so --json can report it, then relayed.
    let mut build_err: Vec<u8> = Vec::new();
    let mut build_out: Vec<u8> = Vec::new();
    let request = BuildRequest {
        filename: inv.filename.clone(),
        output: program.clone(),
        build_type,
        json: false,
        link: Vec::new(),
    };
    let status = {
        let mut build_io = Io {
            stdin: &mut *io.stdin,
            stdout: &mut build_out,
            stderr: &mut build_err,
        };
        finish(build(&request, &mut build_io), &mut build_io)
    };
    let _ = io.stderr.write_all(&build_err);
    if status != 0 {
        // This invocation created the directory; a failed build must not block a retry.
        let _ = std::fs::remove_dir_all(&output);
        let message = String::from_utf8_lossy(&build_err).trim().to_string();
        return fail(io, inv, build_type, &output, "build", &message, status, &[]);
    }

    let mut command = Command::new(&program);
    command
        .args(&inv.arguments)
        .env("MS_PROFILE", &folded_path)
        .stdin(Stdio::inherit())
        .stderr(Stdio::inherit());
    command.stdout(if structured {
        Stdio::piped()
    } else {
        Stdio::inherit()
    });
    let stops = Stops::catch();
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            return fail(
                io,
                inv,
                build_type,
                &output,
                "execution",
                &error.to_string(),
                1,
                &[],
            );
        }
    };
    let captured = child.stdout.take().map(|mut pipe| {
        std::thread::spawn(move || {
            let mut data = Vec::new();
            let _ = pipe.read_to_end(&mut data);
            data
        })
    });
    let waited = wait_with_signals(&mut child, &stops);
    let stdout_bytes = captured
        .and_then(|handle| handle.join().ok())
        .unwrap_or_default();
    let status = match waited {
        Ok(status) => status,
        Err(error) => {
            return fail(
                io,
                inv,
                build_type,
                &output,
                "execution",
                &error.to_string(),
                1,
                &stdout_bytes,
            );
        }
    };
    let program_status = exit_code(status);
    let reason = if status.code().is_some() {
        "program_exit"
    } else {
        "interrupted"
    };

    let mut diagnostics: Vec<CommandDiagnostic> = Vec::new();
    let mut artifacts: Vec<(&str, String, &str)> =
        vec![("executable", program.clone(), "verified")];
    let mut profile_json = Json::Null;
    let mut report = String::new();
    let mut final_status = program_status;
    match std::fs::read_to_string(&folded_path) {
        Err(_) => {
            let message = format!(
                "the program wrote no profile to {folded_path} (it exited with status {program_status}); a runtime built without profiling support or a program killed before cleanup writes nothing"
            );
            diagnostics.push(CommandDiagnostic {
                severity: String::new(),
                code: "MSN001".into(),
                phase: "artifact".into(),
                message: message.clone(),
                position: Position::new(&inv.filename, 1, 1),
                end: None,
                fix: None,
            });
            artifacts.push(("folded", folded_path.clone(), "missing"));
            if !structured {
                let _ = writeln!(io.stderr, "{message}");
            }
            if final_status == 0 {
                final_status = 1;
            }
        }
        Ok(text) => match parse_folded(&text) {
            Err(problem) => {
                let message = format!("cannot read {folded_path}: {problem}");
                diagnostics.push(CommandDiagnostic {
                    severity: String::new(),
                    code: "MSN001".into(),
                    phase: "artifact".into(),
                    message: message.clone(),
                    position: Position::new(&inv.filename, 1, 1),
                    end: None,
                    fix: None,
                });
                artifacts.push(("folded", folded_path.clone(), "written"));
                if !structured {
                    let _ = writeln!(io.stderr, "{message}");
                }
                if final_status == 0 {
                    final_status = 1;
                }
            }
            Ok(profile) => {
                let pprof_path = pathops::join(&[&output, "profile.pb"]);
                let top_path = pathops::join(&[&output, "top.txt"]);
                let manifest_path = pathops::join(&[&output, "manifest.json"]);
                report = render_top(&profile, top);
                let manifest = Json::object()
                    .with("format", Json::int(1))
                    .with("executable", Json::str("program"))
                    .with("folded", Json::str("profile.folded"))
                    .with("pprof", Json::str("profile.pb"))
                    .with("top", Json::str("top.txt"))
                    .with("samples", Json::int(profile.total() as i64))
                    .with("hz", Json::int(profile.hz as i64));
                let writes = [
                    std::fs::write(&pprof_path, encode_pprof(&profile, now_nanos())),
                    std::fs::write(&top_path, report.as_bytes()),
                    std::fs::write(
                        &manifest_path,
                        manifest.pretty_line(ms_json::Escape::HtmlSafe).as_bytes(),
                    ),
                ];
                if let Some(Err(error)) = writes.iter().find(|result| result.is_err()) {
                    let message = format!("cannot write the profile bundle in {output}: {error}");
                    diagnostics.push(CommandDiagnostic {
                        severity: String::new(),
                        code: "MSN001".into(),
                        phase: "artifact".into(),
                        message,
                        position: Position::new(&inv.filename, 1, 1),
                        end: None,
                        fix: None,
                    });
                    final_status = final_status.max(1);
                }
                for (kind, path) in [
                    ("folded", &folded_path),
                    ("pprof", &pprof_path),
                    ("top", &top_path),
                    ("manifest", &manifest_path),
                ] {
                    artifacts.push((kind, path.clone(), "written"));
                }
                let total = profile.total();
                let percent = |n: u64| {
                    if total == 0 {
                        0.0
                    } else {
                        (n as f64 * 10000.0 / total as f64).round() / 100.0
                    }
                };
                let entries = profile.top();
                profile_json = Json::object()
                    .with("samples", Json::int(total as i64))
                    .with("hz", Json::int(profile.hz as i64))
                    .with(
                        "duration_ns",
                        Json::int((total * profile.period_nanos()) as i64),
                    )
                    .with(
                        "top",
                        Json::Arr(
                            entries
                                .iter()
                                .take(top)
                                .map(|e| {
                                    Json::object()
                                        .with("function", Json::str(&e.function))
                                        .with("flat", Json::int(e.flat as i64))
                                        .with(
                                            "flat_percent",
                                            Json::Num(format!("{}", percent(e.flat))),
                                        )
                                        .with("cum", Json::int(e.cum as i64))
                                        .with(
                                            "cum_percent",
                                            Json::Num(format!("{}", percent(e.cum))),
                                        )
                                })
                                .collect(),
                        ),
                    )
                    .with(
                        "perf",
                        Json::object()
                            .with("record", Json::str(perf_record(&program, &inv.arguments)))
                            .with("report", Json::str(PERF_REPORT)),
                    );
            }
        },
    }

    if structured {
        let mut document = native_document(
            &inv.command,
            "",
            build_type,
            &output,
            true,
            final_status,
            Some(reason),
            &artifacts,
            &stdout_bytes,
            &diagnostics,
        );
        if profile_json != Json::Null {
            document = document.with("profile", profile_json);
        }
        return emit_json(io, &document, final_status);
    }
    if !report.is_empty() {
        let _ = write!(io.stdout, "{report}");
        let _ = writeln!(io.stdout, "\nProfile bundle: {display_output}");
        for (file, what) in [
            (
                "profile.folded",
                "folded stacks (flamegraph.pl, inferno, speedscope)",
            ),
            (
                "profile.pb",
                "pprof protobuf (go tool pprof, pprof -http=:8080)",
            ),
            ("top.txt", "this report"),
            ("program", "the profiled executable"),
        ] {
            let _ = writeln!(
                io.stdout,
                "  {:<28} {what}",
                pathops::join(&[&display_output, file])
            );
        }
        let _ = writeln!(io.stdout);
        let shown_program = pathops::join(&[&display_output, "program"]);
        let _ = write!(io.stdout, "{}", perf_help(&shown_program, &inv.arguments));
    }
    final_status
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn native_document(
    command: &str,
    source_root: &str,
    build_type: BuildType,
    output: &str,
    completed: bool,
    exit_code: i32,
    reason: Option<&str>,
    artifacts: &[(&str, String, &str)],
    stdout: &[u8],
    diagnostics: &[CommandDiagnostic],
) -> Json {
    let mut document = Json::object()
        .with("format", Json::int(1))
        .with("command", Json::str(command))
        .with("build_type", Json::str(build_type.as_str()))
        .with("source_root", Json::str(source_root))
        .with("output", Json::str(output))
        .with("completed", Json::Bool(completed))
        .with("exit_code", Json::int(i64::from(exit_code)));
    if let Some(reason) = reason {
        document = document.with("reason", Json::str(reason));
    }
    document = document.with(
        "artifacts",
        Json::Arr(
            artifacts
                .iter()
                .map(|(kind, path, state)| {
                    Json::object()
                        .with("kind", Json::str(*kind))
                        .with("path", Json::str(path))
                        .with("state", Json::str(*state))
                })
                .collect(),
        ),
    );
    match std::str::from_utf8(stdout) {
        Ok(text) => document = document.with("stdout", Json::str(text)),
        Err(_) => {
            document = document
                .with("stdout", Json::str(""))
                .with("stdout_base64", Json::str(base64(stdout)))
        }
    }
    document.with(
        "diagnostics",
        Json::Arr(diagnostics.iter().map(CommandDiagnostic::to_json).collect()),
    )
}

#[allow(clippy::too_many_arguments)]
fn fail(
    io: &mut Io,
    inv: &Invocation,
    build_type: BuildType,
    output: &str,
    phase: &str,
    message: &str,
    status: i32,
    stdout: &[u8],
) -> i32 {
    if !message.is_empty() && phase != "build" {
        let _ = writeln!(io.stderr, "{message}");
    }
    if !inv.structured {
        return status;
    }
    let diagnostic = CommandDiagnostic {
        severity: String::new(),
        code: "MSN001".into(),
        phase: phase.into(),
        message: message.into(),
        position: Position::new(&inv.filename, 1, 1),
        end: None,
        fix: None,
    };
    let reason = format!("{phase}_error");
    let document = native_document(
        &inv.command,
        "",
        build_type,
        output,
        false,
        status,
        Some(&reason),
        &[],
        stdout,
        &[diagnostic],
    );
    emit_json(io, &document, status)
}

pub(crate) fn base64(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        out.push(ALPHABET[(n >> 18) as usize & 63] as char);
        out.push(ALPHABET[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

pub const HELP: &str = "Usage: ms profile <file.ms|ms.toml> [--json] [--out-dir directory] [--top n] [--build-type level] [-- program arguments]

Build an application, run it with the sampling profiler enabled, and write a profile bundle.
The runtime samples the program (MS_PROFILE is set to the folded-stack output path) and ms converts
what it wrote: folded stacks, a pprof protobuf, and a text report of the busiest functions.
The bundle contains program, profile.folded, profile.pb, top.txt, and manifest.json.
The directory must be new. Native builds keep frame pointers, DWARF line tables and a perf map,
so perf record works on any ms build output; ms profile prints the command for this program.
Profiling adds overhead. Measure normal execution separately.
Arguments after -- go to the application; its exit status is returned.
Builds link with the linker bundled in ms on every platform; no C compiler or SDK is needed.

Options:
  --out-dir <directory>    Bundle directory (default: ./profile)
  --top <n>                Rows in the text report (default 20)
  --json                   Emit one versioned result; capture stdout, keep stderr live
  --build-type <level>  Debug, Release, or MinSizeRel (case-insensitive)
  Default build type: Release
  -h, --help  Show this help without executing the command

Examples:
  ms profile ms.toml
  ms profile main.ms --out-dir capture --top 10 -- first second
";

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str =
        "# hz=100\nmain;parse;read 40\nmain;parse 10\nmain;render 50\n\nmain;parse;read 10\n";

    #[test]
    fn folded_round_trip() {
        let profile = parse_folded(SAMPLE).unwrap();
        assert_eq!(profile.hz, 100);
        assert_eq!(profile.total(), 110);
        assert_eq!(
            profile.stacks[0],
            (vec!["main".to_string(), "parse".into(), "read".into()], 50)
        );
        let top = profile.top();
        assert_eq!(
            top[0],
            TopEntry {
                function: "read".into(),
                flat: 50,
                cum: 50
            }
        );
        assert_eq!(
            top[1],
            TopEntry {
                function: "render".into(),
                flat: 50,
                cum: 50
            }
        );
        assert_eq!(
            top[2],
            TopEntry {
                function: "parse".into(),
                flat: 10,
                cum: 60
            }
        );
        assert_eq!(
            top[3],
            TopEntry {
                function: "main".into(),
                flat: 0,
                cum: 110
            }
        );
    }

    #[test]
    fn recursion_counts_cumulative_once() {
        let profile = parse_folded("f;f;f 4\n").unwrap();
        assert_eq!(
            profile.top(),
            vec![TopEntry {
                function: "f".into(),
                flat: 4,
                cum: 4
            }]
        );
    }

    #[test]
    fn rejects_bad_lines() {
        for bad in ["main", "main x", "main 0", "main;;x 1", "# hz=0\nmain 1"] {
            assert!(parse_folded(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn report_text() {
        let profile = parse_folded(SAMPLE).unwrap();
        let text = render_top(&profile, 2);
        assert_eq!(
            text,
            "Showing top 2 of 4 functions (110 samples, 100 Hz, 1.10s)\n    flat   flat%      cum    cum%  function\n      50  45.45%       50  45.45%  read\n      50  45.45%       50  45.45%  render\n"
        );
    }

    #[test]
    fn pprof_structure() {
        let profile = parse_folded("a;b 3\n").unwrap();
        let bytes = encode_pprof(&profile, 42);
        // sample_type x2, one sample, two locations, two functions, strings, time, duration, period_type, period.
        let fields = top_level_fields(&bytes);
        assert_eq!(fields.iter().filter(|f| **f == 1).count(), 2);
        assert_eq!(fields.iter().filter(|f| **f == 2).count(), 1);
        assert_eq!(fields.iter().filter(|f| **f == 4).count(), 2);
        assert_eq!(fields.iter().filter(|f| **f == 5).count(), 2);
        assert!(fields.iter().filter(|f| **f == 6).count() >= 7);
        for field in [9, 10, 11, 12] {
            assert_eq!(
                fields.iter().filter(|f| **f == field).count(),
                1,
                "field {field}"
            );
        }
    }

    /// Walk the top-level protobuf fields and return their numbers in order.
    fn top_level_fields(bytes: &[u8]) -> Vec<u64> {
        let mut fields = Vec::new();
        let mut i = 0;
        let read = |i: &mut usize| {
            let mut value = 0u64;
            let mut shift = 0;
            loop {
                let byte = bytes[*i];
                *i += 1;
                value |= u64::from(byte & 0x7f) << shift;
                if byte & 0x80 == 0 {
                    return value;
                }
                shift += 7;
            }
        };
        while i < bytes.len() {
            let tag = read(&mut i);
            fields.push(tag >> 3);
            match tag & 7 {
                0 => {
                    read(&mut i);
                }
                2 => {
                    let len = read(&mut i) as usize;
                    i += len;
                }
                other => panic!("unexpected wire type {other}"),
            }
        }
        fields
    }

    #[test]
    fn base64_matches_reference() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(&[0xff, 0xfe]), "//4=");
    }
}

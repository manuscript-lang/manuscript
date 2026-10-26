//! `ms verify`: check, fmt --check, lint and test on one target in one result.
//! Orchestration only; each step is this CLI run in process with its streams
//! captured, so verify works .

use std::time::Instant;

use crate::backend::Io;
use crate::engine::Engine;
use crate::json::{self, Json};
use crate::util::{emit_json, resolve_input};
use ms_build::Lower;

/// Findings printed per failed step in text mode (`--json` carries every one).
const FINDING_LIMIT: usize = 8;

struct Step {
    name: &'static str,
    status: &'static str,
    exit_code: i32,
    duration_ns: i64,
    reason: String,
    error: String,
    result: Option<Json>,
}

impl Step {
    fn new(name: &'static str, status: &'static str) -> Step {
        Step {
            name,
            status,
            exit_code: 0,
            duration_ns: 0,
            reason: String::new(),
            error: String::new(),
            result: None,
        }
    }

    fn to_json(&self) -> Json {
        let mut object = Json::object()
            .with("name", Json::str(self.name))
            .with("status", Json::str(self.status))
            .with("exit_code", Json::int(i64::from(self.exit_code)))
            .with("duration_ns", Json::int(self.duration_ns));
        if !self.reason.is_empty() {
            object = object.with("reason", Json::str(&self.reason));
        }
        if !self.error.is_empty() {
            object = object.with("error", Json::str(&self.error));
        }
        if let Some(result) = &self.result {
            object = object.with("result", result.clone());
        }
        object
    }
}

pub fn run_verify<L: Lower>(args: &[String], engine: &Engine<L>, io: &mut Io) -> i32 {
    let (mut structured, mut skip_test, mut positional) = (false, false, false);
    let mut targets: Vec<&String> = Vec::new();
    for arg in args {
        match arg.as_str() {
            "--" if !positional => positional = true,
            "--json" if !positional => structured = true,
            "--no-test" if !positional => skip_test = true,
            _ if !positional && arg.starts_with('-') => {
                let _ = writeln!(
                    io.stderr,
                    "unknown option {arg} for ms verify; run 'ms help verify' for its options"
                );
                return 2;
            }
            _ => targets.push(arg),
        }
    }
    if targets.len() > 1 {
        let _ = writeln!(
            io.stderr,
            "ms verify takes one target; pass a .ms file, directory, or ms.toml"
        );
        return 2;
    }
    let target = targets.first().map_or("ms.toml", |t| t.as_str());
    if target.is_empty() {
        let _ = writeln!(
            io.stderr,
            "ms verify: the target is empty; pass a .ms file, directory, or ms.toml"
        );
        return 2;
    }
    let target = match resolve_input("verify", target) {
        Ok(target) => target,
        Err(message) => {
            let _ = writeln!(io.stderr, "{message}");
            return 2;
        }
    };
    // Subcommands parse options again; retain the target's positional meaning.
    let input = if target.starts_with('-') {
        format!("./{target}")
    } else {
        target.clone()
    };
    let mut steps: Vec<Step> = Vec::new();
    let mut ok = true;
    let mut record = |io: &mut Io, step: Step, steps: &mut Vec<Step>| {
        if step.status == "failed" {
            ok = false;
        }
        if !structured {
            let _ = writeln!(io.stdout, "{:<6} {}", step.name, step.status);
        }
        steps.push(step);
    };
    let skip = |name: &'static str, reason: &str| {
        let mut step = Step::new(name, "skipped");
        step.reason = reason.to_string();
        step
    };
    let check = run_step("check", &["check", &input, "--json"], engine, io);
    let check_passed = check.status == "passed";
    record(io, check, &mut steps);
    let format = run_step("fmt", &["fmt", &input, "--check", "--json"], engine, io);
    record(io, format, &mut steps);
    if check_passed {
        let lint = run_step("lint", &["lint", &input, "--json"], engine, io);
        record(io, lint, &mut steps);
    } else {
        record(io, skip("lint", "check failed"), &mut steps);
    }
    if skip_test {
        record(io, skip("test", "--no-test"), &mut steps);
    } else if !check_passed {
        record(io, skip("test", "check failed"), &mut steps);
    } else {
        let test = run_step("test", &["test", &input, "--json"], engine, io);
        record(io, test, &mut steps);
    }
    let status = i32::from(!ok);
    if structured {
        let document = Json::object()
            .with("format", Json::int(1))
            .with("target", Json::str(&target))
            .with("ok", Json::Bool(ok))
            .with(
                "steps",
                Json::Arr(steps.iter().map(Step::to_json).collect()),
            );
        return emit_json(io, &document, status);
    }
    for step in steps.iter().filter(|step| step.status == "failed") {
        print_findings(step, io);
        let _ = writeln!(
            io.stderr,
            "{0} failed; run ms {0} {target} for details (or ms verify {target} --json for every step)",
            step.name
        );
    }
    status
}

/// Run one command in process with stdout and stderr captured.
fn run_step<L: Lower>(name: &'static str, args: &[&str], engine: &Engine<L>, io: &mut Io) -> Step {
    let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
    let (mut out, mut err): (Vec<u8>, Vec<u8>) = (Vec::new(), Vec::new());
    let start = Instant::now();
    let code = {
        let mut step_io = Io {
            stdin: &mut *io.stdin,
            stdout: &mut out,
            stderr: &mut err,
        };
        crate::run(&args, engine, &mut step_io)
    };
    let mut step = Step::new(name, "failed");
    step.exit_code = code;
    step.duration_ns = start.elapsed().as_nanos() as i64;
    let output = String::from_utf8_lossy(&out);
    step.result = json::parse(output.trim()).ok();
    if code == 0 {
        step.status = "passed";
        return step;
    }
    if step.result.is_none() {
        step.error = String::from_utf8_lossy(&err).trim().to_string();
    }
    step
}

/// Print the leading findings of a failed step so the text summary names the
/// problem instead of only pointing at another command.
fn print_findings(step: &Step, io: &mut Io) {
    let mut findings: Vec<String> = Vec::new();
    if !step.error.is_empty() {
        findings.push(step.error.clone());
    }
    if let Some(result) = &step.result {
        if let Some(diagnostics) = result.get("diagnostics").and_then(Json::as_array) {
            for d in diagnostics {
                let position = d.get("position");
                let number = |key: &str| match position.and_then(|p| p.get(key)) {
                    Some(Json::Num(n)) => n.clone(),
                    _ => "0".to_string(),
                };
                let file = position
                    .and_then(|p| p.get("file"))
                    .and_then(Json::as_str)
                    .unwrap_or("");
                let message = d.get("message").and_then(Json::as_str).unwrap_or("");
                findings.push(format!(
                    "{file}:{}:{}: {message}",
                    number("line"),
                    number("column")
                ));
            }
        }
        if let Some(tests) = result.get("tests").and_then(Json::as_array) {
            for t in tests {
                if t.get("status").and_then(Json::as_str) == Some("failed") {
                    let name = t.get("name").and_then(Json::as_str).unwrap_or("");
                    let failure = t.get("failure").and_then(Json::as_str).unwrap_or("");
                    findings.push(format!(
                        "{name}: {}",
                        failure.split('\n').next().unwrap_or("")
                    ));
                }
            }
        }
    }
    for (i, finding) in findings.iter().enumerate() {
        if i == FINDING_LIMIT {
            let _ = writeln!(io.stderr, "  ... {} more", findings.len() - i);
            break;
        }
        let _ = writeln!(io.stderr, "  {finding}");
    }
}

//! `ms run`: build a temporary executable and run it.

use std::process::{Command, Stdio};
use std::time::Duration;

use ms_build::Lower;

use super::{RustBackend, TempDir, compile};
use crate::backend::{BackendResult, Io, RunRequest};
use crate::diagnostic::CommandDiagnostic;
use crate::fault::{EXIT_FAULT, Fault};
use crate::json::Json;
use crate::process::{exit_code, wait_supervised, wait_with_signals};
use crate::util::emit_json;

use super::testing::pipe_reader;

pub(super) fn run<L: Lower>(
    backend: &RustBackend<L>,
    request: &RunRequest,
    io: &mut Io,
) -> BackendResult {
    let mut compiled = match compile(backend, &request.filename, false) {
        Ok(compiled) => compiled,
        Err(failure) if request.json => {
            let document = document(&failure.source_root, 1, "", "")
                .with("reason", Json::str("compile_error"))
                .with(
                    "diagnostics",
                    Json::Arr(
                        failure
                            .command_diagnostics()
                            .iter()
                            .map(CommandDiagnostic::to_json)
                            .collect(),
                    ),
                );
            return Ok(emit_json(io, &document, 1));
        }
        Err(failure) => return Ok(failure.report(io)),
    };
    let directory = match TempDir::create("manuscript-run-") {
        Ok(directory) => directory,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return Ok(1);
        }
    };
    let executable = directory.0.join("program");
    if let Err(message) = backend.link(&mut compiled, &executable, request.build_type) {
        let _ = writeln!(io.stderr, "{message}");
        return Ok(1);
    }
    if request.json {
        return run_structured(&compiled.source_root, &executable, request, io);
    }
    // The child shares the terminal: flush what we have written first.
    let _ = io.stdout.flush();
    let mut child = match Command::new(&executable).args(&request.arguments).spawn() {
        Ok(child) => child,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return Ok(1);
        }
    };
    match wait_with_signals(&mut child) {
        Ok(status) => Ok(exit_code(status)),
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            Ok(1)
        }
    }
}

/// The `--json` document of `ms run`, without the fault or diagnostics.
fn document(source_root: &str, exit: i32, stdout: &str, stderr: &str) -> Json {
    Json::object()
        .with("format", Json::int(1))
        .with("source_root", Json::str(source_root))
        .with("exit_code", Json::int(i64::from(exit)))
        .with("stdout", Json::str(stdout))
        .with("stderr", Json::str(stderr))
}

/// Runs the program with its output captured and reports one document: the exit status, the
/// output, and, when the program ended in a runtime fault, the fault as structured data.
fn run_structured(
    source_root: &str,
    executable: &std::path::Path,
    request: &RunRequest,
    io: &mut Io,
) -> BackendResult {
    let spawned = Command::new(executable)
        .args(&request.arguments)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();
    let mut child = match spawned {
        Ok(child) => child,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return Ok(1);
        }
    };
    let stdout = pipe_reader(child.stdout.take().expect("piped stdout"));
    let stderr = pipe_reader(child.stderr.take().expect("piped stderr"));
    let (mut out, mut err): (Vec<u8>, Vec<u8>) = (Vec::new(), Vec::new());
    let waited = wait_supervised(&mut child, None, &mut || {
        while let Ok(chunk) = stdout.try_recv() {
            out.extend_from_slice(&chunk);
        }
        while let Ok(chunk) = stderr.try_recv() {
            err.extend_from_slice(&chunk);
        }
    });
    // Output written just before exit; a pipe held open elsewhere ends the wait.
    while let Ok(chunk) = stdout.recv_timeout(Duration::from_millis(100)) {
        out.extend_from_slice(&chunk);
    }
    while let Ok(chunk) = stderr.recv_timeout(Duration::from_millis(100)) {
        err.extend_from_slice(&chunk);
    }
    let status = match waited {
        Ok(waited) => exit_code(waited.status),
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return Ok(1);
        }
    };
    let (out, err) = (
        String::from_utf8_lossy(&out).into_owned(),
        String::from_utf8_lossy(&err).into_owned(),
    );
    let mut json = document(source_root, status, &out, &err);
    if status == EXIT_FAULT
        && let Some(fault) = Fault::parse(&err)
    {
        json = json.with("fault", fault.to_json());
    }
    json = json.with("diagnostics", Json::Arr(Vec::<Json>::new()));
    Ok(emit_json(io, &json, status))
}

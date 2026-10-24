//! `ms run`: build a temporary executable and run it.

use std::process::Command;

use ms_driver::Lower;

use super::{Engine, TempDir, compile};
use crate::backend::{BackendResult, Io, RunRequest};
use crate::process::{exit_code, wait_with_signals};

pub(super) fn run<L: Lower>(
    backend: &Engine<L>,
    request: &RunRequest,
    io: &mut Io,
) -> BackendResult {
    let mut compiled = match compile(backend, &request.filename, request.build_type, false) {
        Ok(compiled) => compiled,
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

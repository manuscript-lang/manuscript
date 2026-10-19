//! `ms build`.

use std::os::unix::fs::MetadataExt;
use std::path::Path;

use ms_driver::Lower;
use ms_project::gopath;

use super::{Failure, RustBackend, compile};
use crate::backend::{BackendResult, BuildRequest, Io};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::json::Json;
use crate::profile::native_document;
use crate::util::emit_json;

/// The two artifacts `ms build` leaves: the executable and its metadata.
fn artifacts(output: &str, executable_built: bool) -> Vec<(&'static str, String, &'static str)> {
    let metadata = format!("{output}.ms-build.json");
    [
        ("executable", output.to_string()),
        ("build_metadata", metadata),
    ]
    .into_iter()
    .map(|(kind, path)| {
        let state = if executable_built {
            "verified"
        } else if Path::new(&path).is_file() {
            "preserved"
        } else {
            "missing"
        };
        (kind, path, state)
    })
    .collect()
}

pub(super) fn build<L: Lower>(
    backend: &RustBackend<L>,
    request: &BuildRequest,
    io: &mut Io,
) -> BackendResult {
    let display = if request.output.is_empty() {
        "program"
    } else {
        &request.output
    };
    let structured = request.json;
    let (output, path_error) = match gopath::abs(display) {
        Ok(absolute) => (absolute, None),
        Err(error) => (display.to_string(), Some(error.to_string())),
    };
    let document = |source_root: &str,
                    completed: bool,
                    status: i32,
                    reason: Option<&str>,
                    diagnostics: &[CommandDiagnostic]| {
        native_document(
            "build",
            source_root,
            request.build_type,
            &output,
            completed,
            status,
            reason,
            &artifacts(&output, completed),
            b"",
            diagnostics,
        )
    };
    let fail = |io: &mut Io, source_root: &str, phase: &str, message: &str| -> i32 {
        let _ = writeln!(io.stderr, "{message}");
        if !structured {
            return 1;
        }
        let diagnostic = CommandDiagnostic {
            code: "MSN001".into(),
            phase: phase.into(),
            message: message.into(),
            position: Position::new(&request.filename, 1, 1),
            end: None,
            fix: None,
        };
        let reason = format!("{phase}_error");
        emit_json(
            io,
            &document(source_root, false, 1, Some(&reason), &[diagnostic]),
            1,
        )
    };

    let mut compiled = match compile(backend, &request.filename, request.build_type, false) {
        Ok(compiled) => compiled,
        Err(failure) => return Ok(report_failure(&failure, structured, &document, io)),
    };
    if let Some(error) = path_error {
        return Ok(fail(io, &compiled.source_root, "build", &error));
    }
    if std::fs::metadata(&output).is_ok_and(|m| m.is_dir()) {
        let _ = writeln!(
            io.stderr,
            "-o {display} is a directory; pass a file path (e.g. -o {})",
            gopath::join(&[display, "program"])
        );
        return Ok(2);
    }
    if let Some(protected) = protected_output(&output, &request.filename, &compiled.project_root) {
        let _ = writeln!(
            io.stderr,
            "-o {display} would overwrite {protected}; choose a different executable path"
        );
        return Ok(2);
    }
    if let Err(message) = backend.link(&mut compiled, Path::new(&output), request.build_type) {
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    if structured {
        return Ok(emit_json(
            io,
            &document(&compiled.source_root, true, 0, None, &[]),
            0,
        ));
    }
    let _ = writeln!(io.stdout, "Built {display}");
    Ok(0)
}

/// Builds the `--json` document from `(source_root, completed, status, reason, diagnostics)`.
type DocumentFn<'a> = dyn Fn(&str, bool, i32, Option<&str>, &[CommandDiagnostic]) -> Json + 'a;

/// Report compile diagnostics as text or as the command's JSON document.
fn report_failure(failure: &Failure, structured: bool, document: &DocumentFn, io: &mut Io) -> i32 {
    if !structured {
        return failure.report(io);
    }
    let diagnostics = failure.command_diagnostics();
    emit_json(
        io,
        &document(
            &failure.source_root,
            false,
            1,
            Some("compile_error"),
            &diagnostics,
        ),
        1,
    )
}

/// The source or manifest file an `-o` path would replace, or `None` when the
/// output is safe to write.
pub(super) fn protected_output(output: &str, input: &str, project_root: &str) -> Option<String> {
    let mut candidates = vec![input.to_string()];
    if !project_root.is_empty() {
        candidates.push(gopath::join(&[project_root, "ms.toml"]));
    }
    if let Ok(info) = std::fs::metadata(output) {
        for candidate in &candidates {
            if let Ok(other) = std::fs::metadata(candidate)
                && (info.dev(), info.ino()) == (other.dev(), other.ino())
            {
                return Some(gopath::base(candidate));
            }
        }
    }
    let base = gopath::base(output);
    (base.ends_with(".ms") || base == "ms.toml").then_some(base)
}

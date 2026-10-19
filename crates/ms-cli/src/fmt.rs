//! `ms fmt`: target resolution, de-duplication, reporting and in-place writes.
//! The formatter itself is the backend's [`Backend::format_source`].

use std::collections::BTreeMap;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;

use ms_project::{Project, ProjectError, discover_modules, gopath, read_project, source_path};

use crate::backend::{Backend, FormatFailure, FormatFile, Io};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::json::Json;
use crate::util::{emit_json, file_error, format_cwd, format_display};

/// Why one file or target failed, before it is rendered as a diagnostic.
enum FmtError {
    Project(ProjectError),
    Syntax { display: String, diagnostic: CommandDiagnostic },
    Drift { display: String },
    Plain(String),
}

pub fn run_format(args: &[String], backend: &dyn Backend, io: &mut Io) -> i32 {
    let (mut check, mut structured, mut positional, mut drop_labels) = (false, false, false, false);
    let mut targets: Vec<String> = Vec::new();
    for arg in args {
        match arg.as_str() {
            "--" if !positional => positional = true,
            "--check" if !positional => check = true,
            "--json" if !positional => structured = true,
            "--drop-labels" if !positional => drop_labels = true,
            _ if !positional && arg.starts_with('-') => {
                let _ = writeln!(io.stderr, "unknown option {arg} for ms fmt; run 'ms help fmt' for its options");
                return 2;
            }
            _ => targets.push(arg.clone()),
        }
    }
    if targets.is_empty() {
        let _ = writeln!(io.stderr, "ms fmt: missing a target; pass .ms files, directories, or ms.toml");
        return 2;
    }
    if structured && !check {
        let _ = writeln!(io.stderr, "--json requires ms fmt --check; remove --json to format files in place");
        return 2;
    }
    let cwd = match format_cwd() {
        Ok(cwd) => cwd,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return 1;
        }
    };
    let mut files_report: Vec<(String, &'static str)> = Vec::new();
    let mut diagnostics: Vec<CommandDiagnostic> = Vec::new();
    let mut status = 0;
    let mut report = |io: &mut Io, target: &str, error: FmtError| {
        let (diagnostic, message) = format_error(&cwd, target, error);
        diagnostics.push(diagnostic);
        if !structured {
            let _ = writeln!(io.stderr, "{message}");
        }
        status = 1;
    };
    // Resolve and deduplicate before writing. Physical identity also determines
    // display spelling, regardless of how a file was selected.
    let mut files: BTreeMap<String, String> = BTreeMap::new();
    targets.sort();
    for target in &targets {
        let paths = match format_paths(target) {
            Ok(paths) => paths,
            Err(error) => {
                report(io, target, FmtError::Project(error));
                continue;
            }
        };
        for path in paths {
            let resolved = gopath::abs(&path).and_then(|absolute| gopath::eval_symlinks(&absolute));
            match resolved {
                Ok(absolute) => {
                    let display = format_display(&cwd, &absolute);
                    files.insert(absolute, display);
                }
                Err(error) => report(io, &path, FmtError::Project(error)),
            }
        }
    }
    let mut ordered: Vec<(String, String)> = files.into_iter().collect();
    ordered.sort_by(|a, b| a.1.cmp(&b.1));
    for (path, display) in ordered {
        let file = FormatFile { path: path.clone(), display: display.clone() };
        let (state, error) = format_file(backend, &file, check, drop_labels);
        files_report.push((display, state));
        if let Some(error) = error {
            report(io, &path, error);
        }
    }
    if structured {
        sort_diagnostics(&mut diagnostics);
        let document = Json::object()
            .with("format", Json::int(1))
            .with(
                "files",
                Json::Arr(
                    files_report.iter().map(|(path, state)| Json::object().with("path", Json::str(path)).with("status", Json::str(*state))).collect(),
                ),
            )
            .with("diagnostics", Json::Arr(diagnostics.iter().map(CommandDiagnostic::to_json).collect()));
        return emit_json(io, &document, status);
    }
    status
}

/// Order by position, then code and message, so every command reports the
/// same diagnostics in the same order.
pub fn sort_diagnostics(issues: &mut [CommandDiagnostic]) {
    issues.sort_by(|a, b| {
        (&a.position.file, a.position.line, a.position.column, &a.code, &a.message).cmp(&(&b.position.file, b.position.line, b.position.column, &b.code, &b.message))
    });
}

fn format_paths(target: &str) -> Result<Vec<String>, ProjectError> {
    let info = std::fs::metadata(target).map_err(|e| ProjectError::Path(path_error("stat", target, &e)))?;
    if !info.is_dir() && gopath::base(target) != "ms.toml" {
        return Ok(vec![target.to_string()]);
    }
    let config = if info.is_dir() {
        let root = gopath::eval_symlinks(&gopath::abs(target)?)?;
        Project { root: root.clone(), source: root, ..Default::default() }
    } else {
        read_project(target)?
    };
    let mut paths = discover_modules(&config, true)?;
    if !config.entry.is_empty() {
        paths.push(config.entry.clone());
    }
    // A discovered file symlink must stay inside the selected project/directory.
    // Explicit files remain independently selectable, including through symlinks.
    let none = ms_project::Overlay::new();
    paths.into_iter().map(|path| source_path(&config.root, &path, &none)).collect()
}

fn path_error(op: &'static str, path: &str, error: &std::io::Error) -> ms_project::PathError {
    ms_project::PathError { op, path: path.to_string(), errno: error.raw_os_error().unwrap_or(0) }
}

fn format_file(backend: &dyn Backend, file: &FormatFile, check: bool, drop_labels: bool) -> (&'static str, Option<FmtError>) {
    let source = match std::fs::read(&file.path) {
        Ok(bytes) => String::from_utf8_lossy(&bytes).into_owned(),
        Err(error) => {
            let op = if error.raw_os_error() == Some(21) { "read" } else { "open" };
            return ("error", Some(FmtError::Project(ProjectError::Path(path_error(op, &file.path, &error)))));
        }
    };
    let mut text = source.clone();
    if drop_labels {
        match backend.drop_redundant_labels(file, &text) {
            Ok(changed) => text = changed,
            Err(failure) => return ("error", Some(failure_error(failure, file))),
        }
    }
    let formatted = match backend.format_source(file, &text) {
        Ok(formatted) => formatted,
        Err(failure) => return ("error", Some(failure_error(failure, file))),
    };
    if source == formatted {
        return ("clean", None);
    }
    if check {
        return ("needs_formatting", Some(FmtError::Drift { display: file.display.clone() }));
    }
    match write_formatted(&file.path, &formatted) {
        Ok(()) => ("formatted", None),
        Err(error) => ("error", Some(FmtError::Project(error))),
    }
}

fn failure_error(failure: FormatFailure, file: &FormatFile) -> FmtError {
    match failure {
        FormatFailure::Syntax(diagnostic) => FmtError::Syntax { display: file.display.clone(), diagnostic },
        FormatFailure::Message(message) => FmtError::Plain(message),
    }
}

/// Replace the file atomically, preserving its permissions.
fn write_formatted(path: &str, formatted: &str) -> Result<(), ProjectError> {
    let info = std::fs::metadata(path).map_err(|e| ProjectError::Path(path_error("stat", path, &e)))?;
    let directory = gopath::dir(path);
    let temp = gopath::join(&[&directory, &format!(".manuscript-format-{}-{}", std::process::id(), unique())]);
    let result = (|| -> std::io::Result<()> {
        std::fs::write(&temp, formatted)?;
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(info.permissions().mode() & 0o777))?;
        std::fs::rename(&temp, path)
    })();
    if let Err(error) = result {
        let _ = std::fs::remove_file(&temp);
        return Err(ProjectError::Path(path_error("rename", path, &error)));
    }
    Ok(())
}

fn unique() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// The diagnostic and terminal message for a failure.
fn format_error(cwd: &str, target: &str, error: FmtError) -> (CommandDiagnostic, String) {
    let mut display = format_display(cwd, target);
    let mut code = "MSF002";
    let mut message;
    match error {
        FmtError::Syntax { display: shown, diagnostic } => {
            let message = format!(
                "{}\nfmt only formats source that parses; fix the syntax error above, then re-run ms fmt {shown}",
                diagnostic.rendered()
            );
            return (diagnostic, message);
        }
        FmtError::Project(ProjectError::Manifest(manifest)) => {
            let cause = manifest.cause.to_string();
            let position = Position { file: display.clone(), line: manifest.location.line, column: manifest.location.column, offset: manifest.location.offset };
            let diagnostic = CommandDiagnostic::source("resolution", &cause, position);
            let console = format!("{}:{}:{}: {}", display, manifest.location.line, manifest.location.column, cause);
            return (diagnostic, console);
        }
        FmtError::Project(ProjectError::Path(path_error)) => {
            let shown = format_display(cwd, &path_error.path);
            message = file_error(&ProjectError::Path(ms_project::PathError { path: shown.clone(), ..path_error }));
            display = shown;
        }
        FmtError::Project(other) => message = other.to_string(),
        FmtError::Drift { display: shown } => {
            code = "MSF001";
            message = format!("Formatting needed: {shown}; run ms fmt {shown} to rewrite it");
        }
        FmtError::Plain(text) => message = text,
    }
    let diagnostic = CommandDiagnostic {
        code: code.to_string(),
        phase: "format".to_string(),
        message: message.clone(),
        position: Position::new(display, 1, 1),
        end: None,
        fix: None,
    };
    (diagnostic, message)
}

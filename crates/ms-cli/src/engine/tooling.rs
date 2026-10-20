//! `ms lint`, `ms inspect`, `ms diagram`, `ms review` and `ms fmt --drop-labels`:
//! the source tools, over a program the checker has accepted.

use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;
use std::time::{Duration, Instant, SystemTime};

use ms_driver::{CheckRequest, Checked, EditorOptions, LoadOptions, check_graph, load_editor_file};
use ms_project::{Overlay, ProjectError, gopath};
use ms_tooling::collect::collect_facts;
use ms_tooling::diagram::diagram_ascii;
use ms_tooling::diff::{DiffFile, parse_diff, removed_content, reverse_apply};
use ms_tooling::facts::Facts;
use ms_tooling::inspect::inspect;
use ms_tooling::mark::{explain, mark_changes};
use ms_tooling::report::{ReviewOptions, diff_report, project_report};
use ms_tooling::review::{DiffInput, compare_facts};
use ms_tooling::views::build_view;

use super::build::protected_output;
use super::{Failure, command_diagnostic};
use crate::analysis::{AnalysisInput, AnalysisSelection, select_analysis_inputs};
use crate::backend::{
    AnalysisCommand, AnalysisRequest, BackendResult, DiagramRequest, FormatFailure, FormatFile, Io,
    OutputRequest, ReviewRequest,
};
use crate::diagnostic::{CommandDiagnostic, Position, diagnostics_document};
use crate::process::Stops;
use crate::util::{emit_json, file_error, plural, write_output};

/// Load and check `filename` the way the source tools do: no lowering, and
/// `main` is required only for a project manifest that has an entry.
fn analyze(filename: &str, overlay: &Overlay) -> Checked {
    analyze_with(filename, overlay, false, true)
}

/// `project_sources` also checks every source file of a manifest's project
/// (`ms check`); `entry` allows the entry requirement (never for `ms lint`).
pub(super) fn analyze_with(
    filename: &str,
    overlay: &Overlay,
    project_sources: bool,
    entry: bool,
) -> Checked {
    let editor = EditorOptions {
        overlay: overlay.clone(),
        project_sources,
        ..EditorOptions::default()
    };
    let graph = load_editor_file(filename, LoadOptions::default(), &editor);
    let entry = entry && !graph.library && gopath::base(filename) == "ms.toml";
    check_graph(
        graph,
        CheckRequest {
            entry,
            ..CheckRequest::default()
        },
    )
}

/// The checked program, or the failure that stopped it.
fn accepted(filename: &str, overlay: &Overlay) -> Result<Checked, Failure> {
    let checked = analyze(filename, overlay);
    if checked.success() && checked.program.is_some() {
        return Ok(checked);
    }
    Err(Failure {
        source_root: checked.source_root,
        diagnostics: checked.diagnostics,
    })
}

fn failure_status(failure: &Failure, json: bool, io: &mut Io) -> i32 {
    if json {
        return emit_json(io, &diagnostics_document(&failure.command_diagnostics()), 1);
    }
    failure.report(io)
}

fn facts_of(checked: &Checked) -> Facts {
    let program = checked.program.as_ref().expect("accepted program");
    collect_facts(&inspect(program).rows(), program)
}

/// `ms check` and `ms lint`; `--watch` repeats the run after each saved change.
pub(super) fn analysis(request: &AnalysisRequest, io: &mut Io) -> BackendResult {
    if !request.watch {
        return Ok(analysis_once(request, io).0);
    }
    let stops = Stops::catch();
    let mut watched = BTreeMap::new();
    let mut due = Some(Instant::now());
    loop {
        if due.is_some_and(|at| Instant::now() >= at) {
            due = None;
            let (_, files) = analysis_once(request, io);
            watched = files
                .into_iter()
                .chain(request.targets.iter().filter_map(|t| absolute(t)))
                .map(|path| (path.clone(), file_state(&path)))
                .collect();
            let _ = writeln!(io.stderr, "ms: waiting for changes");
            let _ = io.stdout.flush();
        }
        std::thread::sleep(WATCH_INTERVAL);
        if stops.take().is_some() {
            return Ok(130);
        }
        for (path, previous) in &mut watched {
            let current = file_state(path);
            if current != *previous {
                *previous = current;
                due = Some(Instant::now() + WATCH_SETTLE);
            }
        }
    }
}

/// One run of the command, and the files that decide its result.
fn analysis_once(request: &AnalysisRequest, io: &mut Io) -> (i32, Vec<String>) {
    let check = request.command == AnalysisCommand::Check;
    let selection = match select_analysis_inputs(&request.targets) {
        Ok(selection) => selection,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return (1, Vec::new());
        }
    };
    let mut analyzed = Vec::new();
    let mut files = Vec::new();
    let mut issues = selection.diagnostics.clone();
    for input in &selection.inputs {
        let checked = analyze_with(&input.path, &Overlay::new(), check, check);
        files.extend(watched_files(&input.path, &checked));
        for issue in &checked.diagnostics {
            issues.push(placed(&selection, &checked.source_root, issue));
        }
        analyzed.push(checked);
    }
    let mut diagnostics = issues.clone();
    for (input, checked) in selection.inputs.iter().zip(&analyzed) {
        let Some(program) = checked.program.as_ref().filter(|_| checked.success()) else {
            continue;
        };
        if check {
            if !request.json {
                let _ = writeln!(io.stdout, "{}", checked_line(input, checked));
            }
            continue;
        }
        for finding in ms_tooling::lint::lint_modules(program) {
            let at = Position {
                file: finding.file.to_string(),
                line: finding.pos.line as usize,
                column: finding.pos.column as usize,
                offset: finding.pos.offset as usize,
            };
            diagnostics.push(CommandDiagnostic {
                code: finding.code.to_string(),
                message: finding.message,
                position: selection.position(&checked.source_root, &at),
                ..CommandDiagnostic::default()
            });
        }
    }
    if selection.collection {
        diagnostics = ordered(diagnostics);
    }
    let status = i32::from(!diagnostics.is_empty());
    if request.json {
        return (
            emit_json(io, &diagnostics_document(&diagnostics), status),
            files,
        );
    }
    let root = match analyzed.as_slice() {
        [only] if !selection.collection => only.source_root.as_str(),
        _ => "",
    };
    for issue in &diagnostics {
        let mut position = issue.position.clone();
        if !root.is_empty() && !gopath::is_abs(&position.file) {
            position.file = gopath::join(&[root, &position.file]);
        }
        let label = if issue.phase.is_empty() {
            &issue.code
        } else {
            &issue.phase
        };
        let _ = writeln!(io.stderr, "{position}: {label}: {}", issue.message);
    }
    if !issues.is_empty() {
        let count = diagnostics.iter().filter(|d| !d.phase.is_empty()).count();
        let _ = writeln!(
            io.stderr,
            "{count} {}; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)",
            plural(count, "error", "errors")
        );
    }
    (status, files)
}

/// The check summary for one input that passed.
fn checked_line(input: &AnalysisInput, checked: &Checked) -> String {
    let Some(program) = checked
        .program
        .as_ref()
        .filter(|_| !checked.project_root.is_empty())
    else {
        return format!("Checked {}", input.display);
    };
    let count = program.modules.iter().filter(|m| !m.is_standard()).count();
    format!(
        "Checked {} ({count} {})",
        input.display,
        plural(count, "module", "modules")
    )
}

/// How often watched files are polled, and how long a change settles before
/// the rerun (editors often save in several steps).
pub(super) const WATCH_INTERVAL: Duration = Duration::from_millis(10);
pub(super) const WATCH_SETTLE: Duration = Duration::from_millis(10);

/// The input, its manifest, and every local module the analysis loaded.
pub(super) fn watched_files(input: &str, checked: &Checked) -> Vec<String> {
    let mut files = Vec::new();
    files.extend(absolute(input));
    if !checked.project_root.is_empty() {
        files.push(gopath::join(&[&checked.project_root, "ms.toml"]));
    }
    let Some(program) = &checked.program else {
        return files;
    };
    for module in program.modules.iter().filter(|m| !m.is_standard()) {
        let file = module.file.as_str();
        if gopath::is_abs(file) || checked.source_root.is_empty() {
            files.extend(absolute(file));
        } else {
            files.extend(absolute(&gopath::join(&[&checked.source_root, file])));
        }
    }
    files
}

pub(super) fn absolute(path: &str) -> Option<String> {
    let path = std::path::absolute(path).ok()?;
    Some(path.to_string_lossy().into_owned())
}

#[derive(PartialEq)]
pub(super) struct FileState {
    size: u64,
    modified: Option<SystemTime>,
}

/// `None` for a file that does not exist.
pub(super) fn file_state(path: &str) -> Option<FileState> {
    let meta = std::fs::metadata(path).ok()?;
    Some(FileState {
        size: meta.len(),
        modified: meta.modified().ok(),
    })
}

/// A compiler diagnostic with its positions in the display form of a collection.
fn placed(
    selection: &AnalysisSelection,
    root: &str,
    issue: &ms_driver::Diagnostic,
) -> CommandDiagnostic {
    let mut diagnostic = command_diagnostic(issue);
    diagnostic.position = selection.position(root, &diagnostic.position);
    diagnostic.end = diagnostic.end.map(|end| selection.position(root, &end));
    diagnostic
}

/// Drop repeats, then order by position, code and message.
fn ordered(diagnostics: Vec<CommandDiagnostic>) -> Vec<CommandDiagnostic> {
    let mut seen = BTreeSet::new();
    let mut unique: Vec<CommandDiagnostic> = diagnostics
        .into_iter()
        .filter(|d| seen.insert(d.to_json().encode()))
        .collect();
    unique.sort_by(|a, b| {
        let key = |d: &CommandDiagnostic| {
            (
                d.position.file.clone(),
                d.position.line,
                d.position.column,
                d.code.clone(),
                d.message.clone(),
            )
        };
        key(a).cmp(&key(b))
    });
    unique
}

/// The source of a program that checks, before any output is chosen.
fn source_program(
    filename: &str,
    output: &str,
    json: bool,
    io: &mut Io,
) -> Result<Checked, BackendResult> {
    let checked = match accepted(filename, &Overlay::new()) {
        Ok(checked) => checked,
        Err(failure) => return Err(Ok(failure_status(&failure, json, io))),
    };
    if !output.is_empty()
        && let Some(protected) = protected_output(output, filename, &checked.project_root)
    {
        let _ = writeln!(
            io.stderr,
            "-o {output} would overwrite {protected}; choose a different output path"
        );
        return Err(Ok(2));
    }
    Ok(checked)
}

pub(super) fn inspect_command(request: &OutputRequest, io: &mut Io) -> BackendResult {
    let checked = match source_program(&request.filename, &request.output, request.json, io) {
        Ok(checked) => checked,
        Err(done) => return done,
    };
    let program = checked.program.as_ref().expect("accepted program");
    let mut text = inspect(program).to_json().encode();
    text.push('\n');
    Ok(write_output(io, &request.output, text.as_bytes()))
}

pub(super) fn diagram(request: &DiagramRequest, io: &mut Io) -> BackendResult {
    let checked = match source_program(&request.filename, &request.output, request.json, io) {
        Ok(checked) => checked,
        Err(done) => return done,
    };
    if !request.view.is_empty() || !request.entity.is_empty() {
        return Ok(view(request, &checked, io));
    }
    let program = checked.program.as_ref().expect("accepted program");
    let inspection = inspect(program);
    let text = if request.format == "mermaid" {
        inspection.mermaid()
    } else {
        diagram_ascii(&inspection.rows())
    };
    Ok(write_output(io, &request.output, text.as_bytes()))
}

/// One scoped diagram view, optionally marked with what a diff changes.
fn view(request: &DiagramRequest, head: &Checked, io: &mut Io) -> i32 {
    let name = if request.view.is_empty() {
        "calls"
    } else {
        &request.view
    };
    let facts = facts_of(head);
    let mut tree = match build_view(&facts, name, &request.entity, request.depth as i64) {
        Ok(tree) => tree,
        Err(message) => {
            let _ = writeln!(io.stderr, "ms diagram: {message}");
            return 2;
        }
    };
    if !request.diff.is_empty() {
        let (input, base) = match diff_inputs(&request.filename, &request.diff, head, io) {
            Ok(inputs) => inputs,
            Err(status) => return status,
        };
        mark_changes(
            &mut tree,
            &compare_facts(&base, &facts, &input),
            &input.touched,
        );
    }
    let text = if request.format == "mermaid" {
        tree.mermaid()
    } else {
        tree.ascii()
    };
    write_output(io, &request.output, text.as_bytes())
}

pub(super) fn review(request: &ReviewRequest, io: &mut Io) -> BackendResult {
    let head = match accepted(&request.filename, &Overlay::new()) {
        Ok(head) => head,
        Err(failure) => return Ok(failure.report(io)),
    };
    let head_facts = facts_of(&head);
    let options = ReviewOptions { all: request.all };
    if request.diff.is_empty() {
        let report = project_report(&head_facts, options);
        return Ok(write_output(
            io,
            &request.output,
            report.render(&request.format).as_bytes(),
        ));
    }
    let (input, base) = match diff_inputs(&request.filename, &request.diff, &head, io) {
        Ok(inputs) => inputs,
        Err(status) => return Ok(status),
    };
    if !request.explain.is_empty() {
        let findings = compare_facts(&base, &head_facts, &input);
        return Ok(match explain(&findings, &head_facts, &request.explain) {
            Ok(text) => write_output(io, &request.output, text.as_bytes()),
            Err(message) => {
                let _ = writeln!(io.stderr, "ms review: {message}");
                2
            }
        });
    }
    let report = diff_report(&base, &head_facts, &input, options);
    Ok(write_output(
        io,
        &request.output,
        report.render(&request.format).as_bytes(),
    ))
}

/// Reads the unified diff, rebuilds the base program from it, and returns the
/// change summary with the base facts; an error carries the status of a
/// problem already reported.
fn diff_inputs(
    filename: &str,
    diff: &str,
    head: &Checked,
    io: &mut Io,
) -> Result<(DiffInput, Facts), i32> {
    let mut fail = |status: i32, message: String| {
        let _ = writeln!(io.stderr, "{message}");
        status
    };
    let text = match read_diff(diff, io.stdin) {
        Ok(text) => text,
        Err(message) => return Err(fail(2, message)),
    };
    let files = match parse_diff(&text) {
        Ok(files) => files,
        Err(message) => {
            return Err(fail(
                2,
                format!(
                    "ms review: {message}; pass a unified diff such as git diff --no-renames main..."
                ),
            ));
        }
    };
    let root = if head.project_root.is_empty() {
        match gopath::abs(filename) {
            Ok(absolute) => gopath::dir(&absolute),
            Err(error) => return Err(fail(2, file_error(&error))),
        }
    } else {
        head.project_root.clone()
    };
    let (mut input, overlay) = match review_input(&files, &root) {
        Ok(found) => found,
        Err(message) => {
            return Err(fail(
                2,
                format!(
                    "ms review: diff does not match the tree: {message}; run it from the checkout the diff was made against"
                ),
            ));
        }
    };
    let mut base = Facts::default();
    if let Ok(checked) = accepted(filename, &overlay) {
        input.base_checked = true;
        base = facts_of(&checked);
    }
    Ok((input, base))
}

fn read_diff(path: &str, stdin: &mut dyn Read) -> Result<String, String> {
    let mut data = Vec::new();
    let read = if path == "-" {
        stdin.read_to_end(&mut data).map(|_| ())
    } else {
        std::fs::read(path).map(|bytes| data = bytes)
    };
    match read {
        Ok(()) => Ok(String::from_utf8_lossy(&data).into_owned()),
        Err(error) => Err(format!(
            "ms review: cannot read the diff: {}",
            file_error(&ProjectError::path("open", path, &error))
        )),
    }
}

/// Maps the diff onto the project and rebuilds each changed file's base text
/// into an overlay. Only `.ms` files inside the project take part.
fn review_input(files: &[DiffFile], root: &str) -> Result<(DiffInput, Overlay), String> {
    let mut input = DiffInput {
        files: files.len(),
        ..DiffInput::default()
    };
    let mut overlay = Overlay::new();
    for file in files {
        for hunk in &file.hunks {
            for line in &hunk.lines {
                match line.as_bytes()[0] {
                    b'+' => input.insertions += 1,
                    b'-' => input.deletions += 1,
                    _ => {}
                }
            }
        }
        if gopath::ext(file.path()) != ".ms" {
            continue;
        }
        let absolute = locate_diff_path(root, file.path(), file.new.is_empty());
        let Ok(relative) = gopath::rel(root, &absolute) else {
            continue;
        };
        if relative.starts_with("..") {
            continue;
        }
        input.sources += 1;
        if file.old.is_empty() {
            input.added.insert(relative.clone());
        } else if file.new.is_empty() {
            overlay.insert(absolute, removed_content(&file.hunks));
        } else {
            let head = std::fs::read(&absolute).map_err(|error| {
                format!(
                    "{}: {}",
                    file.path(),
                    file_error(&ProjectError::path("open", &absolute, &error))
                )
            })?;
            let base = reverse_apply(&String::from_utf8_lossy(&head), &file.hunks)
                .map_err(|message| format!("{}: {message}", file.path()))?;
            overlay.insert(absolute, base);
        }
        if !file.new.is_empty() {
            input.touched.insert(relative, file.touched_lines());
        }
    }
    Ok((input, overlay))
}

/// Finds the diff's repository-relative path at or above the project root,
/// since the project may live in a subdirectory of the checkout.
fn locate_diff_path(root: &str, path: &str, deleted: bool) -> String {
    let mut dir = root.to_string();
    loop {
        let candidate = gopath::join(&[&dir, path]);
        let target = if deleted {
            gopath::dir(&candidate)
        } else {
            candidate.clone()
        };
        if std::fs::metadata(&target).is_ok() {
            return candidate;
        }
        let parent = gopath::dir(&dir);
        if parent == dir {
            return gopath::join(&[root, path]);
        }
        dir = parent;
    }
}

pub(super) fn drop_redundant_labels(
    file: &FormatFile,
    source: &str,
) -> Result<String, FormatFailure> {
    let checked = analyze(&file.path, &Overlay::new());
    let program = checked.program.as_ref().filter(|_| checked.success());
    let Some(program) = program else {
        let Some(first) = checked.diagnostics.first() else {
            return Err(FormatFailure::Message(format!(
                "{}: --drop-labels needs source that checks",
                file.display
            )));
        };
        return Err(FormatFailure::Message(format!(
            "{}:{}:{}: {}: {}\n--drop-labels needs source that checks ({} error(s)); fix them, then re-run ms fmt --drop-labels {}",
            file.display,
            first.pos.line,
            first.pos.column,
            first.phase.as_str(),
            first.message,
            checked.diagnostics.len(),
            file.display
        )));
    };
    Ok(ms_tooling::labels::drop_redundant_labels(program, source).0)
}

/// `ms fmt`: the formatter in `ms-syntax`; source that does not parse is reported, never rewritten.
pub(super) fn format_source(file: &FormatFile, source: &str) -> Result<String, FormatFailure> {
    let name: std::sync::Arc<str> = file.display.as_str().into();
    ms_syntax::format::format(&name, source)
        .map_err(|issue| FormatFailure::Syntax(Box::new(command_diagnostic(&issue))))
}

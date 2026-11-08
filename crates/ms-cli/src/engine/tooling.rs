//! `ms lint`, `ms inspect`, `ms diagram`, `ms review` and `ms fmt --drop-labels`:
//! the source tools, over a program the checker has accepted.

use std::collections::{BTreeMap, BTreeSet};
use std::io::{Read, Write};
use std::time::{Duration, Instant, SystemTime};

use ms_driver::project::{Overlay, ProjectError, pathops};
use ms_driver::{CheckRequest, Checked, EditorOptions, LoadOptions, check_graph, load_editor_file};
use ms_tooling::collect::collect_facts;
use ms_tooling::diagram::diagram_ascii;
use ms_tooling::diff::{DiffFile, parse_diff, removed_content, reverse_apply};
use ms_tooling::facts::Facts;
use ms_tooling::inspect::inspect;
use ms_tooling::mark::{explain, explain_json, mark_changes};
use ms_tooling::report::{ReviewOptions, diff_report, project_report};
use ms_tooling::review::{DiffInput, compare_facts};
use ms_tooling::views::{ascii_view, build_view, mermaid_view};

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
fn analyze(syms: ms_syntax::Names, filename: &str, overlay: &Overlay) -> Checked {
    analyze_with(syms, filename, overlay, false, true)
}

/// `project_sources` also checks every source file of a manifest's project
/// (`ms check`); `entry` allows the entry requirement (never for `ms lint`).
pub(super) fn analyze_with(
    syms: ms_syntax::Names,
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
    let graph = load_editor_file(syms, filename, LoadOptions::default(), &editor);
    let entry = entry && !graph.library && pathops::base(filename) == "ms.toml";
    check_graph(syms, graph, CheckRequest { entry })
}

/// The checked program, or the failure that stopped it.
/// `project` also loads a manifest's discovered test files, as `ms check` does.
fn accepted(
    syms: ms_syntax::Names,
    filename: &str,
    overlay: &Overlay,
    project: bool,
) -> Result<Checked, Failure> {
    let checked = analyze_with(syms, filename, overlay, project, true);
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

fn facts_of(syms: ms_syntax::Names, checked: &Checked) -> Facts {
    let program = checked.program.as_ref().expect("accepted program");
    collect_facts(syms, &inspect(syms, program).rows(), program)
}

/// `ms check` and `ms lint`; `--watch` repeats the run after each saved change.
pub fn analysis(syms: ms_syntax::Names, request: &AnalysisRequest, io: &mut Io) -> BackendResult {
    if !request.watch {
        return Ok(analysis_once(syms, request, FIX_PASSES, io).0);
    }
    let stops = Stops::catch();
    let mut watched = BTreeMap::new();
    let mut due = Some(Instant::now());
    loop {
        if due.is_some_and(|at| Instant::now() >= at) {
            due = None;
            let started = SystemTime::now();
            let (_, files) = analysis_once(syms, request, FIX_PASSES, io);
            // A file that dropped out of the graph (a broken import loads no modules) stays
            // watched, so repairing it reruns the check.
            watched = observed(
                std::mem::take(&mut watched),
                files
                    .into_iter()
                    .chain(request.targets.iter().filter_map(|t| absolute(t))),
                started,
            );
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

/// Rounds of `--fix` per run; fixes that regenerate each other stop here.
const FIX_PASSES: u8 = 8;

/// One run of the command, and the files that decide its result.
fn analysis_once(
    syms: ms_syntax::Names,
    request: &AnalysisRequest,
    fix_passes: u8,
    io: &mut Io,
) -> (i32, Vec<String>) {
    let check = request.command == AnalysisCommand::Check;
    let selection = match select_analysis_inputs(&request.targets) {
        Ok(selection) => selection,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return (1, Vec::new());
        }
    };
    let mut files = Vec::new();
    let mut fixes: Vec<(String, ms_driver::DiagnosticFix)> = Vec::new();
    let mut diagnostics = selection.diagnostics.clone();
    let mut findings = Vec::new();
    let mut summaries = Vec::new();
    let mut root = String::new();
    // The terminal output, written at the end or, with `--json --with-text`, carried in the document.
    let text = !request.json || request.with_text;
    let mut text_out: Vec<u8> = Vec::new();
    let mut text_err: Vec<u8> = Vec::new();
    if selection.inputs.is_empty() && selection.diagnostics.is_empty() && text {
        let _ = writeln!(
            text_err,
            "ms {}: no .ms files found in {}",
            if check { "check" } else { "lint" },
            request.targets.join(", ")
        );
    }
    files.extend(selection.scanned.iter().cloned());
    for input in &selection.inputs {
        let checked = analyze_with(syms, &input.path, &Overlay::new(), check, check);
        if request.fix {
            fixes.extend(source_fixes(&checked));
        }
        files.extend(watched_files(syms, &input.path, &checked));
        for issue in &checked.diagnostics {
            diagnostics.push(placed(&selection, &checked.source_root, issue));
        }
        if selection.inputs.len() == 1 && !selection.collection {
            root.clone_from(&checked.source_root);
        }
        let Some(program) = checked.program.as_ref().filter(|_| checked.success()) else {
            continue;
        };
        if check {
            if text {
                summaries.push(checked_line(syms, input, &checked));
            }
            continue;
        }
        for finding in ms_tooling::lint::lint_modules(syms, program) {
            if request.fix
                && let Some(fix) = &finding.fix
            {
                let file = finding.file.as_ref();
                let path = if pathops::is_abs(file) || checked.source_root.is_empty() {
                    file.to_string()
                } else {
                    pathops::join(&[&checked.source_root, file])
                };
                fixes.push((path, fix.clone()));
            }
            let at = Position {
                file: finding.file.to_string(),
                line: finding.pos.line as usize,
                column: finding.pos.column as usize,
                offset: finding.pos.offset as usize,
            };
            findings.push(CommandDiagnostic {
                code: finding.code.to_string(),
                severity: finding.severity.name().to_string(),
                message: finding.message,
                position: selection.position(&checked.source_root, &at),
                fix: finding.fix.as_ref().map(|fix| {
                    let place = |pos: ms_driver::Pos| {
                        selection.position(
                            &checked.source_root,
                            &Position {
                                file: finding.file.to_string(),
                                line: pos.line as usize,
                                column: pos.column as usize,
                                offset: pos.offset as usize,
                            },
                        )
                    };
                    super::fix_json(&place, fix)
                }),
                ..CommandDiagnostic::default()
            });
        }
    }
    if request.fix {
        let (applied, edited) = apply_fixes(fixes, io);
        if applied > 0 {
            let _ = writeln!(
                io.stderr,
                "ms: applied {applied} {} in {edited} {}",
                plural(applied, "fix", "fixes"),
                plural(edited, "file", "files")
            );
            // A fix that overlapped an applied one, or a diagnostic the checker only
            // reaches once an earlier one is gone, is found again on the rerun.
            let rerun = AnalysisRequest {
                fix: fix_passes > 1,
                ..request.clone()
            };
            return analysis_once(syms, &rerun, fix_passes.saturating_sub(1), io);
        }
    }
    // Keep compiler diagnostics ahead of lint findings and defer output until
    // every input has been checked, without retaining their checked programs.
    let has_errors = !diagnostics.is_empty();
    diagnostics.extend(findings);
    for summary in summaries {
        let _ = writeln!(text_out, "{summary}");
    }
    if selection.collection {
        diagnostics = ordered(diagnostics);
    } else if diagnostics.iter().all(|d| d.phase == "parse") {
        // One file's recovered syntax errors, in source order.
        diagnostics.sort_by_key(|d| (d.position.file.clone(), d.position.line, d.position.column));
    }
    let failing = |d: &CommandDiagnostic| d.severity != "warning" || request.deny_warnings;
    let status = i32::from(diagnostics.iter().any(failing));
    if text {
        let mut sources = crate::snippet::Sources::default();
        for issue in &diagnostics {
            let mut position = issue.position.clone();
            if !root.is_empty() && !pathops::is_abs(&position.file) {
                position.file = pathops::join(&[&root, &position.file]);
            }
            let label = if !issue.phase.is_empty() {
                &issue.phase
            } else if issue.severity == "warning" {
                &format!("warning {}", issue.code)
            } else {
                &issue.code
            };
            let end = issue.end.as_ref().map(|e| (e.line, e.column));
            let excerpt = sources.excerpt(&position.file, position.line, position.column, end);
            let _ = writeln!(text_err, "{position}: {label}: {}{excerpt}", issue.message);
        }
        if has_errors {
            let count = diagnostics.iter().filter(|d| !d.phase.is_empty()).count();
            let _ = writeln!(
                text_err,
                "{count} {}; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)",
                plural(count, "error", "errors")
            );
        }
        let warnings = diagnostics
            .iter()
            .filter(|d| d.severity == "warning")
            .count();
        if warnings > 0 {
            let note = if request.deny_warnings {
                "failing because of --deny-warnings"
            } else {
                "warnings do not fail ms lint; pass --deny-warnings to fail on them"
            };
            let _ = writeln!(
                text_err,
                "{warnings} {}; {note}",
                plural(warnings, "warning", "warnings")
            );
        }
    }
    if request.json {
        let mut document = diagnostics_document(&diagnostics);
        if request.with_text {
            let utf8 = |bytes: Vec<u8>| String::from_utf8_lossy(&bytes).into_owned();
            document = document.with(
                "text",
                crate::json::Json::object()
                    .with("stdout", crate::json::Json::str(utf8(text_out)))
                    .with("stderr", crate::json::Json::str(utf8(text_err))),
            );
        }
        return (emit_json(io, &document, status), files);
    }
    let _ = io.stdout.write_all(&text_out);
    let _ = io.stderr.write_all(&text_err);
    (status, files)
}

/// Each fixable diagnostic of `checked` with the path of the file it edits.
fn source_fixes(checked: &Checked) -> Vec<(String, ms_driver::DiagnosticFix)> {
    let mut fixes = Vec::new();
    for issue in &checked.diagnostics {
        let Some(fix) = &issue.fix else { continue };
        let file = issue.file.as_ref();
        if file.starts_with("@std/") {
            continue;
        }
        let path = if pathops::is_abs(file) || checked.source_root.is_empty() {
            file.to_string()
        } else {
            pathops::join(&[&checked.source_root, file])
        };
        fixes.push((path, fix.clone()));
    }
    fixes
}

/// Applies the fixes in place, last edit first so offsets stay valid. A fix
/// that is repeated or overlaps an earlier one waits for the next run.
/// Returns the fixes applied, the files changed, and whether any fix waited.
fn apply_fixes(fixes: Vec<(String, ms_driver::DiagnosticFix)>, io: &mut Io) -> (usize, usize) {
    let mut by_file: BTreeMap<String, Vec<ms_driver::DiagnosticFix>> = BTreeMap::new();
    for (path, fix) in fixes {
        by_file.entry(path).or_default().push(fix);
    }
    let (mut applied, mut edited) = (0, 0);
    for (path, mut file_fixes) in by_file {
        file_fixes.sort_by_key(|f| (f.pos.offset, f.end.offset));
        file_fixes.dedup();
        let Ok(mut text) = std::fs::read_to_string(&path) else {
            continue;
        };
        let mut chosen: Vec<&ms_driver::DiagnosticFix> = Vec::new();
        let mut last_end = 0;
        for fix in &file_fixes {
            let (start, end) = (fix.pos.offset as usize, fix.end.offset as usize);
            let valid = start <= end
                && end <= text.len()
                && text.is_char_boundary(start)
                && text.is_char_boundary(end);
            if valid && (chosen.is_empty() || start >= last_end) {
                last_end = end;
                chosen.push(fix);
            }
        }
        if chosen.is_empty() {
            continue;
        }
        for fix in chosen.iter().rev() {
            text.replace_range(
                fix.pos.offset as usize..fix.end.offset as usize,
                &fix.replacement,
            );
        }
        if let Err(error) = std::fs::write(&path, &text) {
            let _ = writeln!(io.stderr, "ms: cannot write {path}: {error}");
            continue;
        }
        applied += chosen.len();
        edited += 1;
    }
    (applied, edited)
}

/// The check summary for one input that passed.
fn checked_line(syms: ms_syntax::Names, input: &AnalysisInput, checked: &Checked) -> String {
    let Some(program) = checked
        .program
        .as_ref()
        .filter(|_| !checked.project_root.is_empty())
    else {
        return format!("Checked {}", input.display);
    };
    let count = program
        .modules
        .iter()
        .filter(|m| !m.is_standard(syms))
        .count();
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

/// The input, its manifest, and local source paths attempted by the loader.
pub(super) fn watched_files(syms: ms_syntax::Names, input: &str, checked: &Checked) -> Vec<String> {
    let mut files = Vec::new();
    files.extend(absolute(input));
    if !checked.project_root.is_empty() {
        let manifest = pathops::join(&[&checked.project_root, "ms.toml"]);
        // A new source or test file appears in a directory discovery walks, not in the graph.
        if let Ok(project) = ms_driver::project::read_project(&manifest) {
            files.extend(ms_driver::project::discovered_directories(&project));
        }
        files.push(manifest);
    }
    files.extend(checked.inputs.iter().cloned());
    let Some(program) = &checked.program else {
        return files;
    };
    for module in program.modules.iter().filter(|m| !m.is_standard(syms)) {
        let file = syms.str(module.file);
        if pathops::is_abs(file) || checked.source_root.is_empty() {
            files.extend(absolute(file));
        } else {
            files.extend(absolute(&pathops::join(&[&checked.source_root, file])));
        }
    }
    files
}

pub(super) fn absolute(path: &str) -> Option<String> {
    let path = std::path::absolute(path).ok()?;
    Some(path.to_string_lossy().into_owned())
}

#[derive(Clone, PartialEq)]
pub(super) struct FileState {
    size: u64,
    modified: Option<SystemTime>,
    /// Where a symbolic link points: retargeting it changes what an import resolves to.
    link: Option<std::path::PathBuf>,
    /// Mode bits (or the read-only flag): repairing a permission rereads a failed source.
    permissions: std::fs::Permissions,
    /// Set for a file changed after the analysis began, which the analysis may not have read.
    unobserved: bool,
}

/// `None` for a file that does not exist.
pub(super) fn file_state(path: &str) -> Option<FileState> {
    let meta = std::fs::metadata(path).ok()?;
    Some(FileState {
        size: meta.len(),
        modified: meta.modified().ok(),
        link: std::fs::read_link(path).ok(),
        permissions: meta.permissions(),
        unobserved: false,
    })
}

/// The watched states after an analysis that began at `started`. A file watched before keeps
/// its earlier state, so an edit made while the analysis ran still differs at the next poll.
/// A file the analysis found is stamped against `started`. A file that dropped out of the graph
/// (a broken import loads no modules) stays watched, so repairing it reruns.
pub(super) fn observed(
    mut before: BTreeMap<String, Option<FileState>>,
    paths: impl Iterator<Item = String>,
    started: SystemTime,
) -> BTreeMap<String, Option<FileState>> {
    let mut now = BTreeMap::new();
    for path in paths {
        let state = match before.remove(&path) {
            Some(known) => known,
            None => state_after(&path, started),
        };
        now.insert(path, state);
    }
    for (path, state) in before {
        now.entry(path).or_insert(state);
    }
    now
}

/// The state of `path` as the analysis that began at `started` saw it. A file modified since
/// may have been read before its edit, so its state never matches: the next poll reruns.
pub(super) fn state_after(path: &str, started: SystemTime) -> Option<FileState> {
    let mut state = file_state(path)?;
    state.unobserved = state.modified.is_some_and(|modified| modified > started);
    Some(state)
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
        .filter(|d| seen.insert(d.to_json().pretty_line(ms_json::Escape::HtmlSafe)))
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
    syms: ms_syntax::Names,
    filename: &str,
    output: &str,
    json: bool,
    project: bool,
    io: &mut Io,
) -> Result<Checked, BackendResult> {
    let checked = match accepted(syms, filename, &Overlay::new(), project) {
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

pub fn inspect_command(
    syms: ms_syntax::Names,
    request: &OutputRequest,
    io: &mut Io,
) -> BackendResult {
    let checked = match source_program(
        syms,
        &request.filename,
        &request.output,
        request.json,
        false,
        io,
    ) {
        Ok(checked) => checked,
        Err(done) => return done,
    };
    let program = checked.program.as_ref().expect("accepted program");
    let mut text = inspect(syms, program)
        .to_json()
        .pretty_line(ms_json::Escape::HtmlSafe);
    text.push('\n');
    Ok(write_output(io, &request.output, text.as_bytes()))
}

pub fn diagram(syms: ms_syntax::Names, request: &DiagramRequest, io: &mut Io) -> BackendResult {
    let checked = match source_program(
        syms,
        &request.filename,
        &request.output,
        request.json,
        false,
        io,
    ) {
        Ok(checked) => checked,
        Err(done) => return done,
    };
    if request.json
        || !request.view.is_empty()
        || !request.entity.is_empty()
        || request.format == "html"
    {
        return Ok(view(syms, request, &checked, io));
    }
    let program = checked.program.as_ref().expect("accepted program");
    let mut inspection = inspect(syms, program);
    // Keep application structure readable; standard calls remain boundary leaves,
    // and a standard method is named by receiver and method, not its source offset.
    let std_methods: std::collections::HashMap<String, String> = inspection
        .entities
        .iter()
        .filter(|e| e.span.file.starts_with("@std/") && e.kind == "method")
        .map(|e| (e.id.clone(), e.name.clone()))
        .collect();
    for call in &mut inspection.calls {
        if let Some(name) = std_methods.get(&call.target) {
            call.target.clone_from(name);
        }
    }
    inspection
        .entities
        .retain(|e| !e.span.file.starts_with("@std/"));
    inspection.calls.retain(|c| !c.owner.starts_with("@std/"));
    let text = if request.format == "mermaid" {
        inspection.mermaid()
    } else {
        diagram_ascii(&inspection.rows())
    };
    Ok(write_output(io, &request.output, text.as_bytes()))
}

/// One scoped diagram view, optionally marked with what a diff changes.
fn view(syms: ms_syntax::Names, request: &DiagramRequest, head: &Checked, io: &mut Io) -> i32 {
    let name = if request.view.is_empty() {
        "calls"
    } else {
        &request.view
    };
    let facts = facts_of(syms, head);
    if request.format == "html" {
        let changes = if request.diff.is_empty() {
            None
        } else {
            let (input, base) =
                match diff_inputs(syms, &request.filename, &request.diff, head, false, io) {
                    Ok(inputs) => inputs,
                    Err(status) => return status,
                };
            Some(compare_facts(&base, &facts, &input))
        };
        let analysis = ms_lsp::analysis::compile_file(
            syms,
            &request.filename,
            &ms_lsp::analysis::Options::default(),
        );
        let hints = ms_lsp::nav::type_hints(syms, &analysis);
        let page = ms_tooling::html::html_page(&facts, changes.as_deref(), &hints);
        return write_output(io, &request.output, page.as_bytes());
    }
    let mut tree = match build_view(&facts, name, &request.entity, request.depth as i64) {
        Ok(tree) => tree,
        Err(message) => {
            let _ = writeln!(io.stderr, "ms diagram: {message}");
            return 2;
        }
    };
    if !request.diff.is_empty() {
        let (input, base) =
            match diff_inputs(syms, &request.filename, &request.diff, head, false, io) {
                Ok(inputs) => inputs,
                Err(status) => return status,
            };
        mark_changes(
            &mut tree,
            &compare_facts(&base, &facts, &input),
            &input.touched,
        );
    }
    let text = if request.json {
        ms_json::obj([
            ("format", ms_json::Json::int(1)),
            ("view", ms_json::Json::str(name)),
            ("entity", ms_json::Json::str(&request.entity)),
            ("tree", tree.to_json()),
        ])
        .pretty_line(ms_json::Escape::HtmlSafe)
            + "\n"
    } else if request.format == "mermaid" {
        // A diff marks the generic tree, so it keeps the generic rendering.
        let custom = request
            .diff
            .is_empty()
            .then(|| mermaid_view(&facts, name, &request.entity, request.depth as i64));
        custom.flatten().unwrap_or_else(|| tree.mermaid())
    } else {
        let custom = request
            .diff
            .is_empty()
            .then(|| ascii_view(&facts, name, &request.entity, request.depth as i64));
        custom.flatten().unwrap_or_else(|| tree.ascii())
    };
    write_output(io, &request.output, text.as_bytes())
}

pub fn review(syms: ms_syntax::Names, request: &ReviewRequest, io: &mut Io) -> BackendResult {
    let head = match source_program(
        syms,
        &request.filename,
        &request.output,
        request.format == "json",
        true,
        io,
    ) {
        Ok(head) => head,
        Err(done) => return done,
    };
    let head_facts = facts_of(syms, &head);
    let options = ReviewOptions {
        all: request.all || request.format == "json",
        effect: &request.effect,
    };
    if request.diff.is_empty() {
        let report = project_report(&head_facts, options);
        return Ok(write_output(
            io,
            &request.output,
            report.render(&request.format).as_bytes(),
        ));
    }
    let (input, base) = match diff_inputs(syms, &request.filename, &request.diff, &head, true, io) {
        Ok(inputs) => inputs,
        Err(status) => return Ok(status),
    };
    if !request.explain.is_empty() {
        let findings = compare_facts(&base, &head_facts, &input);
        let explanation = if request.format == "json" {
            explain_json(&findings, &head_facts, &request.explain)
                .map(|j| j.pretty_line(ms_json::Escape::HtmlSafe) + "\n")
        } else {
            explain(&findings, &head_facts, &request.explain)
        };
        return Ok(match explanation {
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
    syms: ms_syntax::Names,
    filename: &str,
    diff: &str,
    head: &Checked,
    project: bool,
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
        match pathops::abs(filename) {
            Ok(absolute) => pathops::dir(&absolute),
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
    if let Ok(checked) = accepted(syms, filename, &overlay, project) {
        input.base_checked = true;
        base = facts_of(syms, &checked);
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
        if pathops::ext(file.path()) != ".ms" {
            continue;
        }
        let absolute = locate_diff_path(root, file.path(), file.new.is_empty());
        let Ok(relative) = pathops::rel(root, &absolute) else {
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
        let candidate = pathops::join(&[&dir, path]);
        let target = if deleted {
            pathops::dir(&candidate)
        } else {
            candidate.clone()
        };
        if std::fs::metadata(&target).is_ok() {
            return candidate;
        }
        let parent = pathops::dir(&dir);
        if parent == dir {
            return pathops::join(&[root, path]);
        }
        dir = parent;
    }
}

pub fn drop_redundant_labels(
    syms: ms_syntax::Names,
    file: &FormatFile,
    source: &str,
) -> Result<String, FormatFailure> {
    let checked = analyze(syms, &file.path, &Overlay::new());
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
pub fn format_source(file: &FormatFile, source: &str) -> Result<String, FormatFailure> {
    let name: std::sync::Arc<str> = file.display.as_str().into();
    ms_syntax::format::format(&name, source)
        .map_err(|issue| FormatFailure::Syntax(Box::new(command_diagnostic(&issue))))
}

#[cfg(test)]
mod watch_state_tests {
    use super::{file_state, observed, state_after};
    use std::time::{Duration, SystemTime};

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("ms-watch-state-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_permission_change_alone_changes_the_state() {
        let dir = scratch("permissions");
        let path = dir.join("main.ms");
        std::fs::write(&path, "export fn main() Int: 0\n").unwrap();
        let name = path.to_str().unwrap();
        let before = file_state(name);
        let mut permissions = std::fs::metadata(&path).unwrap().permissions();
        permissions.set_readonly(true);
        std::fs::set_permissions(&path, permissions).unwrap();
        assert!(file_state(name) != before);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_file_modified_during_analysis_never_matches_its_state() {
        let dir = scratch("during");
        let path = dir.join("early.ms");
        let name = path.to_str().unwrap();
        let started = SystemTime::now();
        std::thread::sleep(Duration::from_millis(50));
        std::fs::write(&path, "export fn value() Int: 3\n").unwrap();
        assert!(state_after(name, started) != file_state(name));
        let settled = SystemTime::now() + Duration::from_secs(60);
        assert!(state_after(name, settled) == file_state(name));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_watched_file_keeps_the_state_from_before_the_analysis() {
        let dir = scratch("before");
        let path = dir.join("early.ms");
        let name = path.to_str().unwrap().to_string();
        std::fs::write(&path, "export fn value() Int: 3\n").unwrap();
        let before = std::collections::BTreeMap::from([(name.clone(), file_state(&name))]);
        let started = SystemTime::now();
        std::fs::write(&path, "export fn value() Int: \"bad\"\n").unwrap();
        let after = observed(before, std::iter::once(name.clone()), started);
        assert!(after[&name] != file_state(&name));
        let _ = std::fs::remove_dir_all(&dir);
    }
}

//! Advisory source hygiene findings. Checking owns
//! semantic errors; lint never changes behavior.

mod bindings;
mod faults;
mod matches;
mod patterns;
mod recursion;
mod tasks;

use ms_check::{ModuleData, Program};
use ms_syntax::Pos;
use std::sync::Arc;

/// One advisory finding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    /// Stable rule code, `MSL001`..`MSL112`.
    pub code: &'static str,
    /// Human-readable message.
    pub message: String,
    /// File the position refers to.
    pub file: Arc<str>,
    /// Where the finding applies.
    pub pos: Pos,
}

fn finding(code: &'static str, message: impl Into<String>, file: &Arc<str>, pos: Pos) -> Finding {
    Finding {
        code,
        message: message.into(),
        file: file.clone(),
        pos,
    }
}

/// Lexical findings: trailing whitespace (`MSL001`) and a missing final
/// newline (`MSL002`).
pub fn lint_source(file: &Arc<str>, source: &str) -> Vec<Finding> {
    let mut findings = Vec::new();
    let mut offset = 0usize;
    for (line, text) in source.split_inclusive('\n').enumerate() {
        let body = text.strip_suffix('\n').unwrap_or(text);
        let body = body.strip_suffix('\r').unwrap_or(body);
        let trimmed = body.trim_end_matches([' ', '\t']);
        if trimmed.len() != body.len() {
            findings.push(finding(
                "MSL001",
                "Remove trailing whitespace",
                file,
                Pos::new(
                    (offset + trimmed.len()) as u32,
                    line as u32 + 1,
                    trimmed.len() as u32 + 1,
                ),
            ));
        }
        offset += text.len();
    }
    if !source.is_empty() && !source.ends_with('\n') {
        let newlines = source.matches('\n').count();
        let column = match source.rfind('\n') {
            Some(last) => source.len() - last,
            None => source.len() + 1,
        };
        findings.push(finding(
            "MSL002",
            "End the file with a newline",
            file,
            Pos::new(source.len() as u32, newlines as u32 + 1, column as u32),
        ));
    }
    findings
}

/// Semantic advisories from a checked program (`LintProgram`). A program with
/// diagnostics yields nothing. Bundled standard modules are skipped.
pub fn lint_program(program: &Program) -> Vec<Finding> {
    if !program.diagnostics.is_empty() {
        return Vec::new();
    }
    let mut findings = Vec::new();
    for module in program.modules.iter().filter(|m| !m.is_standard()) {
        bindings::lint(program, module, &mut findings);
        faults::lint(module, &mut findings);
        recursion::lint(program, module, &mut findings);
        patterns::lint(module, &mut findings);
        matches::lint(module, &mut findings);
        tasks::lint(module, &mut findings);
    }
    findings.sort_by(|a, b| {
        (a.file.as_ref(), a.pos.offset, a.code).cmp(&(b.file.as_ref(), b.pos.offset, b.code))
    });
    findings
}

/// Everything `ms lint` reports for a checked program: lexical findings per
/// module, then semantic ones, outside `@std/`, ordered by file, line, column.
pub fn lint_modules(program: &Program) -> Vec<Finding> {
    let mut findings = Vec::new();
    for module in program.modules.iter().filter(|m| !m.is_standard()) {
        let file: Arc<str> = Arc::from(module.file.as_str());
        findings.extend(lint_source(&file, &module.source));
    }
    findings.extend(
        lint_program(program)
            .into_iter()
            .filter(|f| !f.file.starts_with("@std/")),
    );
    findings.sort_by(|a, b| {
        (a.file.as_ref(), a.pos.line, a.pos.column).cmp(&(
            b.file.as_ref(),
            b.pos.line,
            b.pos.column,
        ))
    });
    findings
}

/// The file a module was checked from.
pub(crate) fn module_file(module: &ModuleData) -> Arc<str> {
    Arc::from(module.file.as_str())
}

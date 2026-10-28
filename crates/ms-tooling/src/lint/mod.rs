//! Advisory source hygiene findings. Checking owns
//! semantic errors; lint never changes behavior.

mod bindings;
mod faults;
mod flush;
mod matches;
mod patterns;
mod recursion;
mod redundant;
mod tasks;

use ms_check::{ModuleData, Program};
use ms_syntax::{DiagnosticFix, Pos};
use std::sync::Arc;

/// One advisory finding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    /// Stable rule code, `MSL001`..`MSL114`.
    pub code: &'static str,
    /// Human-readable message.
    pub message: String,
    /// File the position refers to.
    pub file: Arc<str>,
    /// Where the finding applies.
    pub pos: Pos,
    /// A machine-applicable edit that resolves the finding, applied by `ms lint --fix`.
    pub fix: Option<DiagnosticFix>,
}

fn finding(code: &'static str, message: impl Into<String>, file: &Arc<str>, pos: Pos) -> Finding {
    Finding {
        code,
        message: message.into(),
        file: file.clone(),
        pos,
        fix: None,
    }
}

/// A lint rule's code with the same family and repair text `ms guide` prints for check codes.
pub struct Rule {
    pub code: &'static str,
    pub family: &'static str,
    pub repair: &'static str,
}

/// Every rule `lint_source` and `lint_program` can report, in code order.
pub const RULES: &[Rule] = &[
    Rule {
        code: "MSL001",
        family: "Trailing whitespace",
        repair: "delete the spaces or tabs at the end of the line; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL002",
        family: "Missing final newline",
        repair: "end the file with a newline; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL102",
        family: "Unused import",
        repair: "remove the import or use the name; `ms lint --fix` removes it",
    },
    Rule {
        code: "MSL103",
        family: "Unreachable statement",
        repair: "delete the statement or the `return`, `break` or `continue` before it",
    },
    Rule {
        code: "MSL106",
        family: "Match arm binding shadows a type or case",
        repair: "rename the binding to a lowercase name, or write the case with its payload in a helper",
    },
    Rule {
        code: "MSL107",
        family: "Nested match",
        repair: "bind the outer payload with an early exit, use compatible `try`, or call a small helper",
    },
    Rule {
        code: "MSL108",
        family: "Optional matched with only some and none",
        repair: "use `if let value = ...:` with `else:`, or an Optional method such as `get(default)` or `map`",
    },
    Rule {
        code: "MSL109",
        family: "Result matched with only ok and error",
        repair: "use `try`, `if let value = ...:` with `else:`, or a Result method such as `get(default)`, `is_error` or `err`",
    },
    Rule {
        code: "MSL110",
        family: "Optional.get() without a default",
        repair: "use `if let value = ...:`, or pass a default to `get(default)`",
    },
    Rule {
        code: "MSL111",
        family: "Loop that never waits or exits",
        repair: "wait inside the loop (sleep or a channel call), or return once `cancelled()` is True",
    },
    Rule {
        code: "MSL112",
        family: "Unconditional recursion",
        repair: "add a base case that returns before the recursive call",
    },
    Rule {
        code: "MSL113",
        family: "Redundant some(...)",
        repair: "pass the plain value where an Optional is expected; `ms lint --fix` removes the wrapper",
    },
    Rule {
        code: "MSL114",
        family: "Resource closed at scope end with an uncalled flush",
        repair: "call `try name.flush()` (or `sync`, `commit`) before the scope ends, or close the resource explicitly",
    },
];

/// The rule for `code`, matched case-insensitively.
pub fn explain(code: &str) -> Option<&'static Rule> {
    RULES.iter().find(|r| r.code.eq_ignore_ascii_case(code))
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
        flush::lint(program, module, &mut findings);
        recursion::lint(program, module, &mut findings);
        patterns::lint(module, &mut findings);
        matches::lint(module, &mut findings);
        tasks::lint(module, &mut findings);
        redundant::lint(module, &mut findings);
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

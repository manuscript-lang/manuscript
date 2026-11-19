//! Advisory source hygiene findings. Checking owns
//! semantic errors; lint never changes behavior.

mod bindings;
mod effects;
mod faults;
mod flush;
mod matches;
mod patterns;
mod promises;
mod recursion;
mod tasks;
mod terse;
mod text;

use ms_check::{ModuleData, Program};
use ms_syntax::{DiagnosticFix, Pos};
use std::cell::OnceCell;
use std::sync::Arc;

/// How seriously a finding is taken. Warnings are reported without failing
/// `ms lint`; errors fail it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Warning,
    Error,
}

impl Severity {
    pub fn name(self) -> &'static str {
        match self {
            Severity::Warning => "warning",
            Severity::Error => "error",
        }
    }
}

/// One advisory finding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    /// Stable rule code, `MSL001`..`MSL136`.
    pub code: &'static str,
    /// The rule's severity.
    pub severity: Severity,
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
        severity: explain(code).map_or(Severity::Error, |rule| rule.severity),
        message: message.into(),
        file: file.clone(),
        pos,
        fix: None,
    }
}

/// A lint rule's code with the same family and repair text `ms explain` prints for check codes.
pub struct Rule {
    pub code: &'static str,
    pub family: &'static str,
    pub severity: Severity,
    pub repair: &'static str,
}

/// Every rule `lint_source` and `lint_program` can report, in code order.
pub const RULES: &[Rule] = &[
    Rule {
        code: "MSL001",
        family: "Trailing whitespace",
        severity: Severity::Warning,
        repair: "delete the spaces or tabs at the end of the line; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL002",
        family: "Missing final newline",
        severity: Severity::Warning,
        repair: "end the file with a newline; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL102",
        family: "Unused import",
        severity: Severity::Warning,
        repair: "remove the import or use the name; `ms lint --fix` removes it",
    },
    Rule {
        code: "MSL103",
        family: "Unreachable statement",
        severity: Severity::Warning,
        repair: "delete the statement or the `return`, `break` or `continue` before it",
    },
    Rule {
        code: "MSL106",
        family: "Match arm binding shadows a type or case",
        severity: Severity::Error,
        repair: "rename the binding to a lowercase name, or write the case with its payload in a helper",
    },
    Rule {
        code: "MSL107",
        family: "Nested match",
        severity: Severity::Error,
        repair: "bind the outer payload with an early exit, use a compatible trailing `?`, or call a small helper",
    },
    Rule {
        code: "MSL108",
        family: "Optional matched with only some and none",
        severity: Severity::Warning,
        repair: "use `if value := ...:` with `else:`, or an Optional method such as `get(default)` or `map`",
    },
    Rule {
        code: "MSL109",
        family: "Result matched with only ok and error",
        severity: Severity::Warning,
        repair: "use a trailing `?`, `if value := ...:` with `else:`, or a Result method such as `get(default)`, `is_error` or `err`",
    },
    Rule {
        code: "MSL110",
        family: "Optional.get() without a default",
        severity: Severity::Warning,
        repair: "use `if value := ...:`, or write `get_or(default)`",
    },
    Rule {
        code: "MSL111",
        family: "Loop that never waits or exits",
        severity: Severity::Error,
        repair: "wait inside the loop (sleep, or wait on a promise or a pipe), or return",
    },
    Rule {
        code: "MSL112",
        family: "Unconditional recursion",
        severity: Severity::Error,
        repair: "add a base case that returns before the recursive call",
    },
    Rule {
        code: "MSL114",
        family: "Resource closed at scope end with an uncalled flush",
        severity: Severity::Error,
        repair: "call `name.flush()?` (or `sync`, `commit`) before the scope ends, or close the resource explicitly",
    },
    Rule {
        code: "MSL115",
        family: "Promise dropped as soon as it is made",
        severity: Severity::Warning,
        repair: "bind the promise and call `wait()` on it, or pass it to `wait_all`; dropping a promise cancels it",
    },
    Rule {
        code: "MSL116",
        family: "Undeclared effect",
        severity: Severity::Warning,
        repair: "permit it with `// ms: allow_effect <effect>` above the function or in the file header, or move the call to the caller, or take a capability parameter",
    },
    Rule {
        code: "MSL117",
        family: "Integer literal interpolated into text",
        severity: Severity::Warning,
        repair: "drop the `f` so braces are plain text, or write `\\{4\\}` for literal braces in `f\"...\"` text; delete the braces to write the number",
    },
    Rule {
        code: "MSL118",
        family: "Length compared with zero",
        severity: Severity::Error,
        repair: "write `xs.is_empty()` or `not xs.is_empty()`; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL119",
        family: "List read with get(i)",
        severity: Severity::Error,
        repair: "write `xs[i]`; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL120",
        family: "Optional chained after a map get",
        severity: Severity::Error,
        repair: "write `map.get_or(key, default)`; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL121",
        family: "Default overridden by a one-line if",
        severity: Severity::Error,
        repair: "write `x := if c: b else: a`; `ms lint --fix` does it for a literal or name default",
    },
    Rule {
        code: "MSL122",
        family: "Counter loop written as a while",
        severity: Severity::Error,
        repair: "write `for i in start..end:` and drop `i += 1`; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL123",
        family: "Index loop that only reads xs[i]",
        severity: Severity::Warning,
        repair: "write `for item in xs:` and use `item`",
    },
    Rule {
        code: "MSL124",
        family: "Loop that appends or adds into a fresh accumulator",
        severity: Severity::Warning,
        repair: "write `xs.map(fn x: ...)`, `xs.filter(fn x: ...)` or `xs.sum()`",
    },
    Rule {
        code: "MSL125",
        family: "Loop that appends every element",
        severity: Severity::Warning,
        repair: "write `out.extend(xs)`",
    },
    Rule {
        code: "MSL126",
        family: "Binding returned on the next line",
        severity: Severity::Error,
        repair: "write `return <expression>`",
    },
    Rule {
        code: "MSL127",
        family: "Map entry rebuilt from its own lookup",
        severity: Severity::Error,
        repair: "write `m[k] -= v` (or `+=`, `*=`, `/=`, `%=`)",
    },
    Rule {
        code: "MSL128",
        family: "Final return the end of the function already makes",
        severity: Severity::Error,
        repair: "delete the final `return ok()` (`Void!`) or `return` (`Void`)",
    },
    Rule {
        code: "MSL129",
        family: "Void! outcome ignored with get(none)",
        severity: Severity::Error,
        repair: "write `void call()`; `ms lint --fix` does it",
    },
    Rule {
        code: "MSL130",
        family: "Statement get() on a Result",
        severity: Severity::Warning,
        repair: "write `call()?` in a function that returns a Result (`main` can return `Void!`), or `void call()` to ignore the outcome",
    },
    Rule {
        code: "MSL131",
        family: "Result printed as a value",
        severity: Severity::Warning,
        repair: "write `call()?` in a function that returns a Result, or `if value := call():` to read the success",
    },
    Rule {
        code: "MSL132",
        family: "slice result replaced by a fallback",
        severity: Severity::Warning,
        repair: "write `xs.slice(a, b)?`, or clamp the end with `min(end, xs.length())` before slicing",
    },
    Rule {
        code: "MSL133",
        family: "`//` after an operand reads like floor division",
        severity: Severity::Warning,
        repair: "`//` starts a comment, so the number after it is ignored; Int `/` already truncates, so write `a / 2`",
    },
    Rule {
        code: "MSL134",
        family: "Void value bound or printed",
        severity: Severity::Warning,
        repair: "call `xs.sort()` or `xs.reverse()` as a statement, or use `sorted()` or `reversed()` for a new list",
    },
    Rule {
        code: "MSL135",
        family: "`to_string()` on Bytes",
        severity: Severity::Warning,
        repair: "`bytes.to_string()` renders `Bytes(104, 105)`; write `bytes.decode_utf8().ok_or(Error(\"not UTF-8\", kind: \"EBADMSG\"))?` for the text",
    },
    Rule {
        code: "MSL136",
        family: "var written at a call site",
        severity: Severity::Warning,
        repair: "write `f(x)`: the parameter's `var` says the callee changes it; `ms lint --fix` does it",
    },
];

/// The rule for `code`, matched case-insensitively.
pub fn explain(code: &str) -> Option<&'static Rule> {
    RULES.iter().find(|r| r.code.eq_ignore_ascii_case(code))
}

/// Whether the `//` at byte `slash` of `line` ends an expression and holds only a number:
/// `mid := (lo + hi) // 2`, a Python floor division that compiles as `(lo + hi)`.
fn floor_division_shape(line: &str, slash: usize) -> bool {
    let before = line[..slash].trim_end();
    let operand_end = before
        .chars()
        .next_back()
        .is_some_and(|c| c.is_ascii_alphanumeric() || matches!(c, ')' | ']' | '_'));
    let comment = line[slash + 2..].trim().trim_end_matches([')', ']']);
    // `total := 1 + 2 * 3 // 7` annotates a result: the expression is all literals.
    let expression = before.rsplit(['=', ':']).next().unwrap_or(before);
    let names_a_value = expression
        .chars()
        .any(|c| c.is_ascii_alphabetic() || c == '_');
    operand_end
        && names_a_value
        && comment.starts_with(|c: char| c.is_ascii_digit())
        && comment.bytes().all(|b| b.is_ascii_digit() || b == b'.')
}

/// Whether byte `at` of `source` is outside any text literal, by the lexer; an unlexable file reports false.
fn outside_text(
    tokens: &OnceCell<Option<Vec<ms_syntax::token::Token>>>,
    file: &Arc<str>,
    source: &str,
    at: usize,
) -> bool {
    tokens
        .get_or_init(|| ms_syntax::lexer::lex(file, source).ok().map(|l| l.tokens))
        .as_ref()
        .is_some_and(|tokens| {
            let next = tokens.partition_point(|t| t.end.offset as usize <= at);
            !tokens.get(next).is_some_and(|t| {
                t.kind == ms_syntax::token::Tok::String && t.pos.offset as usize <= at
            })
        })
}

/// Lexical findings: trailing whitespace (`MSL001`), a missing final
/// newline (`MSL002`) and a `//` that reads like floor division (`MSL133`).
pub fn lint_source(file: &Arc<str>, source: &str) -> Vec<Finding> {
    let mut findings = Vec::new();
    // Lex only if a candidate exists. Unknown text boundaries must never yield
    // a destructive whitespace quickfix in an incomplete editor snapshot.
    let tokens = OnceCell::new();
    let mut offset = 0usize;
    for (line, text) in source.split_inclusive('\n').enumerate() {
        let body = text.strip_suffix('\n').unwrap_or(text);
        let body = body.strip_suffix('\r').unwrap_or(body);
        let trimmed = body.trim_end_matches([' ', '\t']);
        let at = offset + trimmed.len();
        let safe_whitespace = || outside_text(&tokens, file, source, at);
        if trimmed.len() != body.len() && safe_whitespace() {
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
        if let Some(slash) = body.find("//")
            && floor_division_shape(body, slash)
            && outside_text(&tokens, file, source, offset + slash)
        {
            findings.push(finding(
                "MSL133",
                "`//` starts a comment, so everything after it is ignored; Int `/` already truncates, so write `a / 2` for a floor division",
                file,
                Pos::new(
                    (offset + slash) as u32,
                    line as u32 + 1,
                    slash as u32 + 1,
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
pub fn lint_program(syms: ms_syntax::Names, program: &Program) -> Vec<Finding> {
    if !program.diagnostics.is_empty() {
        return Vec::new();
    }
    let mut findings = Vec::new();
    for module in program.modules.iter().filter(|m| !m.is_standard(syms)) {
        bindings::lint(syms, program, module, &mut findings);
        faults::lint(syms, module, &mut findings);
        flush::lint(syms, program, module, &mut findings);
        recursion::lint(syms, program, module, &mut findings);
        patterns::lint(syms, module, &mut findings);
        matches::lint(syms, module, &mut findings);
        tasks::lint(syms, module, &mut findings);
        promises::lint(syms, module, &mut findings);
        text::lint(syms, module, &mut findings);
        terse::lint(syms, module, &mut findings);
    }
    effects::lint(syms, program, &mut findings);
    findings.sort_by(|a, b| {
        (a.file.as_ref(), a.pos.offset, a.code).cmp(&(b.file.as_ref(), b.pos.offset, b.code))
    });
    findings
}

/// Everything `ms lint` reports for a checked program: lexical findings per
/// module, then semantic ones, outside `@std/`, ordered by file, line, column.
pub fn lint_modules(syms: ms_syntax::Names, program: &Program) -> Vec<Finding> {
    let mut findings = Vec::new();
    for module in program.modules.iter().filter(|m| !m.is_standard(syms)) {
        let file: Arc<str> = Arc::from(syms.str(module.file));
        findings.extend(lint_source(&file, &module.source));
    }
    findings.extend(
        lint_program(syms, program)
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
pub(crate) fn module_file(syms: ms_syntax::Names, module: &ModuleData) -> Arc<str> {
    Arc::from(syms.str(module.file))
}

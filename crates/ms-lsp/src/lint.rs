//! Advisory lint findings shown next to diagnostics.
//!
//! The server takes findings through [`Lint`]; [`Tooling`] is the default and
//! [`Hygiene`] the whitespace-only subset.

use ms_check::Program;

/// One advisory finding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LintFinding {
    /// Rule code such as `MSL001`.
    pub code: String,
    /// Message.
    pub message: String,
    /// Logical module file.
    pub file: String,
    /// Byte offset in that file.
    pub offset: usize,
}

/// A source of lint findings.
pub trait Lint {
    /// Findings that need only the text of a file.
    fn source(&self, filename: &str, source: &str) -> Vec<LintFinding>;
    /// Findings that need the checked program.
    fn program(&self, program: &Program) -> Vec<LintFinding>;
}

/// The whitespace hygiene rules (`MSL001`, `MSL002`) and no semantic lint.
pub struct Hygiene;

impl Lint for Hygiene {
    fn source(&self, filename: &str, source: &str) -> Vec<LintFinding> {
        let mut findings = Vec::new();
        let mut offset = 0;
        for text in source.split_inclusive('\n') {
            let body = text.strip_suffix('\n').unwrap_or(text);
            let body = body.strip_suffix('\r').unwrap_or(body);
            let trimmed = body.trim_end_matches([' ', '\t']);
            if trimmed.len() != body.len() {
                findings.push(LintFinding {
                    code: "MSL001".to_string(),
                    message: "Remove trailing whitespace".to_string(),
                    file: filename.to_string(),
                    offset: offset + trimmed.len(),
                });
            }
            offset += text.len();
        }
        if !source.is_empty() && !source.ends_with('\n') {
            findings.push(LintFinding {
                code: "MSL002".to_string(),
                message: "End the file with a newline".to_string(),
                file: filename.to_string(),
                offset: source.len(),
            });
        }
        findings
    }

    fn program(&self, _program: &Program) -> Vec<LintFinding> {
        Vec::new()
    }
}

/// Every rule `ms lint` reports: whitespace hygiene plus the semantic
/// advisories of the tooling crate.
pub struct Tooling;

impl Lint for Tooling {
    fn source(&self, filename: &str, source: &str) -> Vec<LintFinding> {
        Hygiene.source(filename, source)
    }

    fn program(&self, program: &Program) -> Vec<LintFinding> {
        ms_tooling::lint::lint_program(program)
            .into_iter()
            .map(|finding| LintFinding {
                code: finding.code.to_string(),
                message: finding.message,
                file: finding.file.to_string(),
                offset: finding.pos.offset as usize,
            })
            .collect()
    }
}

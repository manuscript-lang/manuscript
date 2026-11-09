//! Advisory lint findings shown next to diagnostics.
//!
//! The server takes findings through [`Lint`]; [`Tooling`] is the default and
//! [`Hygiene`] the whitespace-only subset.

use ms_check::Program;
use ms_tooling::lint::Severity;

/// One advisory finding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LintFinding {
    /// Rule code such as `MSL001`.
    pub code: String,
    /// LSP severity: 1 for an error rule, 2 for a warning rule.
    pub severity: i64,
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
        ms_tooling::lint::lint_source(&filename.into(), source)
            .into_iter()
            .map(|finding| LintFinding {
                code: finding.code.to_string(),
                severity: 2,
                message: finding.message,
                file: filename.to_string(),
                offset: finding.pos.offset as usize,
            })
            .collect()
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
        let syms = ms_syntax::Names::global();
        ms_tooling::lint::lint_program(syms, program)
            .into_iter()
            .map(|finding| LintFinding {
                code: finding.code.to_string(),
                severity: match finding.severity {
                    Severity::Warning => 2,
                    Severity::Error => 1,
                },
                message: finding.message,
                file: finding.file.to_string(),
                offset: finding.pos.offset as usize,
            })
            .collect()
    }
}

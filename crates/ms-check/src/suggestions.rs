//! Machine-applicable fixes for diagnostics whose message names one concrete edit.
//!
//! A misspelled name carries `; did you mean 'x'?` and an unresolved standard
//! name carries `; add: from "module" import x`. When exactly one edit is named,
//! the diagnostic also carries it as a `DiagnosticFix`.

use crate::checker::Checker;
use ms_syntax::{DiagnosticFix, Phase, Pos};

/// The single replacement a `did you mean` hint names, if exactly one.
fn single_suggestion(message: &str) -> Option<&str> {
    let rest = message.split_once("; did you mean '")?.1;
    let (name, tail) = rest.split_once('\'')?;
    (tail == "?" && !name.is_empty()).then_some(name)
}

/// The import statement an `add: from` hint names.
fn import_statement(message: &str) -> Option<&str> {
    let rest = message.split_once("; add: ")?.1;
    let end = rest.find('\n').unwrap_or(rest.len());
    let statement = rest[..end].trim_end();
    statement.starts_with("from ").then_some(statement)
}

/// The fix for a diagnostic at `pos` whose offending name has `len` bytes.
pub(crate) fn fix_for(message: &str, pos: Pos, len: usize) -> Option<DiagnosticFix> {
    if let Some(name) = single_suggestion(message) {
        let end = Pos::new(pos.offset + len as u32, pos.line, pos.column + len as u32);
        return Some(DiagnosticFix {
            pos,
            end,
            replacement: name.to_string(),
        });
    }
    let statement = import_statement(message)?;
    let start = Pos::new(0, 1, 1);
    Some(DiagnosticFix {
        pos: start,
        end: start,
        replacement: format!("{statement}\n"),
    })
}

impl Checker {
    /// A resolution diagnostic about the `len`-byte name at `pos`, with its fix.
    pub(crate) fn res_error_name(&mut self, pos: Pos, len: usize, message: String) {
        self.error_fixed(pos, len, Phase::Resolution, message);
    }

    /// A type diagnostic about the `len`-byte name at `pos`, with its fix.
    pub(crate) fn type_error_name(&mut self, pos: Pos, len: usize, message: String) {
        self.error_fixed(pos, len, Phase::Type, message);
    }

    fn error_fixed(&mut self, pos: Pos, len: usize, phase: Phase, message: String) {
        let fix = fix_for(&message, pos, len);
        let count = self.p.diagnostics.len();
        self.error(pos, phase, message);
        if self.p.diagnostics.len() > count
            && let Some(last) = self.p.diagnostics.last_mut()
        {
            last.fix = fix;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_single_suggestion_is_a_fix() {
        let pos = Pos::new(10, 2, 5);
        let fix = fix_for("unknown binding cuont; did you mean 'count'?", pos, 5).unwrap();
        assert_eq!((fix.pos.offset, fix.end.offset), (10, 15));
        assert_eq!(fix.replacement, "count");
        assert!(fix_for("no member x; did you mean 'a' or 'b'?", pos, 1).is_none());
        assert!(fix_for("unknown binding q; declare it", pos, 1).is_none());
    }

    #[test]
    fn import_hint_inserts_at_file_start() {
        let message = "unknown binding stdout; add: from \"@std/io\" import stdout";
        let fix = fix_for(message, Pos::new(40, 3, 1), 6).unwrap();
        assert_eq!(fix.pos.offset, 0);
        assert_eq!(fix.replacement, "from \"@std/io\" import stdout\n");
    }
}

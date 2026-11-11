//! Machine-applicable fixes for diagnostics whose message names one concrete edit.
//!
//! A misspelled name carries `; did you mean 'x'?` and an unresolved standard
//! name carries `; add: import x from "module"`. When exactly one edit is named,
//! the diagnostic also carries it as a `DiagnosticFix`.

use crate::checker::Checker;
use crate::types::{Ty, same};
use ms_syntax::Cause;
use ms_syntax::ast::{Expr, ExprKind};
use ms_syntax::{DiagnosticFix, Phase, Pos};

/// The module that declares `Promise`.
pub(crate) const PROMISE_MODULE: &str = "@std/concurrency/promise.ms";

/// Whether a `Promise[T]` used where `expected` is required gets its value from `wait()`:
/// `expected` is `T!`, which is what `wait` returns.
pub(crate) fn promise_wait_fits(syms: ms_syntax::Names, actual: &Ty, expected: &Ty) -> bool {
    actual.is_source_type(syms, PROMISE_MODULE, "Promise")
        && actual.args.len() == 1
        && expected.is_std(syms, "Result")
        && expected.args.len() == 2
        && same(&actual.args[0], &expected.args[0])
}

/// The single replacement a `did you mean` hint names, if exactly one.
fn single_suggestion(message: &str) -> Option<&str> {
    let rest = message.split_once("; did you mean '")?.1;
    let (name, tail) = rest.split_once('\'')?;
    (tail == "?" && !name.is_empty()).then_some(name)
}

/// The import statement an `add: import` hint names.
fn import_statement(message: &str) -> Option<&str> {
    let rest = message.split_once("; add: ")?.1;
    let end = rest.find('\n').unwrap_or(rest.len());
    let statement = rest[..end].trim_end();
    statement.starts_with("import ").then_some(statement)
}

/// The single spelling an `unknown binding` hint names for a habit from
/// another language (`Ok`, `Err`, `True`, `null`, `this`).
fn habit_replacement(message: &str) -> Option<&'static str> {
    let rest = message.strip_prefix("unknown binding ")?;
    let (name, hint) = rest.split_once("; ")?;
    match name {
        "Ok" => Some("ok"),
        "Err" | "err" | "Error" => Some("error"),
        "True" => Some("true"),
        "False" => Some("false"),
        "nil" | "null" | "None" | "undefined" => Some("none"),
        "this" if hint.ends_with("write self instead of this") => Some("self"),
        _ => None,
    }
}

/// The fix for a diagnostic at `pos` whose offending name has `len` bytes.
pub(crate) fn fix_for(message: &str, pos: Pos, len: usize) -> Option<DiagnosticFix> {
    if let Some(name) = habit_replacement(message) {
        let end = Pos::new(pos.offset + len as u32, pos.line, pos.column + len as u32);
        return Some(DiagnosticFix {
            pos,
            end,
            replacement: name.to_string(),
        });
    }
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

/// Turns the immutable binding `name := v` or `name: T := v` declared at `decl` into the
/// `var` form. `None` unless the source reads a plain name there, so patterns and
/// loop variables get no edit.
pub(crate) fn binding_to_var(source: &str, decl: Pos) -> Option<DiagnosticFix> {
    let at = decl.offset as usize;
    let rest = source.get(at..)?;
    let name_len = rest
        .bytes()
        .take_while(|b| b.is_ascii_alphanumeric() || *b == b'_')
        .count();
    (name_len > 0).then_some(())?;
    let name = &rest[..name_len];
    let after = &rest[name_len..];
    let spaces = after.len() - after.trim_start_matches(' ').len();
    let (len, replacement) = if after[spaces..].starts_with(":=") {
        (name_len + spaces + 2, format!("var {name} ="))
    } else if after[spaces..].starts_with(':') {
        // `x: T := v` becomes `var x: T = v`: rewrite through the `:=`. A
        // parameter `x: T` has no `:=` on its line and only gains `var`.
        let line = after.split('\n').next()?;
        match line.find(":=").filter(|w| !line[..*w].contains([',', ')'])) {
            Some(walrus) => (
                name_len + walrus + 2,
                format!("var {name}{} =", after[..walrus].trim_end()),
            ),
            None => (name_len, format!("var {name}")),
        }
    } else {
        return None;
    };
    Some(DiagnosticFix {
        pos: decl,
        end: Pos::new((at + len) as u32, decl.line, decl.column + len as u32),
        replacement,
    })
}

/// Removal of the `()` after the nullary case `name` called at `pos`.
pub(crate) fn drop_case_parens(source: &str, pos: Pos, name: &str) -> Option<DiagnosticFix> {
    let at = pos.offset as usize;
    let rest = source.get(at..)?.strip_prefix(name)?;
    rest.starts_with("()").then_some(())?;
    let start_offset = (at + name.len()) as u32;
    let start = Pos::new(start_offset, pos.line, pos.column + name.len() as u32);
    let end = Pos::new(start_offset + 2, pos.line, start.column + 2);
    Some(DiagnosticFix {
        pos: start,
        end,
        replacement: String::new(),
    })
}

/// The source text of the written expression `e`, with its range.
fn expr_range<'s>(source: &'s str, e: &Expr) -> Option<(Pos, Pos, &'s str)> {
    let (start, end) = (e.start(), e.end);
    if end.offset <= start.offset {
        return None;
    }
    let text = source.get(start.offset as usize..end.offset as usize)?;
    Some((start, end, text))
}

/// Rewrites the expression `e` into `build(text, atomic)`, where `atomic`
/// says a `.method()` suffix binds to all of `text` without parentheses.
pub(crate) fn rewrite_expr(
    source: &str,
    e: &Expr,
    build: impl Fn(&str, bool) -> Option<String>,
) -> Option<DiagnosticFix> {
    let (pos, end, text) = expr_range(source, e)?;
    let atomic = matches!(
        e.kind,
        ExprKind::Name(_)
            | ExprKind::Member { .. }
            | ExprKind::Call { .. }
            | ExprKind::Index { .. }
            | ExprKind::Apply { .. }
            | ExprKind::List(_)
            | ExprKind::Map(_)
    );
    Some(DiagnosticFix {
        pos,
        end,
        replacement: build(text, atomic)?,
    })
}

/// `value.suffix` for the expression `e`.
pub(crate) fn append_call(source: &str, e: &Expr, call: &str) -> Option<DiagnosticFix> {
    rewrite_expr(source, e, |text, atomic| {
        Some(if atomic {
            format!("{text}.{call}")
        } else {
            format!("({text}).{call}")
        })
    })
}

/// `f"{value}"` for the expression `e`, unless its text would not nest.
pub(crate) fn interpolate(source: &str, e: &Expr) -> Option<DiagnosticFix> {
    // A plain integer literal is its own text; `"{3}"` would read as a regex quantifier.
    let digits = matches!(e.kind, ExprKind::Number(_));
    rewrite_expr(source, e, |text, _| {
        if digits && !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit()) {
            return Some(format!("\"{text}\""));
        }
        (!text.contains(['"', '{', '}', '\n'])).then(|| format!("\"{{{text}}}\""))
    })
}

/// Whether the operator of the binary expression at `pos` is the `op` of a compound
/// assignment (`x += y`). The parser desugars that to `x = x + y`, so the left operand
/// is the assignment target and no fix may rewrite it.
pub(crate) fn is_compound_operator(source: &str, pos: Pos, op: &str) -> bool {
    source.as_bytes().get(pos.offset as usize + op.len()) == Some(&b'=')
}

/// Converts the Int expression `e` to Float: `3` becomes `3.0`, else `.to_float()`.
pub(crate) fn to_float(source: &str, e: &Expr) -> Option<DiagnosticFix> {
    float_literal(source, e).or_else(|| append_call(source, e, "to_float()"))
}

/// `3` becomes `3.0` for a plain decimal Int literal.
fn float_literal(source: &str, e: &Expr) -> Option<DiagnosticFix> {
    if !matches!(e.kind, ExprKind::Number(_)) {
        return None;
    }
    rewrite_expr(source, e, |text, _| {
        (!text.is_empty() && text.bytes().all(|b| b.is_ascii_digit())).then(|| format!("{text}.0"))
    })
}

/// The conversion fix for an `actual` value used where `expected` is required.
pub(crate) fn conversion_fix(
    source: &str,
    e: &Expr,
    actual: &str,
    expected: &str,
) -> Option<DiagnosticFix> {
    match (actual, expected) {
        ("Int", "Float") => to_float(source, e),
        ("Int" | "Float" | "Bool", "String") => interpolate(source, e),
        _ => None,
    }
}

impl Checker {
    /// A type diagnostic carrying an already-built fix.
    pub(crate) fn type_error_with_fix(
        &mut self,
        pos: Pos,
        cause: Cause,
        message: String,
        fix: Option<DiagnosticFix>,
    ) {
        let count = self.p.diagnostics.len();
        self.error_with_cause(pos, Phase::Type, cause, message);
        if self.p.diagnostics.len() > count
            && let Some(last) = self.p.diagnostics.last_mut()
        {
            last.fix = fix;
        }
    }

    /// A resolution diagnostic carrying an already-built fix.
    pub(crate) fn res_error_with_fix(
        &mut self,
        pos: Pos,
        message: String,
        fix: Option<DiagnosticFix>,
    ) {
        let count = self.p.diagnostics.len();
        self.error(pos, Phase::Resolution, message);
        if self.p.diagnostics.len() > count
            && let Some(last) = self.p.diagnostics.last_mut()
        {
            last.fix = fix;
        }
    }

    /// A type diagnostic about the `len`-byte name at `pos`, with its fix.
    pub(crate) fn type_error_name(&mut self, pos: Pos, len: usize, message: String) {
        self.error_fixed(pos, len, Phase::Type, message);
    }

    /// A resolution diagnostic that `name` (at `pos`) is unknown, with its fix.
    pub(crate) fn unknown_error(&mut self, pos: Pos, name: ms_syntax::Symbol, message: String) {
        let len = self.syms.str(name).len();
        self.error_fixed_caused(pos, len, Phase::Resolution, Cause::Unknown(name), message);
    }

    fn error_fixed(&mut self, pos: Pos, len: usize, phase: Phase, message: String) {
        self.error_fixed_caused(pos, len, phase, Cause::Other, message);
    }

    pub(crate) fn error_fixed_caused(
        &mut self,
        pos: Pos,
        len: usize,
        phase: Phase,
        cause: Cause,
        message: String,
    ) {
        let fix = fix_for(&message, pos, len);
        let count = self.p.diagnostics.len();
        self.error_with_cause(pos, phase, cause, message);
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
    fn habit_names_are_fixed() {
        let pos = Pos::new(4, 1, 5);
        let fix = fix_for("unknown binding True; write the lowercase true", pos, 4).unwrap();
        assert_eq!((fix.end.offset, fix.replacement.as_str()), (8, "true"));
        let this = "unknown binding this; the receiver in an impl method is 'self'; write self instead of this";
        assert_eq!(fix_for(this, pos, 4).unwrap().replacement, "self");
        assert!(fix_for("unknown binding this; there is no 'this'", pos, 4).is_none());
    }

    #[test]
    fn immutable_binding_becomes_var() {
        let fix = binding_to_var("x := 1", Pos::new(0, 1, 1)).unwrap();
        assert_eq!(
            (fix.pos.offset, fix.end.offset, fix.replacement.as_str()),
            (0, 4, "var x =")
        );
        let typed = binding_to_var("x: Int := 1", Pos::new(0, 1, 1)).unwrap();
        assert_eq!(
            (typed.end.offset, typed.replacement.as_str()),
            (9, "var x: Int =")
        );
        assert!(binding_to_var("for x in xs", Pos::new(4, 1, 5)).is_none());
    }

    #[test]
    fn nullary_call_parens_are_dropped() {
        let fix = drop_case_parens("  Red()", Pos::new(2, 1, 3), "Red").unwrap();
        assert_eq!((fix.pos.offset, fix.end.offset), (5, 7));
        assert!(drop_case_parens("Red(1)", Pos::new(0, 1, 1), "Red").is_none());
    }

    #[test]
    fn import_hint_inserts_at_file_start() {
        let message = "unknown binding stdout; add: import stdout from \"@std/io\"";
        let fix = fix_for(message, Pos::new(40, 3, 1), 6).unwrap();
        assert_eq!(fix.pos.offset, 0);
        assert_eq!(fix.replacement, "import stdout from \"@std/io\"\n");
    }
}

//! The pure fix builders of `ms-check`'s `suggestions.rs`, copied with the checker removed, for the
//! C port in `src/compiler/src/syntax/fixes.c` to be diffed against (`src/compiler/tests/fixes-diff.sh`). Each
//! stdin line is one tab-separated case and each output line its fix (`gen COUNT SEED` writes
//! random cases). Temporary tooling for the C rewrite: delete it with the Rust checker.
//!   F message offset line column len     fix_for
//!   B source offset line column          binding_to_var
//!   D source offset line column name     drop_case_parens
//!   K source offset op                   is_compound_operator
//!   X op text [actual expected]          an expression fix on `A := text`
//! Sources escape a newline as `\n`.

use ms_syntax::ast::*;
use ms_syntax::parser::parse;
use ms_syntax::{DiagnosticFix, Pos};
use std::io::{BufRead, Write};
use std::sync::Arc;

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
fn habit_replacement(message: &str) -> Option<String> {
    let rest = message.strip_prefix("unknown binding ")?;
    let (name, hint) = rest.split_once("; ")?;
    let word = match name {
        "Ok" => "ok",
        "Err" | "err" | "Error" => "error",
        "True" => "true",
        "False" => "false",
        "nil" | "null" | "None" | "undefined" => "none",
        "this" if hint.ends_with("write self instead of this") => "self",
        _ if hint.ends_with(&format!("so write self.{name}")) => {
            return Some(format!("self.{name}"));
        }
        _ => return None,
    };
    Some(word.to_string())
}

/// The fix for a diagnostic at `pos` whose offending name has `len` bytes.
fn fix_for(message: &str, pos: Pos, len: usize) -> Option<DiagnosticFix> {
    if let Some(name) = habit_replacement(message) {
        let end = Pos::new(pos.offset + len as u32, pos.line, pos.column + len as u32);
        return Some(DiagnosticFix {
            pos,
            end,
            replacement: name,
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
fn binding_to_var(source: &str, decl: Pos) -> Option<DiagnosticFix> {
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
fn drop_case_parens(source: &str, pos: Pos, name: &str) -> Option<DiagnosticFix> {
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
fn rewrite_expr(
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
fn append_call(source: &str, e: &Expr, call: &str) -> Option<DiagnosticFix> {
    rewrite_expr(source, e, |text, atomic| {
        Some(if atomic {
            format!("{text}.{call}")
        } else {
            format!("({text}).{call}")
        })
    })
}

/// `value()` for a no-argument method named without its parentheses.
fn append_parens(source: &str, e: &Expr) -> Option<DiagnosticFix> {
    rewrite_expr(source, e, |text, atomic| {
        atomic.then(|| format!("{text}()"))
    })
}

/// `value.is_none()` or `value.is_some()` for `value == none` / `value != none`.
fn none_test(source: &str, whole: &Expr, other: &Expr, present: bool) -> Option<DiagnosticFix> {
    let (pos, end, _) = expr_range(source, whole)?;
    let inner = rewrite_expr(source, other, |text, atomic| {
        let call = if present { "is_some()" } else { "is_none()" };
        Some(if atomic {
            format!("{text}.{call}")
        } else {
            format!("({text}).{call}")
        })
    })?;
    Some(DiagnosticFix {
        pos,
        end,
        replacement: inner.replacement,
    })
}

/// `f"{value}"` for the expression `e`, unless its text would not nest.
fn interpolate(source: &str, e: &Expr) -> Option<DiagnosticFix> {
    // A plain integer literal is its own text; `f"{3}"` would read as a regex quantifier.
    let digits = matches!(e.kind, ExprKind::Number(_));
    rewrite_expr(source, e, |text, _| {
        if digits && !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit()) {
            return Some(format!("\"{text}\""));
        }
        (!text.contains(['"', '{', '}', '\n'])).then(|| format!("f\"{{{text}}}\""))
    })
}

/// Whether the operator of the binary expression at `pos` is the `op` of a compound
/// assignment (`x += y`). The parser desugars that to `x = x + y`, so the left operand
/// is the assignment target and no fix may rewrite it.
fn is_compound_operator(source: &str, pos: Pos, op: &str) -> bool {
    source.as_bytes().get(pos.offset as usize + op.len()) == Some(&b'=')
}

/// Converts the Int expression `e` to Float: `3` becomes `3.0`, else `.to_float()`.
fn to_float(source: &str, e: &Expr) -> Option<DiagnosticFix> {
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
fn conversion_fix(source: &str, e: &Expr, actual: &str, expected: &str) -> Option<DiagnosticFix> {
    match (actual, expected) {
        ("Int", "Float") => to_float(source, e),
        ("Int" | "Float" | "Bool", "String") => interpolate(source, e),
        ("String", "Error" | "@std/Error") => {
            rewrite_expr(source, e, |text, _| Some(format!("Error({text})")))
        }
        _ => None,
    }
}
fn unescape(s: &str) -> String {
    s.replace("\\n", "\n")
}

fn show(fix: Option<DiagnosticFix>) -> String {
    let Some(f) = fix else { return "-".into() };
    format!(
        "{}:{}:{}-{}:{}:{}={}",
        f.pos.offset,
        f.pos.line,
        f.pos.column,
        f.end.offset,
        f.end.line,
        f.end.column,
        f.replacement.replace('\n', "\\n")
    )
}

fn pos_of(f: &[&str]) -> Pos {
    Pos::new(
        f[0].parse().unwrap(),
        f[1].parse().unwrap(),
        f[2].parse().unwrap(),
    )
}

/// Runs `with` on the value of the constant `A := text`.
fn on_expr(text: &str, with: impl Fn(&str, &Expr) -> String) -> String {
    let source = format!("A := {text}\n");
    let file: Arc<str> = Arc::from("f.ms");
    let Ok(module) = parse(&file, &source) else {
        return "parse-error".into();
    };
    match module.decls.first().map(|d| &d.kind) {
        Some(DeclKind::Const(c)) => with(&source, &c.value),
        _ => "not-constant".into(),
    }
}

fn expression(f: &[&str]) -> String {
    on_expr(f[1], |source, e| match f[0] {
        "call" => show(append_call(source, e, "call()")),
        "parens" => show(append_parens(source, e)),
        "none" => match &e.kind {
            ExprKind::Binary { left, .. } => show(none_test(source, e, left, f[2] == "present")),
            _ => "not-binary".into(),
        },
        "interpolate" => show(interpolate(source, e)),
        "float" => show(to_float(source, e)),
        "convert" => show(conversion_fix(source, e, f[2], f[3])),
        other => panic!("unknown expression op {other}"),
    })
}

fn answer(line: &str) -> String {
    let f: Vec<&str> = line.split('\t').collect();
    match f[0] {
        "F" => show(fix_for(
            &unescape(f[1]),
            pos_of(&f[2..5]),
            f[5].parse().unwrap(),
        )),
        "B" => show(binding_to_var(&unescape(f[1]), pos_of(&f[2..5]))),
        "D" => show(drop_case_parens(&unescape(f[1]), pos_of(&f[2..5]), f[5])),
        "K" => is_compound_operator(&unescape(f[1]), Pos::new(f[2].parse().unwrap(), 1, 1), f[3])
            .to_string(),
        "X" => expression(&f[1..]),
        other => panic!("unknown op {other}"),
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
    fn pick<'a>(&mut self, items: &[&'a str]) -> &'a str {
        items[self.below(items.len())]
    }
}

const NAMES: &[&str] = &[
    "Ok",
    "Err",
    "err",
    "Error",
    "True",
    "False",
    "nil",
    "null",
    "None",
    "undefined",
    "this",
    "count",
    "x",
];
const HINTS: &[&str] = &[
    "write the lowercase true",
    "the receiver in an impl method is 'self'; write self instead of this",
    "there is no 'this'",
    "declare it",
    "did you mean 'count'?",
    "so write self.count",
    "so write self.x",
    "add: import stdout from \"@std/io\"",
];
const TAILS: &[&str] = &[
    "; did you mean 'count'?",
    "; did you mean 'a' or 'b'?",
    "; did you mean ''?",
    "; did you mean 'x'",
    "; add: import stdout from \"@std/io\"",
    "; add: import a from \"b\"\\nmore",
    "; add: use x",
    "; add: import  ",
    "",
];
const SOURCES: &[&str] = &[
    "x := 1",
    "x: Int := 1",
    "x : Int := 1",
    "x  := 1",
    "x: Int",
    "x: Int, y: Int := 2",
    "x: Fn(Int) := 1",
    "x: T) := 1",
    "for x in xs",
    "  Red()",
    "Red()",
    "Red(1)",
    "Red",
    "x: Int\\ny := 1",
    "naïve := 1",
    "x: Üint := 1",
    "a.b() += 1",
    "x += 1",
    "x +=",
    "",
];
const EXPRS: &[&str] = &[
    "x",
    "3",
    "42",
    "1.5",
    "0xFF",
    "1_000",
    "a.b",
    "f(x)",
    "a[0]",
    "[1, 2]",
    "x + 1",
    "-x",
    "-3",
    "(x)",
    "(1 + 2)",
    "a.b(c)",
    "m.get(k)",
    "\"s\"",
    "\"a{b}\"",
    "f\"v\"",
    "x == y",
    "a.b == c",
    "x < y",
    "xs[i] + 1",
    "[1][0]",
    "{a: 1}",
    "g[T]",
    "x?",
    "a.b?",
    "not x",
    "true",
    "none",
    "fn(x) Int: x",
    "match x { }",
];

fn escape(s: &str) -> String {
    s.replace('\n', "\\n")
}

fn generate(count: usize, seed: u64) {
    let mut r = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
    let out = std::io::stdout();
    let mut out = out.lock();
    for _ in 0..count {
        let line = match r.below(6) {
            0 => {
                let message = if r.below(2) == 0 {
                    format!("unknown binding {}; {}", r.pick(NAMES), r.pick(HINTS))
                } else {
                    format!("unknown binding {}{}", r.pick(NAMES), r.pick(TAILS))
                };
                format!(
                    "F\t{}\t{}\t{}\t{}\t{}",
                    escape(&message),
                    r.below(40),
                    1 + r.below(5),
                    1 + r.below(30),
                    r.below(8)
                )
            }
            1 | 2 => {
                let s = r.pick(SOURCES);
                let op = if r.below(2) == 0 { "B" } else { "D" };
                let name = r.pick(&["Red", "x", "", "naïve"]);
                let tail = if op == "D" {
                    format!("\t{name}")
                } else {
                    String::new()
                };
                format!(
                    "{op}\t{s}\t{}\t{}\t{}{tail}",
                    r.below(s.len() + 3),
                    1 + r.below(3),
                    1 + r.below(10)
                )
            }
            3 => {
                let s = r.pick(SOURCES);
                format!(
                    "K\t{s}\t{}\t{}",
                    r.below(s.len() + 2),
                    r.pick(&["+", "-", "*", "==", "<"])
                )
            }
            _ => {
                let e = r.pick(EXPRS);
                match r.below(6) {
                    0 => format!("X\tcall\t{e}"),
                    1 => format!("X\tparens\t{e}"),
                    2 => format!(
                        "X\tnone\t{e} {} none\t{}",
                        r.pick(&["==", "!="]),
                        r.pick(&["present", "absent"])
                    ),
                    3 => format!("X\tinterpolate\t{e}"),
                    4 => format!("X\tfloat\t{e}"),
                    _ => format!(
                        "X\tconvert\t{e}\t{}\t{}",
                        r.pick(&["Int", "Float", "Bool", "String", "List"]),
                        r.pick(&["Float", "String", "Error", "@std/Error", "Int"])
                    ),
                }
            }
        };
        writeln!(out, "{line}").unwrap();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("gen") {
        generate(args[2].parse().unwrap(), args[3].parse().unwrap());
        return;
    }
    let stdin = std::io::stdin();
    let out = std::io::stdout();
    let mut out = out.lock();
    for line in stdin.lock().lines() {
        writeln!(out, "{}", answer(&line.unwrap())).unwrap();
    }
}

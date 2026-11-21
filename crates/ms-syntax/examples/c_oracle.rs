//! Prints the lexer's tokens or the parser's tree for each file in a canonical text form, so the C
//! front end in `src/compiler/` can be compared with it byte for byte (`make c-compiler-test`).
//! Temporary tooling for the C rewrite: delete it with the Rust front end.

use ms_syntax::diag::Diagnostic;
use ms_syntax::dump::{dump_module, quote};
use ms_syntax::lexer::lex;
use ms_syntax::parser::parse;
use ms_syntax::{Names, Pos};
use std::fmt::Write;
use std::sync::Arc;

fn pos(out: &mut String, p: Pos) {
    let _ = write!(out, "{}:{}:{}", p.line, p.column, p.offset);
}

fn diag(out: &mut String, d: &Diagnostic) {
    out.push_str("error ");
    pos(out, d.pos);
    out.push_str(" end=");
    match d.end {
        Some(e) => pos(out, e),
        None => out.push('-'),
    }
    out.push_str(" fix=");
    match &d.fix {
        Some(f) => {
            pos(out, f.pos);
            out.push('-');
            pos(out, f.end);
            out.push('=');
            out.push_str(&quote(&f.replacement));
        }
        None => out.push('-'),
    }
    let _ = writeln!(out, " opener={} {}", d.opener_line, quote(&d.message));
}

/// A `.txt` file lists `phase<TAB>message` lines; a source file contributes its parse error.
fn codes(out: &mut String, path: &str, text: &str, file: &Arc<str>) {
    let mut line = |phase: &str, message: &str| {
        let d = Diagnostic {
            phase: match phase {
                "parse" => ms_syntax::diag::Phase::Parse,
                "resolution" => ms_syntax::diag::Phase::Resolution,
                "type" => ms_syntax::diag::Phase::Type,
                "lowering" => ms_syntax::diag::Phase::Lowering,
                "format" => ms_syntax::diag::Phase::Format,
                _ => ms_syntax::diag::Phase::Execution,
            },
            ..Diagnostic::parse(file, Pos::default(), message)
        };
        let _ = writeln!(out, "{} {}", d.code(), d.subcode().unwrap_or("-"));
    };
    if path.ends_with(".txt") {
        for l in text.lines() {
            let (phase, message) = l.split_once('\t').unwrap_or((l, ""));
            line(phase, message);
        }
    } else if let Err(d) = parse(file, text) {
        line("parse", &d.message);
    }
}

/// Prints `kind id offset` for the imports, declarations, statements and expressions of a module,
/// in walk order, to check that node ids are allocated as the C parser allocates them.
struct IdLines<'a>(&'a mut String);

impl ms_syntax::visit::Visitor for IdLines<'_> {
    fn stmt(&mut self, s: &ms_syntax::ast::Stmt) {
        let _ = writeln!(self.0, "S {} {}", s.id.0, s.pos.offset);
    }
    fn expr(&mut self, e: &ms_syntax::ast::Expr) {
        let _ = writeln!(self.0, "E {} {}", e.id.0, e.pos.offset);
    }
}

fn node_ids(out: &mut String, m: &ms_syntax::ast::Module) {
    for i in &m.imports {
        let _ = writeln!(out, "I {} {}", i.id.0, i.pos.offset);
    }
    for d in &m.decls {
        let _ = writeln!(out, "D {} {}", d.id.0, d.pos.offset);
        ms_syntax::visit::walk_decl(&mut IdLines(out), d);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = args[0].as_str();
    let mut out = String::new();
    for path in &args[1..] {
        let bytes = std::fs::read(path).expect("read");
        let _ = writeln!(out, "=== {path}");
        let Ok(text) = std::str::from_utf8(&bytes) else {
            out.push_str("error invalid-utf8\n");
            continue;
        };
        let file: Arc<str> = Arc::from("f.ms");
        if mode == "codes" {
            codes(&mut out, path, text, &file);
            continue;
        }
        match mode {
            "partial" => {
                let (m, diags) = ms_syntax::partial::parse_partial(&file, text);
                out.push_str(&dump_module(Names::global(), &m));
                let _ = writeln!(out, "nodes {}", m.node_count);
                for d in &diags {
                    diag(&mut out, d);
                }
            }
            "format" => match ms_syntax::format::format(&file, text) {
                Ok(formatted) => out.push_str(&formatted),
                Err(d) => diag(&mut out, &d),
            },
            "ids" => match parse(&file, text) {
                Ok(m) => {
                    node_ids(&mut out, &m);
                    let _ = writeln!(out, "nodes {}", m.node_count);
                }
                Err(d) => diag(&mut out, &d),
            },
            "tokens" => match lex(&file, text) {
                Ok(l) => {
                    for t in &l.tokens {
                        let _ = write!(out, "{} {} {} ", t.kind.as_str(), t.lo, t.hi);
                        pos(&mut out, t.pos);
                        out.push(' ');
                        pos(&mut out, t.end);
                        out.push('\n');
                    }
                    for (a, b) in &l.block_comments {
                        let _ = writeln!(out, "block {a} {b}");
                    }
                }
                Err(d) => diag(&mut out, &d),
            },
            _ => match parse(&file, text) {
                Ok(m) => {
                    out.push_str(&dump_module(Names::global(), &m));
                    let _ = writeln!(out, "nodes {}", m.node_count);
                }
                Err(d) => diag(&mut out, &d),
            },
        }
    }
    print!("{out}");
}

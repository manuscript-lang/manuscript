//! Prints the lexer's tokens or the parser's tree for each file in a canonical text form, so the C
//! front end in `compiler/` can be compared with it byte for byte (`make c-compiler-test`).
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
        match mode {
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

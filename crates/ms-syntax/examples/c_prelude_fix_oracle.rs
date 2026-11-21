//! `prelude_import_fix` of `ms-check`'s `prelude_imports.rs`, copied with the checker removed, for
//! the C port in `src/compiler/src/syntax/prelude_fix.c` to be diffed against
//! (`src/compiler/tests/prelude-fix-diff.sh`). Each stdin line is a source with `\n` and `\r`
//! escapes; each output line lists the fix of every import binding of its editor-recovery parse.
//! `gen COUNT SEED` writes random sources. Temporary tooling for the C rewrite: delete it with the
//! Rust checker.

use ms_syntax::DiagnosticFix;
use ms_syntax::lexer;
use ms_syntax::token::{Tok, Token};
use std::io::{BufRead, Write};
use std::sync::Arc;

/// Removes one binding, preserving comments, neighboring bindings and
/// original line endings. This stays an exact source edit rather than
/// formatting the file.
fn prelude_import_fix(
    source: &str,
    imports: &[ms_syntax::ast::Import],
    item: &ms_syntax::ast::Import,
) -> Option<DiagnosticFix> {
    let file: Arc<str> = Arc::from("f.ms");
    let tokens = match lexer::lex(&file, source) {
        Ok(lexed) => lexed.tokens,
        // A recovering editor snapshot can retain this valid import alongside
        // unrelated lexer errors. Lex only its complete declaration in that case.
        Err(_) => {
            let tokens = prelude_import_tokens(&file, source, item);
            if tokens.is_empty() {
                return None;
            }
            tokens
        }
    };
    let at = tokens
        .iter()
        .position(|t| t.pos.offset == item.name_pos.offset)?;
    let count = imports
        .iter()
        .filter(|other| other.clause.offset == item.clause.offset)
        .count();
    if count == 1 && item.in_group(source, &tokens) {
        let only = imports.iter().all(|other| {
            other.pos.offset != item.pos.offset || other.clause.offset == item.clause.offset
        });
        let (start, end) = item.group_removal(source, &tokens, only)?;
        let at = |offset: usize| {
            let before = &source[..offset];
            let line = before.matches('\n').count() as u32 + 1;
            let column = (offset - before.rfind('\n').map_or(0, |i| i + 1)) as u32 + 1;
            ms_syntax::Pos {
                offset: offset as u32,
                line,
                column,
            }
        };
        return Some(DiagnosticFix {
            pos: at(start),
            end: at(end),
            replacement: String::new(),
        });
    }
    let name = tokens[at];
    let text =
        |from: u32, to: u32| -> &str { source.get(from as usize..to as usize).unwrap_or("") };
    let trivia_of = |trivia: &str| -> String {
        if trivia.contains("//") || trivia.contains("/*") {
            trivia.to_string()
        } else {
            String::new()
        }
    };
    if count > 1 {
        // The last binding of a group takes the comma before it, not its trailing
        // comma: its edit then overlaps its neighbor's, so redundant names are
        // removed over successive runs until the whole import goes, never leaving
        // an empty `import ( ) from ...`.
        let last = tokens.get(at + 2).is_none_or(|t| t.kind == Tok::RParen);
        let previous_comma = at > 0 && tokens[at - 1].kind == Tok::Comma;
        if at + 1 < tokens.len() && tokens[at + 1].kind == Tok::Comma && !(last && previous_comma) {
            let comma = tokens[at + 1];
            let mut end = comma.end;
            if at + 2 < tokens.len() && tokens[at + 2].pos.line == comma.end.line {
                end = tokens[at + 2].pos;
            }
            let trivia = trivia_of(text(name.end.offset, comma.pos.offset));
            return Some(DiagnosticFix {
                pos: name.pos,
                end,
                replacement: trivia,
            });
        }
        if at > 0 && tokens[at - 1].kind == Tok::Comma {
            let comma = tokens[at - 1];
            let mut end = name.end;
            if at + 1 < tokens.len() && tokens[at + 1].kind == Tok::Comma {
                end = tokens[at + 1].end;
            }
            let trivia = trivia_of(text(comma.end.offset, name.pos.offset));
            return Some(DiagnosticFix {
                pos: comma.pos,
                end,
                replacement: trivia,
            });
        }
        return None;
    }
    // Delete a singleton import, retaining any comments inside a multiline
    // group and any trailing comment after the path string.
    let mut end = name.end;
    let mut comments = String::new();
    let mut previous = item.pos.offset;
    for token in &tokens {
        if token.pos.offset < item.pos.offset {
            continue;
        }
        let trivia = text(previous, token.pos.offset);
        if trivia.contains("//") || trivia.contains("/*") {
            comments.push_str(trivia);
        }
        previous = token.end.offset;
        if token.kind == Tok::String {
            end = token.end;
            break;
        }
    }
    let mut fix = DiagnosticFix {
        pos: item.pos,
        end,
        replacement: comments.clone(),
    };
    if comments.is_empty() {
        let tail = source.get(end.offset as usize..).unwrap_or("");
        match tail.find('\n') {
            Some(n) if tail[..n].trim().is_empty() => {
                fix.end.offset += n as u32 + 1;
                fix.end.line += 1;
                fix.end.column = 1;
            }
            _ if tail.trim().is_empty() => {
                fix.end.offset = source.len() as u32;
                fix.end.column += tail.len() as u32;
            }
            _ => {}
        }
    }
    Some(fix)
}

/// Lexes only the complete declaration of `item`, with positions shifted back
/// into the whole file.
fn prelude_import_tokens(
    file: &Arc<str>,
    source: &str,
    item: &ms_syntax::ast::Import,
) -> Vec<Token> {
    let start = item.pos.offset as usize;
    let mut end = start;
    while end < source.len() {
        match source[end..].find('\n') {
            Some(n) => end += n + 1,
            None => end = source.len(),
        }
        let Ok(lexed) = lexer::lex(file, &source[start..end]) else {
            continue;
        };
        if !lexed.tokens.iter().any(|t| t.kind == Tok::String) {
            continue;
        }
        let mut tokens = lexed.tokens;
        for t in &mut tokens {
            for pos in [&mut t.pos, &mut t.end] {
                if pos.line == 1 {
                    pos.column += item.pos.column - 1;
                }
                pos.line += item.pos.line - 1;
                pos.offset += start as u32;
            }
        }
        return tokens;
    }
    Vec::new()
}

fn show(fix: Option<DiagnosticFix>) -> String {
    let Some(f) = fix else { return "-".into() };
    format!(
        "{}:{}:{}-{}:{}:{}=[{}]",
        f.pos.offset,
        f.pos.line,
        f.pos.column,
        f.end.offset,
        f.end.line,
        f.end.column,
        f.replacement.replace('\n', "\\n").replace('\r', "\\r")
    )
}

fn answer(line: &str) -> String {
    let source = line.replace("\\n", "\n").replace("\\r", "\r");
    let file: Arc<str> = Arc::from("f.ms");
    let (module, _) = ms_syntax::partial::parse_partial(&file, &source);
    let fixes: Vec<String> = module
        .imports
        .iter()
        .map(|item| show(prelude_import_fix(&source, &module.imports, item)))
        .collect();
    format!("{} {}", module.imports.len(), fixes.join(" | "))
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

const STATEMENTS: &[&str] = &[
    "import a from \"x\"",
    "import a, b from \"x\"",
    "import a, b, c from \"x\"",
    "import (a from \"x\")",
    "import (a from \"x\", b from \"y\")",
    "import (\\n    a from \"x\",\\n    b from \"y\",\\n)",
    "import (\\n    a from \"x\", // keep\\n    b, c from \"y\"\\n)",
    "import (\\n    // lead\\n    a from \"x\"\\n)",
    "import (a, b from \"x\", c from \"y\")",
    "import a from \"x\" // trailing",
    "import a /* c */ from \"x\"",
    "import a, /* c */ b from \"x\"",
    "import a,\\n  b from \"x\"",
    "import a from \"x\"    ",
    "import a from \"x\";",
    "import a from \"unterminated",
    "import a from",
    "import ((a from \"x\"))",
    "  import a from \"x\"",
];
const FILLER: &[&str] = &[
    "",
    "fn f() Void:\\n    return",
    "// note",
    "A := 1",
    "x := \"s\"",
    "naïve := 1",
];

fn generate(count: usize, seed: u64) {
    let mut r = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
    let out = std::io::stdout();
    let mut out = out.lock();
    for _ in 0..count {
        let n = 1 + r.below(3);
        let mut parts: Vec<&str> = (0..n).map(|_| r.pick(STATEMENTS)).collect();
        if r.below(2) == 0 {
            parts.push(r.pick(FILLER));
        }
        let sep = ["\\n", "\\n", "\\n\\n", "\\r\\n"][r.below(4)];
        let mut line = parts.join(sep);
        if r.below(3) != 0 {
            line.push_str(sep);
        }
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

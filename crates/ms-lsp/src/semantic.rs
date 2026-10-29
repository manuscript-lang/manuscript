//! `textDocument/semanticTokens/full`.

use crate::analysis::{Analysis, Document};
use crate::index::{Occurrence, expr_text};
use crate::json::{Json, obj};
use crate::text::{self, EditorKind, SourcePositions};
use ms_check::types::Kind;
use ms_syntax::ast::*;
use ms_syntax::token::{KEYWORDS, Tok};
use ms_syntax::visit::{self, Visitor};
use std::collections::HashMap;
use std::sync::Arc;

/// The legend, in kind-number order.
pub const TOKEN_TYPES: [&str; 11] = [
    "keyword",
    "variable",
    "number",
    "string",
    "comment",
    "function",
    "type",
    "property",
    "parameter",
    "enumMember",
    "typeParameter",
];

#[derive(Copy, Clone, PartialEq, Eq)]
enum Lex {
    Name,
    Number,
    Str,
    Comment,
    Keyword,
    Skip,
}

struct Token {
    kind: Lex,
    previous_fn: bool,
    previous_type: bool,
    text: String,
    offset: usize,
}

fn lexer_tokens(d: &Document) -> Vec<Token> {
    let mut tokens = scanned_tokens(d);
    // `opaque` is contextual: a keyword only in front of `type`.
    for i in 1..tokens.len() {
        if tokens[i - 1].kind == Lex::Name
            && tokens[i - 1].text == "opaque"
            && tokens[i].kind == Lex::Keyword
            && tokens[i].text == "type"
        {
            tokens[i - 1].kind = Lex::Keyword;
        }
    }
    tokens
}

fn scanned_tokens(d: &Document) -> Vec<Token> {
    let file: Arc<str> = Arc::from(d.path().as_str());
    if let Ok(lexed) = ms_syntax::lexer::lex(&file, &d.text) {
        let mut tokens = Vec::with_capacity(lexed.tokens.len());
        let mut previous = Tok::Eof;
        for t in &lexed.tokens {
            let kind = match t.kind {
                Tok::Name => Lex::Name,
                Tok::Number => Lex::Number,
                Tok::String => Lex::Str,
                Tok::Comment => Lex::Comment,
                Tok::Newline | Tok::Indent | Tok::Dedent | Tok::Eof => Lex::Skip,
                other => {
                    if other.as_str().as_bytes()[0].is_ascii_lowercase() {
                        Lex::Keyword
                    } else {
                        Lex::Skip
                    }
                }
            };
            tokens.push(Token {
                kind,
                previous_fn: previous == Tok::Fn,
                previous_type: previous == Tok::Type,
                text: lexed.source[t.lo as usize..t.hi as usize].to_string(),
                offset: t.pos.offset as usize,
            });
            previous = t.kind;
        }
        return tokens;
    }
    // The text does not lex: fall back to the forgiving scanner.
    let mut tokens = Vec::new();
    let mut previous = "";
    for t in text::editor_tokens(&d.text) {
        let kind = match t.kind {
            EditorKind::Name => {
                if KEYWORDS.contains(&t.text) {
                    Lex::Keyword
                } else if t.text.as_bytes()[0].is_ascii_digit() {
                    Lex::Number
                } else {
                    Lex::Name
                }
            }
            EditorKind::Str => Lex::Str,
            EditorKind::Comment => Lex::Comment,
            EditorKind::Char(_) => Lex::Skip,
        };
        tokens.push(Token {
            kind,
            previous_fn: previous == "fn",
            previous_type: previous == "type",
            text: t.text.to_string(),
            offset: t.start,
        });
        previous = if t.kind == EditorKind::Name {
            t.text
        } else {
            ""
        };
    }
    tokens
}

struct Kinds<'a> {
    module: &'a ms_check::syntax::ModRef,
    resolved: &'a mut HashMap<usize, i64>,
}

impl Kinds<'_> {
    fn consider(&mut self, e: &Expr) {
        if expr_text(e).is_none() {
            return;
        }
        let Some(info) = self.module.facts().info(e.id).cloned() else {
            return;
        };
        if let Some(symbol) = &info.symbol
            && symbol.kind == ms_check::types::SymKind::Type
        {
            self.resolved.insert(e.pos.offset as usize, 6);
        } else if info.ty.as_ref().is_some_and(|t| t.kind == Kind::Function)
            && info.symbol.as_ref().is_none_or(|s| !s.is_constant())
        {
            self.resolved.insert(e.pos.offset as usize, 5);
        }
    }
}

impl Visitor for Kinds<'_> {
    fn expr(&mut self, e: &Expr) {
        self.consider(e);
        if let ExprKind::Match { arms, .. } = &e.kind {
            for arm in arms {
                let mut path = &arm.path;
                loop {
                    self.consider(path);
                    match &path.kind {
                        ExprKind::Member { left, .. } | ExprKind::Apply { left, .. } => path = left,
                        _ => break,
                    }
                }
            }
        }
    }
}

/// The encoded tokens of a document, using the checked index when available.
pub fn semantic_tokens(analysis: Option<&Analysis>, index: &[Occurrence], d: &Document) -> Json {
    let tokens = lexer_tokens(d);
    let mut resolved: HashMap<usize, i64> = HashMap::new();
    if let Some(analysis) = analysis {
        let file = analysis.module_file(d);
        for entry in index {
            if entry.file.as_str() != file {
                continue;
            }
            let Some(info) = &entry.info else { continue };
            let mut kind = 1;
            if entry.key.starts_with("field:") {
                kind = 7;
            } else if entry.key.starts_with("parameter:") {
                kind = 8;
            } else if entry.key.starts_with("case:") {
                kind = 9;
            } else if info
                .symbol
                .as_ref()
                .is_some_and(|s| s.kind == ms_check::types::SymKind::Type)
            {
                kind = 6;
            } else if info.ty.as_ref().is_some_and(|t| t.kind == Kind::Function)
                && info.symbol.as_ref().is_none_or(|s| !s.is_constant())
            {
                kind = 5;
            }
            resolved.insert(entry.offset, kind);
        }
        if analysis.program.is_some()
            && let Some(module) = analysis.module(d)
        {
            let mut kinds = Kinds {
                module: &module,
                resolved: &mut resolved,
            };
            for decl in &module.decls {
                visit::walk_decl(&mut kinds, decl.decl());
            }
        }
    }
    let positions = SourcePositions::new(&d.text);
    let (mut line, mut character) = (0usize, 0usize);
    let mut data: Vec<Json> = Vec::new();
    for token in &tokens {
        let mut kind: i64 = match token.kind {
            Lex::Name => 1,
            Lex::Number => 2,
            Lex::Str => 3,
            Lex::Comment => 4,
            Lex::Keyword => 0,
            Lex::Skip => continue,
        };
        if token.kind == Lex::Name {
            if let Some(found) = resolved.get(&token.offset) {
                kind = *found;
            }
            if token.previous_fn {
                kind = 5;
            }
            if token.previous_type {
                kind = 6;
            }
        }
        let mut offset = token.offset;
        for part in token.text.split_inclusive('\n') {
            let body = part.strip_suffix('\n').unwrap_or(part);
            let body = body.strip_suffix('\r').unwrap_or(body);
            let start = positions.position(offset);
            let end = positions.position(offset + body.len());
            let length = end.character as i64 - start.character as i64;
            if length > 0 {
                let mut delta = start.character as i64;
                if start.line == line {
                    delta -= character as i64;
                }
                data.extend([
                    Json::from((start.line as i64) - line as i64),
                    Json::from(delta),
                    Json::from(length),
                    Json::from(kind),
                    Json::from(0i64),
                ]);
                line = start.line;
                character = start.character;
            }
            offset += part.len();
        }
    }
    obj([("data", Json::Arr(data))])
}

//! Redundant prelude imports and their exact-source fix
//!.

use crate::checker::Checker;
use crate::syntax::*;
use ms_syntax::lexer;
use ms_syntax::token::{Tok, Token};
use ms_syntax::{Diagnostic, DiagnosticFix, Phase, Pos};
use std::sync::Arc;

impl Checker {
    /// Reports an import of a name every module already sees.
    pub(crate) fn redundant_prelude_import(
        &mut self,
        module: &ModRef,
        item: &ms_syntax::ast::Import,
    ) {
        let name_len = item.name.len() as u32;
        let end = Pos::new(
            item.name_pos.offset + name_len,
            item.name_pos.line,
            item.name_pos.column + name_len,
        );
        let name = &item.name;
        self.p.diagnostics.push(Diagnostic {
            file: module.file.as_str().into(),
            pos: item.name_pos,
            phase: Phase::Resolution,
            message: format!(
                "redundant prelude import {name}; remove {name} from this import and use its prelude declaration directly"
            ),
            end: Some(end),
            fix: prelude_import_fix(module, item),
        });
    }
}

/// Removes one binding, preserving comments, neighboring bindings and
/// original line endings. This stays an exact source edit rather than
/// formatting the file.
fn prelude_import_fix(module: &ModRef, item: &ms_syntax::ast::Import) -> Option<DiagnosticFix> {
    let file: Arc<str> = module.file.as_str().into();
    let source: &str = &module.source;
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
    let count = module
        .imports
        .iter()
        .filter(|other| other.pos.offset == item.pos.offset)
        .count();
    let name = tokens[at];
    let text =
        |from: u32, to: u32| -> &str { source.get(from as usize..to as usize).unwrap_or("") };
    let trivia_of = |trivia: &str| -> String {
        if trivia.contains('#') {
            trivia.to_string()
        } else {
            String::new()
        }
    };
    if count > 1 {
        if at + 1 < tokens.len() && tokens[at + 1].kind == Tok::Comma {
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
            if at + 1 < tokens.len() && tokens[at + 1].pos.line == name.end.line {
                end = tokens[at + 1].pos;
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
        if trivia.contains('#') {
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

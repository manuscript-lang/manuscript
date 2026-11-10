//! Statement compaction: rewrites that make a program shorter without changing its meaning.
//!
//! Each rewrite is a source edit found on the parsed tree. A candidate that
//! contains a comment, spans several lines in an unexpected place, or would exceed the
//! line width is left as written.

use super::{WIDTH, layout_token};
use crate::ast::*;
use crate::lexer::lex;
use crate::pos::Pos;
use crate::token::{Tok, Token};
use crate::visit::{self, Visitor};
use std::collections::HashSet;
use std::sync::Arc;

/// Returns `source` with its statements compacted, or `None` when nothing changes.
pub(super) fn compact(file: &Arc<str>, module: &Module, source: &str) -> Option<String> {
    let tokens = lex(file, source).ok()?.tokens;
    let mut pass = Compact {
        source,
        tokens: &tokens,
        edits: Vec::new(),
        else_ifs: HashSet::new(),
    };
    for d in &module.decls {
        visit::walk_decl(&mut pass, d);
    }
    if pass.edits.is_empty() {
        return None;
    }
    pass.edits.sort_unstable_by_key(|e| e.0);
    let mut result = String::with_capacity(source.len());
    let mut cursor = 0;
    for (from, to, text) in &pass.edits {
        if *from < cursor {
            continue;
        }
        result.push_str(&source[cursor..*from]);
        result.push_str(text);
        cursor = *to;
    }
    result.push_str(&source[cursor..]);
    Some(result)
}

struct Compact<'a> {
    source: &'a str,
    tokens: &'a [Token],
    edits: Vec<(usize, usize, String)>,
    /// Statements that are the `else if` of an enclosing `if`.
    else_ifs: HashSet<NodeId>,
}

impl Compact<'_> {
    /// `target = target op rest` as `target op= rest`.
    fn compound(&mut self, s: &Stmt, value: &Expr) {
        let ExprKind::Binary { op, right, .. } = &value.kind else {
            return;
        };
        let symbol = match op {
            BinaryOp::Add => '+',
            BinaryOp::Sub => '-',
            BinaryOp::Mul => '*',
            BinaryOp::Div => '/',
            BinaryOp::Rem => '%',
            _ => return,
        };
        let (from, to) = (s.pos.offset as usize, right.start().offset as usize);
        let Some(head) = self.source.get(from..to) else {
            return;
        };
        let Some(eq) = head.find('=') else { return };
        let target = head[..eq].trim_end();
        let squeezed: String = head.chars().filter(|c| !c.is_whitespace()).collect();
        let expected = format!("{}={}{}", target, target, symbol);
        if target.is_empty() || head.contains("//") || squeezed != expected {
            return;
        }
        self.edits.push((from, to, format!("{target} {symbol}= ")));
    }

    /// `if c:` over a single `return`, `break` or `continue` line becomes one line.
    fn inline_if(&mut self, s: &Stmt, body: &[Stmt]) {
        let [only] = body else { return };
        let end: Pos = match &only.kind {
            StmtKind::Return(Some(e)) => e.end,
            StmtKind::Return(None) | StmtKind::Break | StmtKind::Continue => {
                let Some(line_end) = self.line_end(only.pos.offset as usize) else {
                    return;
                };
                let text = self.source[only.pos.offset as usize..line_end].trim_end();
                if !matches!(text, "return" | "break" | "continue") {
                    return;
                }
                Pos {
                    offset: (only.pos.offset as usize + text.len()) as u32,
                    ..only.pos
                }
            }
            _ => return,
        };
        let start = self
            .tokens
            .partition_point(|t| t.pos.offset < only.pos.offset);
        let Some(colon) = self.tokens[..start]
            .iter()
            .rev()
            .find(|t| !layout_token(t.kind))
        else {
            return;
        };
        let (from, to) = (colon.hi as usize, only.pos.offset as usize);
        let Some(gap) = self.source.get(from..to) else {
            return;
        };
        if colon.kind != Tok::Colon || !gap.contains('\n') || !gap.chars().all(char::is_whitespace)
        {
            return;
        }
        // The header must sit on one line, and nothing may follow the body on its line.
        let if_start = s.pos.offset as usize;
        let Some(header) = self.source.get(if_start..colon.hi as usize) else {
            return;
        };
        let end_offset = end.offset as usize;
        let Some(line_end) = self.line_end(end_offset) else {
            return;
        };
        if header.contains('\n') || !self.source[end_offset..line_end].trim().is_empty() {
            return;
        }
        let body_text = &self.source[to..end_offset];
        // A multi-line text literal reaches this pass as a private-use placeholder.
        let masked = body_text
            .chars()
            .any(|c| ('\u{e000}'..='\u{f8ff}').contains(&c));
        if masked || body_text.contains('\n') || body_text.contains("//") {
            return;
        }
        let line_start = self.source[..if_start].rfind('\n').map_or(0, |n| n + 1);
        let width = self.source[line_start..colon.hi as usize].chars().count()
            + 1
            + body_text.chars().count();
        if width <= WIDTH {
            self.edits.push((from, to, " ".to_string()));
        }
    }

    fn line_end(&self, at: usize) -> Option<usize> {
        let rest = self.source.get(at..)?;
        Some(at + rest.find('\n').unwrap_or(rest.len()))
    }
}

impl Visitor for Compact<'_> {
    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::Assign {
                compound: None,
                value,
                ..
            } => self.compound(s, value),
            StmtKind::If {
                body, else_body, ..
            } => {
                if let [inner] = else_body.as_slice()
                    && matches!(inner.kind, StmtKind::If { .. })
                {
                    self.else_ifs.insert(inner.id);
                }
                if else_body.is_empty() && !self.else_ifs.contains(&s.id) {
                    self.inline_if(s, body);
                }
            }
            _ => {}
        }
    }
}

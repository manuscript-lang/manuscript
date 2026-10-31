//! Deterministic source formatter.
//!
//! The formatter keeps the lexer's tokens and comment text. The delimiter tree
//! gives expressions safe continuation boundaries; the AST identifies calls,
//! literals, parameters and statement values instead of guessing from token
//! spellings.

use crate::ast::*;
use crate::lexer::{PResult, lex};
use crate::parser::parse;
use crate::pos::Pos;
use crate::token::{Tok, Token};
use crate::visit::{self, Visitor};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

const WIDTH: usize = 88;

/// Formats `source`. Invalid syntax never produces output.
pub fn format(file: &Arc<str>, source: &str) -> PResult<String> {
    parse(file, source)?;
    let mut normalized = source.replace("\r\n", "\n");
    let mut lines: Vec<String> = normalized.split('\n').map(str::to_string).collect();
    let module = parse(file, &normalized)?;
    let breaks = paragraph_breaks(&module, &lines);
    let mut lexed = lex(file, &normalized)?.tokens;
    if let Some(aligned) = align_suite_headers(&lines, &lexed) {
        // Expression layout moves the closing line of a multi-line header back
        // to the statement's indentation, so its suite must move with it.
        normalized = aligned.join("\n");
        lines = aligned;
        lexed = lex(file, &normalized)?.tokens;
    }
    let mut by_line: Vec<Vec<Token>> = vec![Vec::new(); lines.len() + 2];
    for t in &lexed {
        if !t.kind.is_layout() {
            by_line[t.pos.line as usize].push(*t);
        }
    }
    let text = |t: &Token| &normalized[t.lo as usize..t.hi as usize];
    let mut output: Vec<String> = Vec::new();
    let mut blank = true;
    // A comment-only line whose indentation snaps to a block boundary can need
    // the blank lines a dedent gets, which only the next pass sees.
    let mut realigned = false;
    for (index, line) in lines.iter().enumerate() {
        if breaks.contains(&(index + 1)) && !blank {
            output.push(String::new());
            blank = true;
        }
        let parts = &by_line[index + 1];
        if parts.is_empty() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                // A blank line after a comment-only line separates the comment block from
                // what follows (a module header from the first declaration's doc).
                if !blank
                    && lines[..index]
                        .last()
                        .is_some_and(|l| l.trim().starts_with('#'))
                {
                    output.push(String::new());
                    blank = true;
                }
                continue;
            }
            let stripped = line.trim_start_matches(' ');
            let indent = line.len() - stripped.len();
            realigned |= indent % 4 != 0;
            output.push(format!(
                "{}{}",
                " ".repeat(indent / 4 * 4),
                stripped.trim_end_matches([' ', '\t'])
            ));
            blank = false;
            continue;
        }
        let mut formatted = " ".repeat(parts[0].pos.column as usize - 1);
        for (i, t) in parts.iter().enumerate() {
            if i > 0 && token_space(parts, i) {
                formatted.push(' ');
            }
            formatted.push_str(text(t));
        }
        let last = parts[parts.len() - 1];
        let tail = last.pos.column as usize - 1 + text(&last).len();
        if tail < line.len()
            && let Some(comment) = line[tail..].find('#')
        {
            formatted.push_str("  ");
            formatted.push_str(line[tail + comment..].trim_end_matches([' ', '\t']));
        }
        output.push(formatted);
        blank = false;
    }
    while output.last().is_some_and(String::is_empty) {
        output.pop();
    }
    if output.is_empty() {
        return Ok(String::new());
    }
    let result = output.join("\n") + "\n";
    let result = format_expression_layout(file, &result)?;
    parse(file, &result)?;
    if realigned && result != source {
        return format(file, &result);
    }
    Ok(result)
}

fn indent_of(line: &str) -> usize {
    line.len() - line.trim_start_matches(' ').len()
}

/// Re-indents a suite whose header spans several lines and ends on a line
/// indented differently from the statement's first line.
fn align_suite_headers(lines: &[String], tokens: &[Token]) -> Option<Vec<String>> {
    let indent = |line: u32| indent_of(&lines[line as usize - 1]) as i64;
    let mut shift = vec![0i64; lines.len() + 2];
    let mut changed = false;
    let mut depth = 0i64;
    for (i, t) in tokens.iter().enumerate() {
        match t.kind {
            Tok::LParen | Tok::LBracket | Tok::LBrace => depth += 1,
            Tok::RParen | Tok::RBracket | Tok::RBrace => depth -= 1,
            _ => {}
        }
        if t.kind != Tok::Indent
            || depth != 0
            || i < 3
            || tokens[i + 1].kind == Tok::Dedent
            || tokens[i - 1].kind != Tok::Newline
            || tokens[i - 2].kind != Tok::Colon
        {
            continue;
        }
        let mut start = i - 2;
        // A parameter default can contain its own suite. Its layout tokens
        // belong to the enclosing group, not the start of this header.
        let mut groups = 0;
        while start > 0 {
            match tokens[start - 1].kind {
                Tok::RParen | Tok::RBracket | Tok::RBrace => groups += 1,
                Tok::LParen | Tok::LBracket | Tok::LBrace => groups -= 1,
                Tok::Newline | Tok::Indent | Tok::Dedent if groups == 0 => break,
                _ => {}
            }
            start -= 1;
        }
        let (header, first) = (tokens[i - 2].pos.line, tokens[start].pos.line);
        if header == first || header as usize > lines.len() || indent(header) == indent(first) {
            continue;
        }
        let (mut end, mut nesting) = (lines.len(), 0);
        for later in &tokens[i..] {
            if later.kind == Tok::Indent {
                nesting += 1;
            } else if later.kind == Tok::Dedent {
                nesting -= 1;
                if nesting == 0 {
                    end = end.min(later.pos.line as usize - 1);
                    break;
                }
            }
        }
        let delta = indent(first) - indent(header);
        for slot in shift.iter_mut().take(end + 1).skip(header as usize) {
            *slot += delta;
        }
        changed = true;
    }
    if !changed {
        return None;
    }
    Some(
        lines
            .iter()
            .enumerate()
            .map(|(index, line)| {
                let delta = shift[index + 1];
                if delta > 0 && !line.trim().is_empty() {
                    format!("{}{}", " ".repeat(delta as usize), line)
                } else if delta < 0 {
                    line[(-delta as usize).min(indent_of(line))..].to_string()
                } else {
                    line.clone()
                }
            })
            .collect(),
    )
}

/// Reports whether the final `)` closes the parameter list of an `fn`
/// declaration or function type, so a `(` after it opens a parenthesized
/// return type (`fn f() (fn() Int)?`) rather than calling a result.
/// `None` when the matching `(` is not among `tokens` (a line that starts at
/// the `)`).
fn closes_parameter_list(tokens: &[Token]) -> Option<bool> {
    let mut depth = 0usize;
    let mut open = None;
    for (index, token) in tokens.iter().enumerate().rev() {
        match token.kind {
            Tok::RParen => depth += 1,
            Tok::LParen => {
                depth -= 1;
                if depth == 0 {
                    open = Some(index);
                    break;
                }
            }
            _ => {}
        }
    }
    let mut at = open?;
    if at > 0 && tokens[at - 1].kind == Tok::RBracket {
        let mut depth = 0usize;
        while at > 0 {
            at -= 1;
            match tokens[at].kind {
                Tok::RBracket => depth += 1,
                Tok::LBracket => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                _ => {}
            }
        }
    }
    let kind = |back: usize| at.checked_sub(back).map(|i| tokens[i].kind);
    Some(kind(1) == Some(Tok::Fn) || (kind(1) == Some(Tok::Name) && kind(2) == Some(Tok::Fn)))
}

fn token_space(tokens: &[Token], at: usize) -> bool {
    let (current, previous) = (tokens[at].kind, tokens[at - 1].kind);
    if current == Tok::Dot && matches!(previous, Tok::Pipe | Tok::Try) {
        return true;
    }
    if previous == Tok::Bang && current == Tok::Name && tokens[at].lo == tokens[at - 1].hi {
        return false;
    }
    if current == Tok::DotDot || previous == Tok::DotDot {
        return false;
    }
    if matches!(
        current,
        Tok::RParen
            | Tok::RBracket
            | Tok::RBrace
            | Tok::Comma
            | Tok::Dot
            | Tok::Colon
            | Tok::Question
            | Tok::Bang
    ) {
        return false;
    }
    if matches!(
        previous,
        Tok::LParen | Tok::LBracket | Tok::LBrace | Tok::Dot
    ) {
        return false;
    }
    if current == Tok::Assign
        && matches!(
            previous,
            Tok::Plus | Tok::Minus | Tok::Star | Tok::Slash | Tok::Percent
        )
        && tokens[at - 1].end.offset == tokens[at].pos.offset
    {
        // The two tokens of a compound assignment such as +=.
        return false;
    }
    if current == Tok::LParen
        && matches!(previous, Tok::Name | Tok::RParen | Tok::RBracket | Tok::Fn)
    {
        if previous != Tok::RParen {
            return false;
        }
        // Per-line spacing cannot see a `(` on an earlier line; keep the authored gap.
        return closes_parameter_list(&tokens[..at]).unwrap_or(tokens[at].lo != tokens[at - 1].hi);
    }
    if current == Tok::LBracket && matches!(previous, Tok::Name | Tok::SelfKw | Tok::RBracket) {
        return false;
    }
    if previous == Tok::Minus
        && (at == 1
            || matches!(
                tokens[at - 2].kind,
                Tok::Assign
                    | Tok::LParen
                    | Tok::LBracket
                    | Tok::Comma
                    | Tok::Colon
                    | Tok::Return
                    | Tok::Plus
                    | Tok::Minus
                    | Tok::Star
                    | Tok::Slash
                    | Tok::Percent
                    | Tok::Lt
                    | Tok::Gt
                    | Tok::EqEq
                    | Tok::NotEq
                    | Tok::Le
                    | Tok::Ge
            ))
    {
        return false;
    }
    true
}

// ---------------------------------------------------------------------------
// Paragraph breaks

fn paragraph_breaks(module: &Module, lines: &[String]) -> HashSet<usize> {
    struct P<'a> {
        lines: &'a [String],
        breaks: HashSet<usize>,
    }
    impl P<'_> {
        /// Keeps leading comments with the node they describe, ignoring
        /// authored blank lines. Stops at code or a different indentation.
        fn before(&mut self, mut line: usize) {
            let indent = indent_of(&self.lines[line - 1]);
            while line > 1 {
                let previous = &self.lines[line - 2];
                if previous.trim().is_empty() {
                    line -= 1;
                    continue;
                }
                if !previous.trim().starts_with('#') || indent_of(previous) != indent {
                    break;
                }
                line -= 1;
            }
            self.breaks.insert(line);
        }

        fn leading_comment(&self, line: usize) -> bool {
            let indent = indent_of(&self.lines[line - 1]);
            self.lines[..line - 1]
                .iter()
                .rev()
                .find(|l| !l.trim().is_empty())
                .is_some_and(|l| l.trim_start().starts_with('#') && indent_of(l) == indent)
        }
    }
    impl Visitor for P<'_> {
        fn block(&mut self, body: &[Stmt]) {
            for i in 1..body.len() {
                let (previous, current) = (&body[i - 1], &body[i]);
                let line = statement_line(current);
                if statement_line(previous) == line {
                    continue;
                }
                if paragraph_block(previous)
                    || paragraph_block(current)
                    || (guard_statement(previous) && !guard_statement(current))
                    || (!matches!(previous.kind, StmtKind::Bind { .. })
                        && matches!(current.kind, StmtKind::Bind { .. }))
                    || self.leading_comment(line)
                {
                    self.before(line);
                }
            }
        }
    }
    let mut p = P {
        lines,
        breaks: HashSet::new(),
    };
    // Imports may be interleaved with declarations. Separate each import
    // section while keeping consecutive imports, and consecutive constants,
    // together.
    let mut groups: HashMap<usize, &str> = HashMap::new();
    let mut top_level: Vec<usize> = Vec::new();
    for d in &module.decls {
        let line = match &d.kind {
            DeclKind::Const(c) => c.group.unwrap_or(d.pos).line as usize,
            _ => d.pos.line as usize,
        };
        top_level.push(line);
        if matches!(d.kind, DeclKind::Const(_)) {
            groups.insert(line, "constant");
        }
    }
    for item in &module.imports {
        let line = item.pos.line as usize;
        if !groups.contains_key(&line) {
            top_level.push(line);
        }
        groups.insert(line, "import");
    }
    top_level.sort_unstable();
    for i in 1..top_level.len() {
        let (a, b) = (groups.get(&top_level[i - 1]), groups.get(&top_level[i]));
        if a.is_none() || a != b {
            p.before(top_level[i]);
        }
    }
    for d in &module.decls {
        // Implementation bodies are separate reading units. Interface
        // signatures remain a compact list of the contract's operations.
        if let DeclKind::Impl(i) = &d.kind {
            for method in i.methods.iter().skip(1) {
                p.before(method.pos.line as usize);
            }
        }
        visit::walk_decl(&mut p, d);
    }
    p.breaks
}

/// The line a binding starts on; a binding in a `let (...)` group starts on
/// the group's keyword line so the group moves as one unit.
fn statement_line(s: &Stmt) -> usize {
    match &s.kind {
        StmtKind::Bind { group: Some(g), .. } => g.line as usize,
        _ => s.pos.line as usize,
    }
}

fn guard_statement(s: &Stmt) -> bool {
    match &s.kind {
        StmtKind::If {
            body, else_body, ..
        } if else_body.is_empty() && body.len() == 1 => {
            matches!(
                body[0].kind,
                StmtKind::Return(_) | StmtKind::Break | StmtKind::Continue
            )
        }
        _ => false,
    }
}

/// The statement's value expression.
fn statement_value(s: &Stmt) -> Option<&Expr> {
    match &s.kind {
        StmtKind::Bind { value, .. } | StmtKind::Assign { value, .. } => Some(value),
        StmtKind::Call(e) => Some(e),
        StmtKind::Return(e) => e.as_ref(),
        StmtKind::If { cond, .. } | StmtKind::While { cond, .. } => Some(cond),
        StmtKind::For { iter, .. } => Some(iter),
        StmtKind::Break | StmtKind::Continue => None,
    }
}

fn paragraph_block(s: &Stmt) -> bool {
    // Single-step blocks belong to the surrounding cluster. Count syntax,
    // rather than source lines, so wrapping a header cannot add paragraphs on
    // the next formatting pass.
    if let Some(mut value) = statement_value(s) {
        while let ExprKind::Unary { operand, .. } = &value.kind {
            value = operand;
        }
        if matches!(value.kind, ExprKind::Match { .. })
            || block_lambda(value)
            || matches!(&value.kind, ExprKind::Call { args, .. } if args.iter().any(|a| block_lambda(&a.value)))
        {
            return true;
        }
    }
    match &s.kind {
        StmtKind::If {
            body, else_body, ..
        } => {
            !guard_statement(s)
                && (body.len() > 1
                    || !else_body.is_empty()
                    || (body.len() == 1 && paragraph_block(&body[0])))
        }
        StmtKind::While { body, .. } | StmtKind::For { body, .. } => {
            body.len() > 1 || (body.len() == 1 && paragraph_block(&body[0]))
        }
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Expression layout

#[derive(Copy, Clone)]
struct Node {
    tok: Token,
    group: Option<usize>,
    space: bool,
}

struct Group {
    open: Token,
    close: Token,
    nodes: Vec<Node>,
    force: bool,
    parameters: bool,
    items: bool,
    list: bool,
}

struct Layout<'a> {
    src: &'a str,
    lines: Vec<&'a str>,
    groups: Vec<Group>,
    by_open: HashMap<u32, usize>,
    by_item: HashMap<u32, usize>,
}

fn layout_token(kind: Tok) -> bool {
    kind.is_layout()
}

fn format_expression_layout(file: &Arc<str>, source: &str) -> PResult<String> {
    let source = group_statement_expressions(file, source, true)?;
    let mut source = group_statement_expressions(file, &source, false)?;
    let mut module = parse(file, &source)?;
    let mut tokens = lex(file, &source)?.tokens;
    if let Some(compact) = compact_callback_suites(&module, &tokens, &source) {
        source = compact;
        module = parse(file, &source)?;
        tokens = lex(file, &source)?.tokens;
    }
    let mut layout = Layout {
        src: &source,
        lines: source.split('\n').collect(),
        groups: Vec::new(),
        by_open: HashMap::new(),
        by_item: HashMap::new(),
    };
    let with_comments = layout.layout_tokens(&tokens);
    let nodes = layout.tree(&with_comments);
    struct Flags<'a, 'b>(&'b mut Layout<'a>);
    impl Visitor for Flags<'_, '_> {
        fn expr(&mut self, e: &Expr) {
            match &e.kind {
                ExprKind::Call { args, .. } => {
                    let Some(first) = args.first() else { return };
                    // Interpolation is part of one atomic string token.
                    let Some(&g) = self.0.by_item.get(&first.pos.offset) else {
                        return;
                    };
                    self.0.groups[g].items = true;
                    if args.iter().any(|a| block_lambda(&a.value)) {
                        self.0.groups[g].force = true;
                    }
                }
                ExprKind::List(_) => {
                    if let Some(&g) = self.0.by_open.get(&e.pos.offset) {
                        self.0.groups[g].list = true;
                    }
                }
                ExprKind::Lambda(l) => self.0.parameters(&l.params),
                _ => {}
            }
        }
    }
    for d in &module.decls {
        layout.declaration(d);
        visit::walk_decl(&mut Flags(&mut layout), d);
    }
    let mut output = String::new();
    let mut offset = 0usize;
    for (index, node) in nodes.iter().enumerate() {
        let Some(gid) = node.group else { continue };
        let g = &layout.groups[gid];
        output.push_str(&source[offset..g.open.lo as usize]);
        let line = output.rsplit('\n').next().unwrap_or("");
        let indent = indent_of(line);
        let column = line.chars().count();
        // Only a method call in a chain counts what follows it; other groups
        // (type arguments, clause patterns) keep their own line.
        let chained = g.open.kind == Tok::LParen
            && index >= 2
            && nodes[index - 1].tok.kind == Tok::Name
            && nodes[index - 2].tok.kind == Tok::Dot;
        let following = if chained {
            layout.following_width(&nodes[index + 1..], true)
        } else {
            0
        };
        layout.group(gid, indent, column, following, &mut output);
        offset = g.close.hi as usize;
    }
    output.push_str(&source[offset..]);
    Ok(output)
}

/// Joining an explicit return to its callback header preserves its meaning.
/// A bare call cannot be joined: an inline body would implicitly return it.
fn compact_callback_suites(module: &Module, tokens: &[Token], source: &str) -> Option<String> {
    struct Compact<'a> {
        tokens: &'a [Token],
        source: &'a str,
        cuts: Vec<(usize, usize)>,
        suites: HashSet<NodeId>,
        stack: Vec<bool>,
    }
    impl Visitor for Compact<'_> {
        fn expr(&mut self, e: &Expr) {
            self.stack.push(matches!(
                e.kind,
                ExprKind::Lambda(_) | ExprKind::Match { .. }
            ));
        }

        fn leave_expr(&mut self, e: &Expr) {
            if self.stack.pop().unwrap() {
                self.suites.insert(e.id);
                if let Some(parent) = self.stack.last_mut() {
                    *parent = true;
                }
            }
            let ExprKind::Call { args, .. } = &e.kind else {
                return;
            };
            for arg in args {
                let ExprKind::Lambda(l) = &arg.value.kind else {
                    continue;
                };
                let [body] = l.body.as_slice() else { continue };
                let StmtKind::Return(Some(value)) = &body.kind else {
                    continue;
                };
                // Nested suites retain indentation relative to this body.
                if self.suites.contains(&value.id) {
                    continue;
                }
                let start = self
                    .tokens
                    .partition_point(|t| t.pos.offset < body.pos.offset);
                let Some(colon) = self.tokens[..start]
                    .iter()
                    .rev()
                    .find(|t| !layout_token(t.kind))
                else {
                    continue;
                };
                let (from, to) = (colon.hi as usize, body.pos.offset as usize);
                // Interpolated expressions keep offsets local to their text, so the
                // range can be reversed or off a boundary.
                let Some(gap) = self.source.get(from..to) else {
                    continue;
                };
                if colon.kind == Tok::Colon
                    && gap.contains('\n')
                    && gap.chars().all(char::is_whitespace)
                {
                    self.cuts.push((from, to));
                }
            }
        }
    }
    let mut compact = Compact {
        tokens,
        source,
        cuts: Vec::new(),
        suites: HashSet::new(),
        stack: Vec::new(),
    };
    for d in &module.decls {
        visit::walk_decl(&mut compact, d);
    }
    if compact.cuts.is_empty() {
        return None;
    }
    compact.cuts.sort_unstable_by(|a, b| b.cmp(a));
    compact.cuts.dedup();
    Some(apply_edits(
        source,
        compact.cuts.iter().rev().map(|&(from, to)| (from, to, " ")),
    ))
}

/// A lambda whose body is a suite of several statements; a one-expression
/// lambda stays inline when the call fits the line.
fn block_lambda(e: &Expr) -> bool {
    matches!(&e.kind, ExprKind::Lambda(l) if l.body.len() > 1)
}

fn suite_expression(mut e: &Expr) -> bool {
    while let ExprKind::Unary { operand, .. } = &e.kind {
        e = operand;
    }
    matches!(e.kind, ExprKind::Lambda(_) | ExprKind::Match { .. })
}

fn is_arith(k: Tok) -> bool {
    matches!(
        k,
        Tok::Plus | Tok::Minus | Tok::Star | Tok::Slash | Tok::Percent
    )
}

fn is_open(k: Tok) -> bool {
    matches!(k, Tok::LParen | Tok::LBracket | Tok::LBrace)
}

impl<'a> Layout<'a> {
    fn text(&self, t: &Token) -> &'a str {
        let src: &'a str = self.src;
        &src[t.lo as usize..t.hi as usize]
    }

    fn parameters(&mut self, params: &[Param]) {
        if let Some(first) = params.first()
            && let Some(&g) = self.by_item.get(&first.pos.offset)
        {
            self.groups[g].parameters = true;
            self.groups[g].items = true;
        }
        for p in params {
            self.typ(p.ty.as_ref());
        }
    }

    fn typ(&mut self, t: Option<&TypeRef>) {
        let Some(t) = t else { return };
        match &t.kind {
            TypeKind::Named { args, .. } => args.iter().for_each(|a| self.typ(Some(a))),
            TypeKind::Fn { params, result } => {
                self.parameters(params);
                self.typ(Some(result));
            }
        }
    }

    fn declaration(&mut self, d: &Decl) {
        match &d.kind {
            DeclKind::Fn(f) => self.func(f),
            DeclKind::Record(r) => r.fields.iter().for_each(|f| self.typ(f.ty.as_ref())),
            DeclKind::Alternative(a) => a.cases.iter().for_each(|c| self.parameters(&c.fields)),
            DeclKind::Interface(i) => i.methods.iter().for_each(|m| self.func(&m.func)),
            DeclKind::Impl(i) => i.methods.iter().for_each(|m| self.func(&m.func)),
            DeclKind::Const(_) | DeclKind::Test(_) => {}
        }
    }

    fn func(&mut self, f: &Func) {
        self.parameters(&f.params);
        self.typ(Some(&f.result));
    }

    /// Recovers comment trivia only outside lexer tokens, so `#` and
    /// interpolation inside strings never become formatter instructions.
    fn layout_tokens(&self, tokens: &[Token]) -> Vec<Token> {
        let mut last: HashMap<u32, usize> = HashMap::new();
        for t in tokens {
            if !layout_token(t.kind) {
                last.insert(
                    t.pos.line,
                    t.pos.column as usize - 1 + (t.hi - t.lo) as usize,
                );
            }
        }
        let mut comments: Vec<Token> = Vec::new();
        let mut offset = 0usize;
        for (index, line) in self.lines.iter().enumerate() {
            let tail = last.get(&(index as u32 + 1)).copied().unwrap_or(0);
            if let Some(at) = line[tail..].find('#') {
                let column = tail + at;
                let text = line[column..].trim_end_matches([' ', '\t']);
                let pos = Pos::new(
                    (offset + column) as u32,
                    index as u32 + 1,
                    column as u32 + 1,
                );
                comments.push(Token {
                    kind: Tok::Comment,
                    pos,
                    end: pos,
                    lo: (offset + column) as u32,
                    hi: (offset + column + text.len()) as u32,
                });
            }
            offset += line.len() + 1;
        }
        let mut result = Vec::with_capacity(tokens.len() + comments.len());
        let mut comment = 0;
        for t in tokens {
            while comment < comments.len() && comments[comment].pos.offset <= t.pos.offset {
                result.push(comments[comment]);
                comment += 1;
            }
            result.push(*t);
        }
        result
    }

    fn tree(&mut self, tokens: &[Token]) -> Vec<Node> {
        let mut at = 0;
        let mut code: Vec<Token> = Vec::new();
        self.sequence_tree(tokens, &mut at, &mut code, None)
    }

    fn sequence_tree(
        &mut self,
        tokens: &[Token],
        at: &mut usize,
        code: &mut Vec<Token>,
        close: Option<Tok>,
    ) -> Vec<Node> {
        let mut nodes = Vec::new();
        while *at < tokens.len() && Some(tokens[*at].kind) != close {
            let token = tokens[*at];
            *at += 1;
            let mut node = Node {
                tok: token,
                group: None,
                space: false,
            };
            if !layout_token(token.kind) && token.kind != Tok::Comment {
                code.push(token);
                node.space = code.len() > 1 && token_space(code, code.len() - 1);
            }
            let end = match token.kind {
                Tok::LParen => Some(Tok::RParen),
                Tok::LBracket => Some(Tok::RBracket),
                Tok::LBrace => Some(Tok::RBrace),
                _ => None,
            };
            if let Some(end) = end {
                let mut items = token.kind != Tok::LParen;
                if code.len() > 1
                    && matches!(
                        code[code.len() - 2].kind,
                        Tok::Name | Tok::RParen | Tok::RBracket | Tok::Fn
                    )
                {
                    items = true;
                }
                let children = self.sequence_tree(tokens, at, code, Some(end));
                let close_token = tokens[*at];
                code.push(close_token);
                *at += 1;
                // Only a nested suite keeps a group multi-line; authored line
                // breaks otherwise collapse when the group fits.
                let force = children.iter().any(|c| c.tok.kind == Tok::Newline);
                let gid = self.groups.len();
                self.by_open.insert(token.pos.offset, gid);
                if let Some(child) = children
                    .iter()
                    .find(|c| !layout_token(c.tok.kind) && c.tok.kind != Tok::Comment)
                {
                    self.by_item.insert(child.tok.pos.offset, gid);
                }
                self.groups.push(Group {
                    open: token,
                    close: close_token,
                    nodes: children,
                    force,
                    parameters: false,
                    items,
                    list: false,
                });
                node.group = Some(gid);
            }
            nodes.push(node);
        }
        nodes
    }

    fn flat(&self, nodes: &[Node]) -> String {
        let mut out = String::new();
        for node in nodes {
            if layout_token(node.tok.kind) || node.tok.kind == Tok::Comment {
                continue;
            }
            if !out.is_empty() && node.space {
                out.push(' ');
            }
            match node.group {
                Some(g) => {
                    let g = &self.groups[g];
                    out.push_str(self.text(&g.open));
                    out.push_str(&self.flat(&g.nodes));
                    out.push_str(self.text(&g.close));
                }
                None => out.push_str(self.text(&node.tok)),
            }
        }
        out
    }

    // Append descendants to the caller's buffer so each enclosing group does
    // not copy its child's complete, increasingly indented output.
    fn group(&self, gid: usize, indent: usize, column: usize, following: usize, out: &mut String) {
        let g = &self.groups[gid];
        let nodes = trim_trailing_comma(self, &g.nodes);
        let flat = format!(
            "{}{}{}",
            self.text(&g.open),
            self.flat(nodes),
            self.text(&g.close)
        );
        let mut suffix = following;
        if g.parameters {
            let line = self.lines[g.close.pos.line as usize - 1];
            let tail =
                &line[g.close.pos.column as usize - 1 + (g.close.hi - g.close.lo) as usize..];
            // A callback body and enclosing arguments do not belong to its
            // signature, and neither do sibling parameters after a
            // function-typed parameter.
            suffix = signature_tail(tail).chars().count();
        }
        let mut force = g.force || column + flat.chars().count() + suffix > WIDTH;
        let (mut operator, count) = self.layout_operators(nodes);
        if g.items || (operator == Some(Tok::Dot) && count < 2) {
            operator = None;
        }
        if operator.is_some_and(is_comparison) {
            operator = None; // Keep each comparison together as one operand.
        }
        force = force || nodes.iter().any(|n| n.tok.kind == Tok::Comment);
        let mut parts = split_layout(nodes, Tok::Comma);
        if parts.is_empty() {
            out.push_str(&flat);
            return;
        }
        let comma_separated = parts.len() > 1;
        if !force {
            // A child's complexity or width can expand the containing argument.
            let mut trial = String::new();
            self.sequence(
                nodes,
                indent,
                column + (g.open.hi - g.open.lo) as usize,
                false,
                &mut trial,
            );
            if !trial.contains('\n') {
                out.push_str(self.text(&g.open));
                out.push_str(&trial);
                out.push_str(self.text(&g.close));
                return;
            }
            force = true;
        }
        if force
            && parts.len() == 1
            && let Some(op) = operator
        {
            parts = split_layout(nodes, op);
        }
        if g.list && !g.force && simple_layout_items(&parts) {
            out.push_str(&self.packed(g, &parts, indent));
            return;
        }
        if g.items
            && !g.parameters
            && !g.force
            && comma_separated
            && parts.len() > 1
            && let Some(packed) = self.packed_arguments(g, &parts, indent)
        {
            out.push_str(&packed);
            return;
        }
        // Keep an opener's trailing comment on its original line.
        out.push_str(self.text(&g.open));
        if !nodes.is_empty()
            && nodes[0].tok.kind == Tok::Comment
            && nodes[0].tok.pos.line == g.open.pos.line
        {
            out.push_str("  ");
            out.push_str(self.text(&nodes[0].tok));
            let remaining = &nodes[1..];
            parts = split_layout(remaining, Tok::Comma);
            if parts.len() == 1
                && let Some(op) = operator
            {
                parts = split_layout(remaining, op);
            }
        }
        for part in &parts {
            let start = out.len();
            out.push('\n');
            self.item(part, indent + 4, out);
            if out.len() == start + 1 {
                out.truncate(start);
            }
        }
        out.push('\n');
        out.push_str(&" ".repeat(indent));
        out.push_str(self.text(&g.close));
    }

    /// An item's enclosing delimiters already allow continuation lines. Break
    /// its operators directly rather than inserting another pair of parentheses.
    fn item(&self, nodes: &[Node], indent: usize, out: &mut String) {
        let (operator, count) = self.layout_operators(nodes);
        let Some(operator) = operator else {
            self.sequence(nodes, indent, indent, true, out);
            return;
        };
        let mut text = String::new();
        self.sequence(nodes, indent, indent, true, &mut text);
        let long = text.split('\n').any(|l| l.chars().count() > WIDTH);
        if !long || (operator == Tok::Dot && count < 2) || is_comparison(operator) {
            out.push_str(&text); // Keep comparison operands together.
            return;
        }
        for (index, part) in split_layout(nodes, operator).iter().enumerate() {
            if index > 0 {
                out.push('\n');
            }
            self.sequence(part, indent, indent, true, out);
        }
    }

    fn layout_operators(&self, nodes: &[Node]) -> (Option<Tok>, usize) {
        let (mut selected, mut level, mut count) = (None, 7, 0);
        for (index, node) in nodes.iter().enumerate() {
            if node.tok.kind == Tok::Newline || node.tok.kind == Tok::Fn {
                return (None, 0); // Operators here belong to a callable body or type.
            }
            if node.group.is_some() {
                continue;
            }
            let p = match node.tok.kind {
                Tok::Or => 1,
                Tok::And => 2,
                Tok::EqEq | Tok::NotEq | Tok::Lt | Tok::Gt | Tok::Le | Tok::Ge => 3,
                Tok::Plus | Tok::Minus => 4,
                Tok::Star | Tok::Slash | Tok::Percent => 5,
                Tok::Dot if !optional_dot(nodes, index) => 6,
                _ => continue,
            };
            if p < level {
                (selected, level, count) = (Some(node.tok.kind), p, 1);
            } else if p == level {
                count += 1;
            }
        }
        (selected, count)
    }

    /// Fills call arguments or list elements line by line when every one prints
    /// on a single line; any argument that must itself break keeps one per line.
    fn packed_arguments(&self, g: &Group, parts: &[&[Node]], indent: usize) -> Option<String> {
        let mut texts = Vec::with_capacity(parts.len());
        for part in parts {
            if part.iter().any(|n| n.tok.kind == Tok::Comment) {
                return None;
            }
            let mut text = String::new();
            self.item(part, indent + 4, &mut text);
            if text.is_empty() || text.contains('\n') {
                return None;
            }
            texts.push(text);
        }
        let mut out = String::from(self.text(&g.open));
        let mut column = 0usize;
        for text in &texts {
            let width = text.trim_start().chars().count();
            if column == 0 || column + 1 + width > WIDTH {
                out.push('\n');
                out.push_str(&" ".repeat(indent + 4));
                column = indent + 4;
            } else {
                out.push(' ');
                column += 1;
            }
            out.push_str(text.trim_start());
            column += width;
        }
        out.push('\n');
        out.push_str(&" ".repeat(indent));
        out.push_str(self.text(&g.close));
        Some(out)
    }

    fn packed(&self, g: &Group, parts: &[&[Node]], indent: usize) -> String {
        let padding = " ".repeat(indent + 4);
        let mut out = String::from(self.text(&g.open));
        let mut column = 0usize;
        for part in parts {
            let text = self.flat(part);
            let width = text.chars().count();
            if column == 0 || column + 1 + width > WIDTH {
                out.push('\n');
                out.push_str(&padding);
                column = indent + 4;
            } else {
                out.push(' ');
                column += 1;
            }
            out.push_str(&text);
            column += width;
        }
        out.push('\n');
        out.push_str(&" ".repeat(indent));
        out.push_str(self.text(&g.close));
        out
    }

    fn line_indent(&self, line: u32) -> usize {
        indent_of(self.lines[line as usize - 1])
    }

    /// Width of the text after a group on its line, up to the next group that
    /// has its own continuation boundary: its contents must not force this
    /// group (such as a list before a map callback) to expand as well.
    fn following_width(&self, rest: &[Node], clause: bool) -> usize {
        let mut tail: Vec<Node> = Vec::new();
        for next in rest {
            if matches!(next.tok.kind, Tok::Newline | Tok::Comment)
                || (clause && next.tok.kind == Tok::Colon)
            {
                break;
            }
            let mut next = *next;
            if let Some(ng) = next.group
                && !self.groups[ng].nodes.is_empty()
                && !(clause && self.groups[ng].nodes.len() <= 2)
            {
                next.group = None;
                tail.push(next);
                break;
            }
            tail.push(next);
        }
        let mut following = self.flat(&tail).chars().count();
        if tail.first().is_some_and(|t| t.space) {
            following += 1;
        }
        following
    }

    fn sequence(
        &self,
        nodes: &[Node],
        indent: usize,
        column: usize,
        prefix: bool,
        out: &mut String,
    ) {
        struct W<'a> {
            out: &'a mut String,
            start: usize,
            column: usize,
            line_indent: usize,
        }
        impl W<'_> {
            fn write(&mut self, text: &str) {
                let start = self.out.len();
                self.out.push_str(text);
                self.measure_from(start);
            }

            fn measure_from(&mut self, start: usize) {
                let text = &self.out[start..];
                if let Some(at) = text.rfind('\n') {
                    let tail = &text[at + 1..];
                    self.column = tail.chars().count();
                    self.line_indent = indent_of(tail);
                } else {
                    self.column += text.chars().count();
                }
            }

            fn is_empty(&self) -> bool {
                self.out.len() == self.start
            }
        }
        let mut w = W {
            start: out.len(),
            out,
            column,
            line_indent: indent,
        };
        let mut first_indent = 0i64;
        for node in nodes {
            // A leading comment may sit off the code's indentation.
            if !layout_token(node.tok.kind) && node.tok.kind != Tok::Comment {
                first_indent = self.line_indent(node.tok.pos.line) as i64;
                break;
            }
        }
        let (mut pending, mut suite, mut last_line) = (false, false, 0u32);
        for (index, node) in nodes.iter().enumerate() {
            if layout_token(node.tok.kind) {
                pending = pending || node.tok.kind == Tok::Newline;
                suite = suite || node.tok.kind == Tok::Newline;
                continue;
            }
            let comment = node.tok.kind == Tok::Comment;
            if comment && last_line != node.tok.pos.line && !w.is_empty() {
                pending = true;
            }
            if !w.is_empty()
                && !pending
                && !suite
                && last_line != 0
                && last_line != node.tok.pos.line
            {
                // An original line break joins this line to the output line. A
                // suite opened here is indented relative to the line that
                // holds its header.
                first_indent = self.line_indent(node.tok.pos.line) as i64;
            }
            if w.is_empty() || pending {
                if !w.is_empty() {
                    w.write("\n");
                    for line in last_line + 1..node.tok.pos.line {
                        if self.lines[line as usize - 1].trim().is_empty() {
                            w.write("\n");
                            break;
                        }
                    }
                }
                w.line_indent = indent;
                if suite {
                    w.line_indent = (indent as i64 + self.line_indent(node.tok.pos.line) as i64
                        - first_indent)
                        .max(0) as usize;
                }
                if prefix || !w.is_empty() {
                    let pad = " ".repeat(w.line_indent);
                    w.write(&pad);
                }
            } else if comment {
                w.write("  ");
            } else if node.space {
                w.write(" ");
            }
            if let Some(gid) = node.group {
                let following = self.following_width(&nodes[index + 1..], false);
                let start = w.out.len();
                self.group(gid, w.line_indent, w.column, following, w.out);
                w.measure_from(start);
                last_line = self.groups[gid].close.pos.line;
            } else {
                w.write(self.text(&node.tok));
                last_line = node.tok.pos.line;
            }
            pending = comment;
        }
    }
}

fn is_comparison(k: Tok) -> bool {
    matches!(
        k,
        Tok::EqEq | Tok::NotEq | Tok::Lt | Tok::Gt | Tok::Le | Tok::Ge
    )
}

/// The `.` of `?.`: a line cannot start with `?.`, so a chain never breaks there.
fn optional_dot(nodes: &[Node], index: usize) -> bool {
    nodes[index].tok.kind == Tok::Dot && index > 0 && nodes[index - 1].tok.kind == Tok::Question
}

fn split_layout(nodes: &[Node], separator: Tok) -> Vec<&[Node]> {
    let mut parts = Vec::new();
    let mut start = 0;
    for (i, node) in nodes.iter().enumerate() {
        let k = node.tok.kind;
        let matches = match separator {
            Tok::Plus | Tok::Minus => matches!(k, Tok::Plus | Tok::Minus),
            Tok::Star | Tok::Slash | Tok::Percent => {
                matches!(k, Tok::Star | Tok::Slash | Tok::Percent)
            }
            _ => k == separator,
        };
        if node.group.is_some() || !matches || optional_dot(nodes, i) {
            continue;
        }
        let mut end = i;
        if separator == Tok::Comma {
            end += 1;
            // A trailing comment explains the item before this comma.
            while end < nodes.len()
                && nodes[end].tok.kind == Tok::Comment
                && nodes[end].tok.pos.line == node.tok.pos.line
            {
                end += 1;
            }
        }
        if end > start {
            parts.push(&nodes[start..end]);
        }
        start = end;
    }
    if start < nodes.len() {
        parts.push(&nodes[start..]);
    }
    parts
}

/// Pack atomic list values into rows using their printed width.
fn simple_layout_items(parts: &[&[Node]]) -> bool {
    for part in parts {
        let mut values = 0;
        for node in *part {
            if layout_token(node.tok.kind) || node.tok.kind == Tok::Comma {
                continue;
            }
            if node.group.is_some() || node.tok.kind == Tok::Comment {
                return false;
            }
            values += 1;
        }
        if values != 1 {
            return false;
        }
    }
    parts.len() > 1
}

/// The part of a source line after a parameter list that belongs to the same
/// signature: the return type, up to the suite colon, or up to the comma or
/// closing delimiter that ends an enclosing parameter.
fn signature_tail(tail: &str) -> &str {
    let mut depth = 0;
    for (i, b) in tail.bytes().enumerate() {
        match b {
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => {
                if depth == 0 {
                    return &tail[..i];
                }
                depth -= 1;
            }
            b':' | b',' if depth == 0 => {
                return &tail[..i];
            }
            _ => {}
        }
    }
    tail
}

/// Drops an authored trailing comma when the group has no comments or suites,
/// so a group that collapses onto one line reads cleanly.
fn trim_trailing_comma<'n>(_: &Layout, nodes: &'n [Node]) -> &'n [Node] {
    let mut last = nodes.len() as isize - 1;
    while last >= 0 && layout_token(nodes[last as usize].tok.kind) {
        last -= 1;
    }
    if last < 0
        || nodes[last as usize].group.is_some()
        || nodes[last as usize].tok.kind != Tok::Comma
    {
        return nodes;
    }
    if nodes.iter().any(|n| n.tok.kind == Tok::Comment) {
        return nodes;
    }
    &nodes[..last as usize]
}

// ---------------------------------------------------------------------------
// Statement grouping

/// Ordinary newlines cannot split ungrouped expressions. Adds grouping only
/// around a statement's complete value, retaining its precedence and inline suite.
fn group_statement_expressions(file: &Arc<str>, source: &str, strip: bool) -> PResult<String> {
    let module = parse(file, source)?;
    let lexed = lex(file, source)?;
    let tokens = &lexed.tokens;
    let mut starts: HashMap<u32, usize> = HashMap::new();
    let mut pairs: HashMap<usize, usize> = HashMap::new();
    let mut stack: Vec<usize> = Vec::new();
    for (i, t) in tokens.iter().enumerate() {
        starts.insert(t.pos.offset, i);
        match t.kind {
            k if is_open(k) => stack.push(i),
            Tok::RParen | Tok::RBracket | Tok::RBrace => {
                if let Some(open) = stack.pop() {
                    pairs.insert(open, i);
                }
            }
            _ => {}
        }
    }
    struct G<'a> {
        tokens: &'a [Token],
        source: &'a str,
        starts: HashMap<u32, usize>,
        pairs: HashMap<usize, usize>,
        insert: HashMap<usize, String>,
        remove: Vec<(usize, usize, String)>,
        strip: bool,
    }
    impl G<'_> {
        /// Parentheses around a whole method chain only add a line; the
        /// layout pass restores them when the chain cannot hug its last call.
        fn unwrap_chain(&mut self, start: usize) {
            let tokens = self.tokens;
            let Some(&close) = self.pairs.get(&start) else {
                return;
            };
            if tokens[start].kind != Tok::LParen {
                return;
            }
            let before = start.checked_sub(1).map(|i| tokens[i].kind);
            if !matches!(
                before,
                None | Some(Tok::Assign | Tok::Return | Tok::Newline | Tok::Indent | Tok::Dedent)
            ) {
                return;
            }
            let after = tokens.get(close + 1).map(|t| t.kind);
            if !matches!(
                after,
                None | Some(Tok::Newline | Tok::Dedent | Tok::Colon | Tok::Eof)
            ) {
                return;
            }
            let (mut depth, mut dots) = (0, 0);
            for t in &tokens[start + 1..close] {
                match t.kind {
                    k if is_open(k) => depth += 1,
                    Tok::RParen | Tok::RBracket | Tok::RBrace => depth -= 1,
                    Tok::Dot if depth == 0 => dots += 1,
                    Tok::Newline | Tok::Indent | Tok::Dedent | Tok::Fn => return,
                    Tok::If | Tok::Else => return,
                    k if depth == 0
                        && (matches!(k, Tok::And | Tok::Or) || is_comparison(k) || is_arith(k)) =>
                    {
                        return;
                    }
                    _ => {}
                }
            }
            let inner = &self.source[tokens[start].hi as usize..tokens[close].lo as usize];
            if dots >= 1 && !inner.contains('#') && tokens[start + 1].kind != Tok::Dot {
                let mut flat = String::new();
                let mut code: Vec<Token> = Vec::new();
                for t in &tokens[start + 1..close] {
                    code.push(*t);
                    if code.len() > 1 && token_space(&code, code.len() - 1) {
                        flat.push(' ');
                    }
                    flat.push_str(&self.source[t.lo as usize..t.hi as usize]);
                }
                self.remove
                    .push((tokens[start].lo as usize, tokens[close].hi as usize, flat));
            }
        }

        fn wrap(&mut self, start: usize) {
            if self.strip {
                return;
            }
            let tokens = self.tokens;
            let (mut end, mut booleans, mut dots, mut operators) = (start, 0, 0, 0);
            let mut calls: Vec<(usize, usize)> = Vec::new();
            while end < tokens.len() {
                if let Some(&close) = self.pairs.get(&end) {
                    // A call with a trivial argument gains nothing from breaking.
                    if tokens[end].kind == Tok::LParen && close > end + 3 {
                        calls.push((end, close));
                    }
                    end = close + 1;
                    continue;
                }
                let kind = tokens[end].kind;
                if layout_token(kind)
                    || matches!(
                        kind,
                        Tok::Colon | Tok::Comma | Tok::RParen | Tok::RBracket | Tok::RBrace
                    )
                {
                    break;
                }
                match kind {
                    Tok::And | Tok::Or => booleans += 1,
                    Tok::Dot => dots += 1,
                    Tok::Plus | Tok::Minus | Tok::Star | Tok::Slash | Tok::Percent => {
                        operators += 1
                    }
                    k if is_comparison(k) => operators += 1,
                    _ => {}
                }
                end += 1;
            }
            if end == start {
                return;
            }
            let from = tokens[start].lo as usize;
            let to = tokens[end - 1].hi as usize;
            let mut flat = String::new();
            let mut code: Vec<Token> = Vec::new();
            for t in &tokens[start..end] {
                if layout_token(t.kind) {
                    continue;
                }
                code.push(*t);
                if code.len() > 1 && token_space(&code, code.len() - 1) {
                    flat.push(' ');
                }
                flat.push_str(&self.source[t.lo as usize..t.hi as usize]);
            }
            let column = tokens[start].pos.column as usize - 1;
            let mut width = column + flat.chars().count();
            if end < tokens.len() && tokens[end].kind == Tok::Colon {
                width += 1; // The condition's suite colon occupies a column too.
            }
            // A chain breaks inside a call whose opening parenthesis still fits
            // on the first line, rather than wrapping the whole chain.
            let hugs = booleans + operators == 0
                && calls.iter().any(|&(open, _)| {
                    let mut head = column;
                    let mut code: Vec<Token> = Vec::new();
                    for t in &tokens[start..=open] {
                        if layout_token(t.kind) {
                            continue;
                        }
                        code.push(*t);
                        if code.len() > 1 && token_space(&code, code.len() - 1) {
                            head += 1;
                        }
                        head += (t.hi - t.lo) as usize;
                    }
                    head <= WIDTH
                });
            if width > WIDTH && !hugs && (booleans + operators > 0 || dots >= 2) {
                self.insert.entry(from).or_default().push('(');
                self.insert.entry(to).or_default().insert(0, ')');
            }
        }
    }
    impl Visitor for G<'_> {
        fn stmt(&mut self, s: &Stmt) {
            let Some(value) = statement_value(s) else {
                return;
            };
            if suite_expression(value) {
                return;
            }
            let Some(&start) = self.starts.get(&s.pos.offset) else {
                return;
            };
            let tokens = self.tokens;
            if matches!(tokens[start].kind, Tok::String | Tok::Fn) {
                return;
            }
            let mut start = start;
            match &s.kind {
                StmtKind::If { binding, .. } => {
                    start += 1;
                    if binding.is_some() {
                        // `if let name = value:` wraps only the value.
                        while tokens[start].kind != Tok::Assign {
                            start += 1;
                        }
                        start += 1;
                    }
                }
                StmtKind::While { .. } => start += 1,
                StmtKind::Return(_) => {
                    if tokens[start].kind == Tok::Return {
                        start += 1;
                    }
                }
                StmtKind::Bind { .. } | StmtKind::Assign { .. } | StmtKind::For { .. } => {
                    let target = if matches!(s.kind, StmtKind::For { .. }) {
                        Tok::In
                    } else {
                        Tok::Assign
                    };
                    while tokens[start].kind != target {
                        if let Some(&end) = self.pairs.get(&start) {
                            start = end;
                        }
                        start += 1;
                    }
                    start += 1;
                }
                _ => {}
            }
            self.wrap(start);
        }
    }
    let mut g = G {
        tokens,
        source,
        starts,
        pairs,
        insert: HashMap::new(),
        remove: Vec::new(),
        strip,
    };
    if strip {
        for start in 0..tokens.len() {
            g.unwrap_chain(start);
        }
    }
    for d in &module.decls {
        // A constant's synthetic statement starts at its initializer, which
        // may be text, so it bypasses the keyword and text-statement handling.
        if let DeclKind::Const(c) = &d.kind
            && !suite_expression(&c.value)
            && let Some(&start) = g.starts.get(&c.init_pos.offset)
        {
            g.wrap(start);
        }
        visit::walk_decl(&mut g, d);
    }
    if strip {
        g.remove.sort_unstable();
        return Ok(apply_edits(
            source,
            g.remove
                .iter()
                .map(|(from, to, flat)| (*from, *to, flat.as_str())),
        ));
    }
    let mut offsets: Vec<usize> = g.insert.keys().copied().collect();
    offsets.sort_unstable();
    Ok(apply_edits(
        source,
        offsets
            .into_iter()
            .map(|offset| (offset, offset, g.insert[&offset].as_str())),
    ))
}

/// Applies nonoverlapping, source-ordered edits without shifting each suffix.
fn apply_edits<'a>(
    source: &str,
    edits: impl IntoIterator<Item = (usize, usize, &'a str)>,
) -> String {
    let mut result = String::with_capacity(source.len());
    let mut cursor = 0;
    for (from, to, text) in edits {
        result.push_str(&source[cursor..from]);
        result.push_str(text);
        cursor = to;
    }
    result.push_str(&source[cursor..]);
    result
}

#[cfg(test)]
mod edit_tests {
    use super::apply_edits;

    #[test]
    fn source_edits_preserve_utf8_and_adjacent_boundaries() {
        let source = "α\r\nhello λ!";
        let edits = [(0, 0, "("), (4, 9, "world"), (9, 10, ""), (12, 12, ")")];
        let mut expected = source.to_string();
        for &(from, to, text) in edits.iter().rev() {
            expected.replace_range(from..to, text);
        }
        assert_eq!(apply_edits(source, edits), expected);
        assert_eq!(apply_edits(source, []), source);
    }

    #[test]
    fn many_edits_keep_the_original_coordinate_space() {
        let source = "abcd".repeat(4096);
        let edits: Vec<_> = (0..source.len())
            .step_by(4)
            .map(|at| (at + 1, at + 3, "λ"))
            .collect();
        assert_eq!(apply_edits(&source, edits), "aλd".repeat(4096));
    }
}

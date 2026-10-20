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
    for (index, line) in lines.iter().enumerate() {
        if breaks.contains(&(index + 1)) && !blank {
            output.push(String::new());
            blank = true;
        }
        let parts = &by_line[index + 1];
        if parts.is_empty() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let stripped = line.trim_start_matches(' ');
            let indent = line.len() - stripped.len();
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
    let result = output.join("\n") + "\n";
    let result = format_expression_layout(file, &result)?;
    parse(file, &result)?;
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
        while start > 0 {
            if matches!(
                tokens[start - 1].kind,
                Tok::Newline | Tok::Indent | Tok::Dedent
            ) {
                break;
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

fn token_space(tokens: &[Token], at: usize) -> bool {
    let (current, previous) = (tokens[at].kind, tokens[at - 1].kind);
    if current == Tok::Dot && matches!(previous, Tok::Pipe | Tok::Try) {
        return true;
    }
    if matches!(
        current,
        Tok::RParen | Tok::RBracket | Tok::RBrace | Tok::Comma | Tok::Dot | Tok::Colon
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
        return false;
    }
    if current == Tok::LBracket && matches!(previous, Tok::Name | Tok::RBracket) {
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
        StmtKind::Bind { value, .. }
        | StmtKind::Assign { value, .. }
        | StmtKind::With { value, .. } => Some(value),
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
    if statement_value(s).is_some_and(|v| matches!(v.kind, ExprKind::Match { .. })) {
        return true;
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
        StmtKind::While { body, .. } | StmtKind::For { body, .. } | StmtKind::With { body, .. } => {
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
    let source = group_statement_expressions(file, source)?;
    let module = parse(file, &source)?;
    let tokens = lex(file, &source)?.tokens;
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
    for node in &nodes {
        let Some(gid) = node.group else { continue };
        let g = &layout.groups[gid];
        output.push_str(&source[offset..g.open.lo as usize]);
        let line = output.rsplit('\n').next().unwrap_or("");
        let indent = indent_of(line);
        let column = line.chars().count();
        output.push_str(&layout.group(gid, indent, column, 0));
        offset = g.close.hi as usize;
    }
    output.push_str(&source[offset..]);
    Ok(output)
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

    fn group(&self, gid: usize, indent: usize, column: usize, following: usize) -> String {
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
            return flat;
        }
        if !force {
            // A child's complexity or width can expand the containing argument.
            let trial = self.sequence(
                nodes,
                indent,
                column + (g.open.hi - g.open.lo) as usize,
                false,
            );
            if !trial.contains('\n') {
                return format!("{}{}{}", self.text(&g.open), trial, self.text(&g.close));
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
            return self.packed(g, &parts, indent);
        }
        // Keep an opener's trailing comment on its original line.
        let mut opening = self.text(&g.open).to_string();
        if !nodes.is_empty()
            && nodes[0].tok.kind == Tok::Comment
            && nodes[0].tok.pos.line == g.open.pos.line
        {
            opening.push_str("  ");
            opening.push_str(self.text(&nodes[0].tok));
            let remaining = &nodes[1..];
            parts = split_layout(remaining, Tok::Comma);
            if parts.len() == 1
                && let Some(op) = operator
            {
                parts = split_layout(remaining, op);
            }
        }
        let mut out = opening;
        for part in &parts {
            let text = self.item(part, indent + 4);
            if !text.is_empty() {
                out.push('\n');
                out.push_str(&text);
            }
        }
        out.push('\n');
        out.push_str(&" ".repeat(indent));
        out.push_str(self.text(&g.close));
        out
    }

    /// An item's enclosing delimiters already allow continuation lines. Break
    /// its operators directly rather than inserting another pair of parentheses.
    fn item(&self, nodes: &[Node], indent: usize) -> String {
        let text = self.sequence(nodes, indent, indent, true);
        let long = text.split('\n').any(|l| l.chars().count() > WIDTH);
        let (operator, count) = self.layout_operators(nodes);
        let Some(operator) = operator else {
            return text;
        };
        if !long || (operator == Tok::Dot && count < 2) || is_comparison(operator) {
            return text; // Keep comparison operands together.
        }
        let lines: Vec<String> = split_layout(nodes, operator)
            .iter()
            .map(|p| self.sequence(p, indent, indent, true))
            .collect();
        lines.join("\n")
    }

    fn layout_operators(&self, nodes: &[Node]) -> (Option<Tok>, usize) {
        let (mut selected, mut level, mut count) = (None, 7, 0);
        for node in nodes {
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
                Tok::Dot => 6,
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

    fn sequence(&self, nodes: &[Node], indent: usize, column: usize, prefix: bool) -> String {
        struct W {
            out: String,
            column: usize,
            line_indent: usize,
        }
        impl W {
            fn write(&mut self, text: &str) {
                self.out.push_str(text);
                if let Some(at) = text.rfind('\n') {
                    let tail = &text[at + 1..];
                    self.column = tail.chars().count();
                    self.line_indent = indent_of(tail);
                } else {
                    self.column += text.chars().count();
                }
            }
        }
        let mut w = W {
            out: String::new(),
            column,
            line_indent: indent,
        };
        let mut first_indent = 0i64;
        for node in nodes {
            if !layout_token(node.tok.kind) {
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
            if comment && last_line != node.tok.pos.line && !w.out.is_empty() {
                pending = true;
            }
            if !w.out.is_empty()
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
            if w.out.is_empty() || pending {
                if !w.out.is_empty() {
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
                if prefix || !w.out.is_empty() {
                    let pad = " ".repeat(w.line_indent);
                    w.write(&pad);
                }
            } else if comment {
                w.write("  ");
            } else if node.space {
                w.write(" ");
            }
            if let Some(gid) = node.group {
                let mut tail: Vec<Node> = Vec::new();
                for next in &nodes[index + 1..] {
                    if next.tok.kind == Tok::Newline || next.tok.kind == Tok::Comment {
                        break;
                    }
                    let mut next = *next;
                    if let Some(ng) = next.group
                        && !self.groups[ng].nodes.is_empty()
                    {
                        // The next group has its own continuation
                        // boundary. Its contents must not force this group
                        // (such as a list before a map callback) to
                        // expand as well.
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
                let text = self.group(gid, w.line_indent, w.column, following);
                w.write(&text);
                last_line = self.groups[gid].close.pos.line;
            } else {
                w.write(self.text(&node.tok));
                last_line = node.tok.pos.line;
            }
            pending = comment;
        }
        w.out
    }
}

fn is_comparison(k: Tok) -> bool {
    matches!(
        k,
        Tok::EqEq | Tok::NotEq | Tok::Lt | Tok::Gt | Tok::Le | Tok::Ge
    )
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
        if node.group.is_some() || !matches {
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
fn group_statement_expressions(file: &Arc<str>, source: &str) -> PResult<String> {
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
    }
    impl G<'_> {
        fn wrap(&mut self, start: usize) {
            let tokens = self.tokens;
            let (mut end, mut booleans, mut dots, mut operators) = (start, 0, 0, 0);
            while end < tokens.len() {
                if let Some(&close) = self.pairs.get(&end) {
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
            let mut width = tokens[start].pos.column as usize - 1 + flat.chars().count();
            if end < tokens.len() && tokens[end].kind == Tok::Colon {
                width += 1; // The condition's suite colon occupies a column too.
            }
            if width > WIDTH && (booleans + operators > 0 || dots >= 2) {
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
            if tokens[start].kind == Tok::String {
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
                StmtKind::Bind { .. }
                | StmtKind::Assign { .. }
                | StmtKind::With { .. }
                | StmtKind::For { .. } => {
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
    };
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
    let mut offsets: Vec<usize> = g.insert.keys().copied().collect();
    offsets.sort_unstable_by(|a, b| b.cmp(a));
    let mut result = source.to_string();
    for offset in offsets {
        result.insert_str(offset, &g.insert[&offset]);
    }
    Ok(result)
}

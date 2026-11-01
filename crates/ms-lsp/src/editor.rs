//! Cursor context and repaired-snapshot queries behind completion and
//! signature help.
//!
//! The checker only captures scopes at an expression, so the request's text is
//! repaired in a private snapshot until a marker expression parses and checks;
//! neither diagnostics nor edits are derived from the fabricated text.

use crate::analysis::{self, Analysis, Document, Documents, Options};
use crate::index::{expr_text, hidden_structure};
use crate::text::{self, EditorKind, EditorToken, Position};
use crate::uri;
use ms_check::syntax::{ModRef, ScopeState};
use ms_check::types::{Kind, Name, Ty, n};
use ms_syntax::Phase;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::rc::Rc;

/// What the text around the cursor looks like.
#[derive(Clone, Debug)]
pub struct CursorContext {
    /// Cursor byte offset.
    pub offset: usize,
    /// Start of the identifier under (or before) the cursor.
    pub start: usize,
    /// End of that identifier.
    pub end: usize,
    /// Text of the identifier before the cursor.
    pub prefix: String,
    /// The identifier follows a `.`.
    pub member: bool,
    /// The `(` of the enclosing call.
    pub call_open: Option<usize>,
    /// The cursor is at the start of an argument (a label position).
    pub argument: bool,
    /// The cursor is in type syntax.
    pub type_context: bool,
    /// Inside a string literal.
    pub literal: bool,
    /// Inside a comment.
    pub comment: bool,
}

/// Classifies the text around a position.
pub fn context_at(d: &Document, p: Position) -> Result<CursorContext, &'static str> {
    let offset = text::offset(&d.text, p)?;
    let bytes = d.text.as_bytes();
    let mut c = CursorContext {
        offset,
        start: offset,
        end: offset,
        prefix: String::new(),
        member: false,
        call_open: None,
        argument: false,
        type_context: false,
        literal: false,
        comment: false,
    };
    while c.start > 0 && text::identifier(bytes[c.start - 1]) {
        c.start -= 1;
    }
    while c.end < bytes.len() && text::identifier(bytes[c.end]) {
        c.end += 1;
    }
    c.prefix = String::from_utf8_lossy(&bytes[c.start..offset]).into_owned();
    // Inside a text interpolation the cursor is in an ordinary expression:
    // scan from that expression so the surrounding literal does not hide it.
    let interpolation = interpolation_start(&d.text, offset);
    let tokens: Vec<EditorToken> = match interpolation {
        Some(from) => text::editor_tokens(&d.text[from..])
            .into_iter()
            .map(|t| EditorToken {
                start: t.start + from,
                end: t.end + from,
                ..t
            })
            .collect(),
        None => text::editor_tokens(&d.text),
    };
    let mut before: Vec<EditorToken> = Vec::new();
    for t in &tokens {
        let in_comment_or_string = matches!(t.kind, EditorKind::Comment | EditorKind::Str);
        if in_comment_or_string
            && offset > t.start
            && (offset < t.end
                || (t.kind == EditorKind::Comment && offset == t.end)
                || (t.kind == EditorKind::Str && !t.text.ends_with('"')))
        {
            c.comment = t.kind == EditorKind::Comment;
            c.literal = t.kind == EditorKind::Str;
        }
        if t.end <= c.start {
            before.push(*t);
        }
    }
    if interpolation.is_some() {
        c.literal = false;
    }
    if before.last().is_some_and(|t| t.is(b'.')) {
        c.member = true;
    }
    let mut stack: Vec<usize> = Vec::new();
    for (index, t) in before.iter().enumerate() {
        if t.is(b'(') || t.is(b'[') || t.is(b'{') {
            stack.push(index);
        } else if t.is(b')') || t.is(b']') || t.is(b'}') {
            stack.pop();
        }
    }
    for &at in stack.iter().rev() {
        let t = before[at];
        if !t.is(b'(') || at == 0 {
            continue;
        }
        let previous = before[at - 1];
        if previous.kind != EditorKind::Name && !previous.is(b']') && !previous.is(b')') {
            continue;
        }
        if function_parameters_at(&before, at) {
            continue;
        }
        c.call_open = Some(t.start);
        let mut segment = t.end;
        let mut depth = 0;
        for v in &before[at + 1..] {
            if v.is(b'(') || v.is(b'[') || v.is(b'{') {
                depth += 1;
            } else if v.is(b')') || v.is(b']') || v.is(b'}') {
                depth -= 1;
            } else if v.is(b',') && depth == 0 {
                segment = v.end;
            }
        }
        c.argument = !text_between(&d.text, segment, c.start).contains(':');
        break;
    }
    let line_start = bytes[..c.start]
        .iter()
        .rposition(|&b| b == b'\n')
        .map_or(0, |at| at + 1);
    let line = String::from_utf8_lossy(&bytes[line_start..c.start]);
    let line = line.trim();
    let function_header = line.starts_with("fn ") || line.starts_with("export fn ");
    c.type_context = (function_header && line.ends_with(')'))
        || ((line.contains("let ") || line.contains("var "))
            && line.contains(':')
            && !line.contains('='))
        || (function_header && line.contains(':'));
    // A default is an expression inside a function header. Track only separators
    // at that parameter list's depth so nested calls and types keep their context.
    for &at in stack.iter().rev() {
        if !before[at].is(b'(') || !function_parameters_at(&before, at) {
            continue;
        }
        let (mut depth, mut default_value) = (0, false);
        for token in &before[at + 1..] {
            if token.is(b'(') || token.is(b'[') || token.is(b'{') {
                depth += 1;
            } else if token.is(b')') || token.is(b']') || token.is(b'}') {
                depth -= 1;
            } else if token.is(b'=') && depth == 0 {
                default_value = true;
            } else if token.is(b',') && depth == 0 {
                default_value = false;
            }
        }
        if default_value {
            c.type_context = false;
        }
        break;
    }
    Ok(c)
}

/// The offset where the text interpolation containing `offset` begins
/// (just after its `{`), or `None` when the cursor is outside every
/// interpolation. Literals sit on one line, so only the cursor's line is read.
pub(crate) fn interpolation_start(source: &str, offset: usize) -> Option<usize> {
    #[derive(PartialEq)]
    enum State {
        Code,
        Text,
        Expr,
        ExprText,
    }
    let bytes = source.as_bytes();
    let line = bytes[..offset]
        .iter()
        .rposition(|&b| b == b'\n')
        .map_or(0, |at| at + 1);
    let (mut state, mut depth, mut from) = (State::Code, 0, 0);
    let mut at = line;
    while at < offset {
        let b = bytes[at];
        match state {
            State::Code => match b {
                b'#' => return None,
                b'"' => state = State::Text,
                _ => {}
            },
            State::ExprText => match b {
                b'\\' => at += 1,
                b'"' => state = State::Expr,
                _ => {}
            },
            State::Text => match b {
                b'\\' => at += 1,
                b'"' => state = State::Code,
                b'{' => {
                    (state, depth, from) = (State::Expr, 0, at + 1);
                }
                _ => {}
            },
            State::Expr => match b {
                b'"' => state = State::ExprText,
                b'{' => depth += 1,
                b'}' if depth == 0 => state = State::Text,
                b'}' => depth -= 1,
                _ => {}
            },
        }
        at += 1;
    }
    (state == State::Expr).then_some(from)
}

fn text_between(source: &str, from: usize, to: usize) -> String {
    if from >= to {
        return String::new();
    }
    String::from_utf8_lossy(&source.as_bytes()[from..to]).into_owned()
}

fn function_parameters_at(tokens: &[EditorToken], at: usize) -> bool {
    if at > 0 && tokens[at - 1].text == "fn" {
        return true;
    }
    let mut previous = at as isize - 1;
    if previous >= 0 && tokens[previous as usize].is(b']') {
        let mut depth = 1;
        previous -= 1;
        while previous >= 0 && depth > 0 {
            if tokens[previous as usize].is(b']') {
                depth += 1;
            }
            if tokens[previous as usize].is(b'[') {
                depth -= 1;
            }
            previous -= 1;
        }
    }
    previous > 0
        && tokens[previous as usize].kind == EditorKind::Name
        && tokens[previous as usize - 1].text == "fn"
}

/// Closes the delimiters still open at the end of the cursor's line, for a
/// private snapshot only.
pub fn close_delimiters(source: &str, line: usize) -> String {
    let (start, _) = text::line_span(source, line);
    let bytes = source.as_bytes();
    // A source that has fewer lines than requested is returned unchanged.
    if line > 0 && start == 0 {
        return source.to_string();
    }
    let end = match bytes[start..].iter().position(|&b| b == b'\n') {
        Some(offset) => start + offset,
        None => bytes.len(),
    };
    let mut stack: Vec<EditorToken> = Vec::new();
    for t in text::editor_tokens(source) {
        if t.is(b'(') || t.is(b'[') || t.is(b'{') {
            stack.push(t);
        } else if t.is(b')') || t.is(b']') || t.is(b'}') {
            stack.pop();
        }
    }
    // Only the cursor's own declaration is repaired. An opener left unmatched
    // by an earlier declaration is independent of it, and closing it here
    // would damage the cursor's valid declaration.
    let declaration = declaration_start(source, start);
    let mut tail = String::new();
    for t in stack.iter().rev() {
        // A later broken declaration must not close its opener on the cursor's
        // earlier, valid line and erase that declaration's scope.
        if t.start >= declaration && t.start <= end {
            tail.push(match t.kind {
                EditorKind::Char(b'(') => ')',
                EditorKind::Char(b'[') => ']',
                _ => '}',
            });
        }
    }
    format!("{}{}{}", &source[..end], tail, &source[end..])
}

/// The start of the top-level declaration containing byte `at`: the nearest
/// line at or before it that begins in column zero with something other than a
/// comment or a closing delimiter.
fn declaration_start(source: &str, at: usize) -> usize {
    let mut start = at;
    loop {
        let line = &source[start..];
        if line
            .bytes()
            .next()
            .is_some_and(|b| !matches!(b, b' ' | b'\t' | b'\r' | b'\n' | b'#' | b')' | b']' | b'}'))
        {
            return start;
        }
        if start == 0 {
            return 0;
        }
        start = source[..start - 1].rfind('\n').map_or(0, |i| i + 1);
    }
}

/// A checked repaired snapshot with the captured scope of the marker.
pub struct EditorAnalysis {
    /// The analysis of the repaired snapshot.
    pub result: Rc<Analysis>,
    /// The repaired document.
    pub document: Document,
    /// The marker identifier.
    pub marker: String,
    /// The expression the marker stands for.
    pub expression: Option<Expr>,
    /// The module the expression is in.
    pub module: Option<ModRef>,
    /// The lexical environment at the marker.
    pub scope: ScopeState,
}

/// Finds the marker expression and its captured scope in a checked analysis.
fn find_marker(
    result: &Analysis,
    document: &Document,
    marker: &str,
) -> Option<(Expr, ModRef, ScopeState)> {
    struct Find<'a> {
        scopes: &'a std::collections::HashMap<NodeId, ScopeState>,
        marker: &'a str,
        found: Option<(Expr, ScopeState)>,
    }
    impl Visitor for Find<'_> {
        fn expr(&mut self, e: &Expr) {
            if self.found.is_none()
                && expr_text(e) == Some(self.marker)
                && let Some(state) = self.scopes.get(&e.id)
            {
                self.found = Some((e.clone(), state.clone()));
            }
        }
    }
    let module = result.module(document)?;
    let scopes = module.facts().scopes.clone();
    let mut find = Find {
        scopes: &scopes,
        marker,
        found: None,
    };
    for d in &module.decls {
        visit::walk_decl(&mut find, d.decl());
    }
    find.found.map(|(e, s)| (e, module, s))
}

/// Whether any module captured a scope for the marker.
fn captured(result: &Analysis) -> bool {
    result
        .program
        .as_ref()
        .is_some_and(|p| p.modules.iter().any(|m| !m.facts().scopes.is_empty()))
}

/// Analyzes the document with the cursor replaced by a marker, repairing the
/// private snapshot a bounded number of times until the marker is captured.
pub fn query_editor(d: &Document, docs: &Documents, c: &CursorContext) -> EditorAnalysis {
    let mut marker = String::from("__manuscript_completion");
    while d.text.contains(&marker) {
        marker.push('_');
    }
    let mut replacement = marker.clone();
    if c.argument && !c.member {
        replacement.push_str(&format!(": {marker}"));
    }
    let mut modified = d.clone();
    modified.text = format!("{}{}{}", &d.text[..c.start], replacement, &d.text[c.end..]);
    if c.type_context {
        let bytes = modified.text.as_bytes();
        let line_start = bytes[..c.start]
            .iter()
            .rposition(|&b| b == b'\n')
            .map_or(0, |at| at + 1);
        let line_end = bytes[c.start..]
            .iter()
            .position(|&b| b == b'\n')
            .map_or(bytes.len(), |at| at + c.start);
        let line = modified.text[line_start..line_end].to_string();
        let trimmed = line.trim();
        if trimmed.starts_with("let ") || trimmed.starts_with("var ") {
            // Query the lexical environment before this local annotation. A type
            // marker alone cannot capture bindings that shadow a prelude type.
            let indent = &line[..line.len() - line.trim_start_matches([' ', '\t']).len()];
            modified.text = format!(
                "{}{indent}let {marker}_value = {marker}{}",
                &modified.text[..line_start],
                &modified.text[line_end..]
            );
        }
    }
    let cursor_line = text::position(&d.text, c.offset).line;
    modified.text = close_delimiters(&modified.text, cursor_line);
    let mut open = docs.clone();
    open.insert(d.uri.clone(), modified.clone());
    let mut result = Rc::new(Analysis::default());
    // Repair only this private analysis snapshot. Stop after a bounded number
    // of faults.
    for _ in 0..24 {
        result = analysis::analyze_options(
            &modified,
            &open,
            Options {
                recover: true,
                scope_marker: Some(marker.clone()),
                ..Options::default()
            },
        );
        if result.program.is_some() && (captured(&result) || c.type_context) {
            break;
        }
        let Some(issue) = result.diagnostics.first() else {
            break;
        };
        if issue.phase != Phase::Parse {
            break;
        }
        let mut target = modified.clone();
        if !result.source_root.is_empty() && !issue.file.is_empty() {
            let path = result.module_path(&issue.file);
            if let Some(found) = open.values().find(|o| uri::filename(&o.uri) == path) {
                target = found.clone();
            }
        }
        let mut lines: Vec<String> = target.text.split('\n').map(str::to_string).collect();
        let mut line = (issue.pos.line as i64) - 1;
        if line >= lines.len() as i64 {
            line = lines.len() as i64 - 1;
        }
        if line < 0 {
            break;
        }
        let mut line = line as usize;
        if lines[line].trim().is_empty() && line > 0 {
            line -= 1;
        }
        let current = lines[line].clone();
        let indent = current.len() - current.trim_start_matches(' ').len();
        if current.contains(&marker) {
            // A half-written statement can still query the scope using a standalone
            // expression at the same indentation. Member queries retain the receiver.
            let start = current.find(&marker).unwrap_or(0);
            let mut prefix = current[..start].to_string();
            let spaces = " ".repeat(indent);
            if c.member {
                if let Some(at) = prefix.rfind("return ") {
                    prefix = prefix[at + 7..].to_string();
                }
                if let Some(at) = prefix.rfind(" = ") {
                    prefix = prefix[at + 3..].to_string();
                }
                lines[line] = format!("{spaces}let {marker}_value = {}{marker}", prefix.trim());
            } else {
                lines[line] = format!("{spaces}let {marker}_value = {marker}");
            }
            if lines[line] == current {
                break;
            }
        } else if current.trim().ends_with(':')
            && (line + 1 == lines.len() || lines[line + 1].trim().is_empty())
        {
            let body = if current.trim().starts_with("match ") {
                vec![
                    format!("{}_:", " ".repeat(indent + 4)),
                    format!("{}return unit", " ".repeat(indent + 8)),
                ]
            } else {
                vec![format!("{}return unit", " ".repeat(indent + 4))]
            };
            for (i, row) in body.into_iter().enumerate() {
                lines.insert(line + 1 + i, row);
            }
        } else {
            lines[line] = format!("{}return unit", " ".repeat(indent));
            if lines[line] == current {
                break;
            }
        }
        target.text = lines.join("\n");
        open.insert(target.uri.clone(), target.clone());
        if target.uri == d.uri {
            modified = target;
        }
    }
    let found = if result.program.is_some() {
        find_marker(&result, &modified, &marker)
    } else {
        None
    };
    let (expression, module, scope) = match found {
        Some((e, m, s)) => (Some(e), Some(m), s),
        None => (None, None, ScopeState::default()),
    };
    EditorAnalysis {
        result,
        document: modified,
        marker,
        expression,
        module,
        scope,
    }
}

/// The type a name or generic application stands for in a captured scope.
pub fn type_expression(e: &Expr, state: &ScopeState) -> Option<Ty> {
    match &e.kind {
        ExprKind::Name(name) => {
            if let Some(t) = state.types.get(&n(name.as_str())) {
                return Some(t.clone());
            }
            let symbol = state.symbols.get(&n(name.as_str()))?;
            (symbol.kind == ms_check::types::SymKind::Type).then(|| symbol.ty())
        }
        ExprKind::Apply { left, types, .. } => {
            let base = type_expression(left, state)?;
            let mut copy = (*base).clone();
            copy.args = Vec::new();
            for arg in types {
                copy.args.push(resolve_editor_type(arg, state)?);
            }
            Some(Rc::new(copy))
        }
        _ => None,
    }
}

fn resolve_editor_type(t: &TypeRef, state: &ScopeState) -> Option<Ty> {
    let TypeKind::Named { name, args } = &t.kind else {
        return None;
    };
    let name: Name = n(name.as_str());
    let base = match state.types.get(&name) {
        Some(t) => t.clone(),
        None => {
            let symbol = state.symbols.get(&name)?;
            if symbol.kind != ms_check::types::SymKind::Type {
                return None;
            }
            symbol.ty()
        }
    };
    let mut copy = (*base).clone();
    copy.args = Vec::new();
    for arg in args {
        copy.args.push(resolve_editor_type(arg, state)?);
    }
    Some(Rc::new(copy))
}

/// Whether the expression is or contains the marker through its operands.
pub fn contains_marker(e: &Expr, marker: &str) -> bool {
    if expr_text(e) == Some(marker) {
        return true;
    }
    match &e.kind {
        ExprKind::Member { left, .. } | ExprKind::Apply { left, .. } => {
            contains_marker(left, marker)
        }
        ExprKind::Index { left, index } => {
            contains_marker(left, marker) || contains_marker(index, marker)
        }
        ExprKind::Unary { operand, .. } => contains_marker(operand, marker),
        ExprKind::Binary { left, right, .. } => {
            contains_marker(left, marker) || contains_marker(right, marker)
        }
        ExprKind::Call { callee, .. } => contains_marker(callee, marker),
        _ => false,
    }
}

/// The signature of the call that contains the marker, with the call itself.
pub fn query_call(a: &EditorAnalysis) -> Option<(Expr, Ty)> {
    let module = a.module.clone().or_else(|| a.result.module(&a.document))?;
    struct Calls<'a> {
        marker: &'a str,
        module: &'a ModRef,
        found: Option<(Expr, Ty)>,
        scope: &'a ScopeState,
        hidden: std::collections::HashMap<NodeId, bool>,
    }
    impl Visitor for Calls<'_> {
        fn expr(&mut self, e: &Expr) {
            if self.found.is_some() {
                return;
            }
            let ExprKind::Call { callee, args } = &e.kind else {
                return;
            };
            let matched = args.iter().any(|a| {
                a.name.is_some_and(|n| n.as_str() == self.marker)
                    || contains_marker(&a.value, self.marker)
            });
            if !matched {
                return;
            }
            let facts = self.module.facts();
            if facts
                .info(e.id)
                .is_some_and(|info| hidden_structure(self.module, e, info, &mut self.hidden))
            {
                return;
            }
            if let Some(info) = facts.info(callee.id)
                && let Some(ty) = &info.ty
                && ty.kind == Kind::Function
            {
                let mut signature = ty.clone();
                if ty.to_string().contains("<invalid>")
                    && let Some(symbol) = &info.symbol
                    && let Some(t) = symbol.ty_opt()
                {
                    signature = t;
                }
                self.found = Some((e.clone(), signature));
                return;
            }
            if let Some(constructed) = facts.info(e.id)
                && let (Some(constructor), Some(case)) =
                    (&constructed.constructor, constructed.case)
            {
                for cs in ms_check::types::cases(constructor) {
                    if cs.name == case {
                        let sig = ms_check::types::function(cs.fields.clone(), constructor.clone());
                        self.found = Some((e.clone(), sig));
                        return;
                    }
                }
            }
            if let Some(ty) = type_expression(callee, self.scope) {
                if ty
                    .opaque_module()
                    .is_some_and(|file| file != self.module.file)
                {
                    return;
                }
                let sig = ms_check::types::constructor_signature(&ty);
                self.found = Some((e.clone(), sig));
            }
        }
    }
    let mut calls = Calls {
        marker: &a.marker,
        module: &module,
        found: None,
        scope: &a.scope,
        hidden: std::collections::HashMap::new(),
    };
    for d in &module.decls {
        visit::walk_decl(&mut calls, d.decl());
    }
    calls.found
}

/// The written arguments of a call with labels resolved by the checker.
pub fn call_arguments(a: &EditorAnalysis, call: &Expr) -> Vec<(String, Expr)> {
    let ExprKind::Call { args, .. } = &call.kind else {
        return Vec::new();
    };
    let module = a.module.clone().or_else(|| a.result.module(&a.document));
    let slots = module.and_then(|m| m.facts().info(call.id).and_then(|i| i.arguments.clone()));
    match slots {
        Some(slots) => slots
            .iter()
            .filter_map(|slot| {
                args.get(slot.index)
                    .map(|a| (slot.name.as_str().to_string(), a.value.clone()))
            })
            .collect(),
        None => args
            .iter()
            .map(|a| {
                (
                    a.name.map(|n| n.as_str().to_string()).unwrap_or_default(),
                    a.value.clone(),
                )
            })
            .collect(),
    }
}

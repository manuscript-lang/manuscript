//! Longer spellings of shorter forms that mean the same thing: `xs.length() == 0`
//! (`MSL118`) and `xs.get(i)` on a list (`MSL119`). Each finding carries the fix.

use super::bindings::pos_at;
use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_check::api::types::Builtin;
use ms_syntax::Pos;
use ms_syntax::Symbol;
use ms_syntax::ast::*;
use ms_syntax::diag::DiagnosticFix;
use ms_syntax::visit::{self, Visitor};

pub(super) fn lint(syms: ms_syntax::Names, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(syms, module);
    let mut scan = Scan {
        syms,
        module,
        file: &file,
        findings,
    };
    for decl in &module.decls {
        match &decl.decl().kind {
            DeclKind::Fn(f) => scan.trailing_return(f),
            DeclKind::Impl(i) => i.methods.iter().for_each(|m| scan.trailing_return(&m.func)),
            _ => {}
        }
    }
    walk_module(module, &mut scan);
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Scan<'_> {
    fn source(&self) -> &str {
        &self.module.source
    }

    fn collection(&self, e: &Expr) -> bool {
        self.module
            .facts()
            .info(e.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| {
                t.is_string() || t.is(Builtin::List) || t.is(Builtin::Map) || t.is(Builtin::Set)
            })
    }

    /// A list whose elements copy (`Int`, `Float`, `Bool`): `xs[i]` can stand where `xs.get(i)` does.
    fn list(&self, e: &Expr) -> bool {
        self.module
            .facts()
            .info(e.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| {
                t.is(Builtin::List)
                    && t.args
                        .first()
                        .and_then(|a| a.builtin)
                        .is_some_and(|b| b.is_int() || b.is_float() || b == Builtin::Bool)
            })
    }

    /// `recv.length()` as its receiver.
    fn length_of<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        (self.syms.str(name) == "length" && args.is_empty() && self.collection(left))
            .then_some(&**left)
    }

    fn text(&self, from: &Expr, to: &Expr) -> Option<&str> {
        let (a, b) = (from.start().offset as usize, to.end.offset as usize);
        self.source()
            .get(a..b)
            .filter(|t| balanced(t) && !t.contains('\n'))
    }

    fn report(
        &mut self,
        code: &'static str,
        message: String,
        at: Pos,
        from: usize,
        to: usize,
        replacement: String,
    ) {
        let mut found = finding(code, message, self.file, at);
        found.fix = Some(DiagnosticFix {
            pos: pos_at(self.source(), from),
            end: pos_at(self.source(), to),
            replacement,
        });
        self.findings.push(found);
    }

    /// `x.length() == 0` and, in a condition, `x.length() != 0` / `> 0`.
    fn emptiness(&mut self, e: &Expr, condition: bool) {
        match &e.kind {
            ExprKind::Binary {
                op: BinaryOp::And | BinaryOp::Or,
                left,
                right,
            } => {
                self.emptiness(left, condition);
                self.emptiness(right, condition);
            }
            ExprKind::Binary { op, left, right } => {
                let zero = matches!(&right.kind, ExprKind::Number(n) if self.syms.str(n) == "0");
                let Some(receiver) = self.length_of(left).filter(|_| zero) else {
                    return;
                };
                let Some(recv) = self.text(receiver, receiver) else {
                    return;
                };
                let replacement = match op {
                    // `== 0` is reported where the expression is visited.
                    BinaryOp::Eq if !condition => format!("{recv}.is_empty()"),
                    BinaryOp::Ne | BinaryOp::Gt if condition => format!("not {recv}.is_empty()"),
                    _ => return,
                };
                self.report(
                    "MSL118",
                    "Use is_empty() instead of comparing length() with 0".to_string(),
                    e.pos,
                    e.start().offset as usize,
                    right.end.offset as usize,
                    replacement,
                );
            }
            _ => {}
        }
    }
}

impl Visitor for Scan<'_> {
    fn block(&mut self, body: &[Stmt]) {
        for at in 0..body.len() {
            self.default_then_reassign(body, at);
            self.temp_return(body, at);
            self.counter_while(body, at);
            self.accumulate_loop(body, at);
            self.index_loop(&body[at]);
            self.append_all(&body[at]);
            self.map_update(&body[at]);
        }
    }

    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::If {
                binding: None,
                cond,
                ..
            }
            | StmtKind::While { cond, .. } => self.emptiness(cond, true),
            StmtKind::Return(Some(e)) => self.emptiness(e, true),
            _ => {}
        }
    }

    fn expr(&mut self, e: &Expr) {
        if let ExprKind::Binary {
            op: BinaryOp::Eq, ..
        } = &e.kind
        {
            self.emptiness(e, false);
        }
        self.map_get_chain(e);
        // `xs.get(i)` on a list held in a name or field is `xs[i]`.
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return;
        };
        let ([arg], true) = (args.as_slice(), self.syms.str(name) == "get") else {
            return;
        };
        if arg.name.is_some()
            || !matches!(left.kind, ExprKind::Name(_) | ExprKind::Member { .. })
            || !self.list(left)
        {
            return;
        }
        let dot = (name_pos(callee) as usize).checked_sub(1);
        let source = self.source();
        let (Some(dot), Some(index)) = (dot, self.text(&arg.value, &arg.value)) else {
            return;
        };
        if source.as_bytes().get(dot) != Some(&b'.') {
            return;
        }
        let index = index.to_string();
        self.report(
            "MSL119",
            "Index the list with xs[i] instead of xs.get(i)".to_string(),
            e.pos,
            dot,
            e.end.offset as usize,
            format!("[{index}]"),
        );
    }
}

fn name_pos(callee: &Expr) -> u32 {
    callee.pos.offset
}

/// How a name is used in a piece of the tree.
struct Uses {
    name: Symbol,
    reads: usize,
    writes: usize,
}

impl Visitor for Uses {
    fn stmt(&mut self, s: &Stmt) {
        if let StmtKind::Assign {
            target: AssignTarget::Name(n),
            ..
        } = &s.kind
            && *n == self.name
        {
            self.writes += 1;
        }
    }

    fn expr(&mut self, e: &Expr) {
        match &e.kind {
            ExprKind::Name(n) if *n == self.name => self.reads += 1,
            ExprKind::Call { args, .. } => {
                for a in args {
                    if a.mutable && matches!(&a.value.kind, ExprKind::Name(n) if *n == self.name) {
                        self.writes += 1;
                    }
                }
            }
            _ => {}
        }
    }
}

fn uses_in(name: Symbol, stmts: &[Stmt]) -> Uses {
    let mut uses = Uses {
        name,
        reads: 0,
        writes: 0,
    };
    for s in stmts {
        visit::walk_stmt(&mut uses, s);
    }
    uses
}

fn expr_reads(name: Symbol, e: &Expr) -> usize {
    let mut uses = Uses {
        name,
        reads: 0,
        writes: 0,
    };
    visit::walk_expr(&mut uses, e);
    uses.reads
}

fn plain_number(e: &Expr, source: &str) -> bool {
    matches!(e.kind, ExprKind::Number(_))
        && source
            .get(e.start().offset as usize..e.end.offset as usize)
            .is_some_and(|t| t.bytes().all(|b| b.is_ascii_digit()))
}

impl Scan<'_> {
    fn span(&self, from: usize, to: usize) -> Option<&str> {
        self.source().get(from..to)
    }

    fn expr_text(&self, e: &Expr) -> Option<&str> {
        self.span(e.start().offset as usize, e.end.offset as usize)
            .filter(|t| balanced(t) && !t.contains('\n'))
    }

    /// `m[k.clone()] = m.get(k).get() op rest` on a map is `m[k] op= rest`: both fault when
    /// the key is missing, and the compound form needs no clone of the key.
    fn map_update(&mut self, s: &Stmt) {
        let StmtKind::Call(call) = &s.kind else {
            return;
        };
        let ExprKind::Call { callee, args } = &call.kind else {
            return;
        };
        let ExprKind::Member { left: map, name } = &callee.kind else {
            return;
        };
        let [index, value] = args.as_slice() else {
            return;
        };
        if self.syms.str(name) != ms_syntax::parser::INDEX_SET
            || index.name.is_some()
            || !is_path(map)
            || !self.is_map(map)
        {
            return;
        }
        let ExprKind::Binary { op, left, right } = &value.value.kind else {
            return;
        };
        let symbol = match op {
            BinaryOp::Add => "+=",
            BinaryOp::Sub => "-=",
            BinaryOp::Mul => "*=",
            BinaryOp::Div => "/=",
            BinaryOp::Rem => "%=",
            _ => return,
        };
        // `map.get(key).get()`
        let ExprKind::Call {
            callee: outer,
            args: none,
        } = &left.kind
        else {
            return;
        };
        let ExprKind::Member {
            left: inner,
            name: unwrap,
        } = &outer.kind
        else {
            return;
        };
        let ExprKind::Call {
            callee: lookup,
            args: key,
        } = &inner.kind
        else {
            return;
        };
        let ExprKind::Member {
            left: again,
            name: get,
        } = &lookup.kind
        else {
            return;
        };
        let ([key], true) = (key.as_slice(), none.is_empty()) else {
            return;
        };
        if self.syms.str(unwrap) != "get"
            || self.syms.str(get) != "get"
            || key.name.is_some()
            || !is_path(&key.value)
        {
            return;
        }
        let (Some(map_text), Some(again_text), Some(key_text), Some(index_text), Some(rest)) = (
            self.expr_text(map),
            self.expr_text(again),
            self.expr_text(&key.value),
            self.expr_text(&index.value),
            self.expr_text(right),
        ) else {
            return;
        };
        let cloned = format!("{key_text}.clone()");
        if map_text != again_text || (index_text != key_text && index_text != cloned) {
            return;
        }
        let (from, to) = (s.pos.offset as usize, right.end.offset as usize);
        let Some(whole) = self.span(from, to) else {
            return;
        };
        if whole.contains("//") || whole.contains('\n') {
            return;
        }
        let text = format!("{map_text}[{key_text}] {symbol} {rest}");
        self.report(
            "MSL127",
            "Update the map entry in place with `m[k] op= value`".to_string(),
            s.pos,
            from,
            to,
            text,
        );
    }

    fn is_map(&self, e: &Expr) -> bool {
        self.module
            .facts()
            .info(e.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| t.is(Builtin::Map))
    }

    /// `m.get(k).get(d)` on a map is `m.get_or(k, d)`.
    fn map_get_chain(&mut self, e: &Expr) {
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let ExprKind::Member { left: inner, name } = &callee.kind else {
            return;
        };
        let ([fallback], true) = (args.as_slice(), self.syms.str(name) == "get") else {
            return;
        };
        let ExprKind::Call {
            callee: ic,
            args: iargs,
        } = &inner.kind
        else {
            return;
        };
        let ExprKind::Member {
            left: map,
            name: iname,
        } = &ic.kind
        else {
            return;
        };
        let [key] = iargs.as_slice() else { return };
        let is_map = self
            .module
            .facts()
            .info(map.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| t.is(Builtin::Map));
        let argument_var = |a: &Argument| {
            a.mutable || self.expr_text(&a.value).is_some_and(|t| t.contains("var "))
        };
        if !is_map
            || self.syms.str(iname) != "get"
            || key.name.is_some()
            || fallback.name.is_some()
            || argument_var(key)
            || argument_var(fallback)
        {
            return;
        }
        let dot = (ic.pos.offset as usize).checked_sub(1);
        let (Some(dot), Some(k), Some(d)) = (
            dot,
            self.expr_text(&key.value).map(str::to_string),
            self.expr_text(&fallback.value).map(str::to_string),
        ) else {
            return;
        };
        if self.source().as_bytes().get(dot) != Some(&b'.') {
            return;
        }
        self.report(
            "MSL120",
            "Use map.get_or(key, default) instead of map.get(key).get(default)".to_string(),
            e.pos,
            dot,
            e.end.offset as usize,
            format!(".get_or({k}, {d})"),
        );
    }

    /// `var x = a` then `if c: x = b` is `let x = if c: b else: a`.
    fn default_then_reassign(&mut self, body: &[Stmt], at: usize) {
        let (Some(first), Some(second)) = (body.get(at), body.get(at + 1)) else {
            return;
        };
        let StmtKind::Bind {
            mutable: true,
            pattern:
                Pattern {
                    kind: PatternKind::Name(name),
                    ..
                },
            ty: None,
            value: default,
            group: None,
        } = &first.kind
        else {
            return;
        };
        let StmtKind::If {
            binding: None,
            cond,
            body: then,
            else_body,
            ..
        } = &second.kind
        else {
            return;
        };
        let ([only], true) = (then.as_slice(), else_body.is_empty()) else {
            return;
        };
        let StmtKind::Assign {
            target: AssignTarget::Name(target),
            compound: None,
            value: replacement,
        } = &only.kind
        else {
            return;
        };
        let simple = matches!(
            default.kind,
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Name(_)
        ) || matches!(&default.kind, ExprKind::Text(parts) if parts.iter().all(|p| matches!(p, TextPart::Lit(_))));
        let scalar = self
            .module
            .facts()
            .info(default.id)
            .and_then(|i| i.ty.as_ref())
            .is_some_and(|t| {
                t.is_string() || t.is(Builtin::Int) || t.is(Builtin::Float) || t.is(Builtin::Bool)
            });
        let rest = &body[at + 2..];
        let later = uses_in(*name, rest);
        let in_cond = expr_reads(*name, cond) + expr_reads(*name, replacement);
        if target != name || !simple || !scalar || later.writes > 0 || in_cond > 0 {
            return;
        }
        let (from, to) = (first.pos.offset as usize, replacement.end.offset as usize);
        let (Some(whole), Some(a), Some(c), Some(b)) = (
            self.span(from, to),
            self.expr_text(default),
            self.expr_text(cond),
            self.expr_text(replacement),
        ) else {
            return;
        };
        if whole.contains("//") {
            return;
        }
        let text = format!("{} := if {c}: {b} else: {a}", self.syms.str(name));
        let (a, c, b) = (a.to_string(), c.to_string(), b.to_string());
        let _ = (a, c, b);
        self.report(
            "MSL121",
            "Write the default and the override as one `x := if c: b else: a`".to_string(),
            first.pos,
            from,
            to,
            text,
        );
    }

    /// A final `return ok(unit)` in a `Unit!` function, or `return` in a `Unit` one: the end of the
    /// body already returns it.
    fn trailing_return(&mut self, f: &Func) {
        let TypeKind::Named { name, args } = &f.result.kind else {
            return;
        };
        let unit = |t: &TypeRef| t.name(self.syms) == "Unit";
        let result = self.syms.str(name) == "Result" && args.len() == 2 && unit(&args[0]);
        if f.body.len() < 2 || !(result || unit(&f.result)) {
            return;
        }
        let Some(last) = f.body.last() else {
            return;
        };
        let StmtKind::Return(value) = &last.kind else {
            return;
        };
        let redundant = match value {
            None => !result,
            Some(e) if matches!(e.kind, ExprKind::Unit) => !result,
            Some(e) => result && self.ok_unit(e),
        };
        if !redundant {
            return;
        }
        let end = value
            .as_ref()
            .map_or(last.pos.offset as usize + "return".len(), |e| {
                e.end.offset as usize
            });
        let source = self.source();
        let mut from = last.pos.offset as usize;
        while from > 0 && source.as_bytes()[from - 1] == b' ' {
            from -= 1;
        }
        let mut to = end;
        if source.as_bytes().get(to) == Some(&b'\n') {
            to += 1;
        }
        let Some(line) = self.span(from, to) else {
            return;
        };
        if line.contains("//") || from == 0 || source.as_bytes()[from - 1] != b'\n' {
            return;
        }
        self.report(
            "MSL128",
            "Drop the final return: the end of the function already returns it".to_string(),
            last.pos,
            from,
            to,
            String::new(),
        );
    }

    /// `ok(unit)`.
    fn ok_unit(&self, e: &Expr) -> bool {
        let ExprKind::Call { callee, args } = &e.kind else {
            return false;
        };
        matches!(&callee.kind, ExprKind::Name(n) if self.syms.str(n) == "ok")
            && matches!(args.as_slice(), [a] if a.name.is_none() && matches!(a.value.kind, ExprKind::Unit))
    }

    /// `let x = e` directly followed by `return x` is `return e`.
    fn temp_return(&mut self, body: &[Stmt], at: usize) {
        let (Some(first), Some(second)) = (body.get(at), body.get(at + 1)) else {
            return;
        };
        let StmtKind::Bind {
            pattern:
                Pattern {
                    kind: PatternKind::Name(name),
                    ..
                },
            ty: None,
            value,
            group: None,
            ..
        } = &first.kind
        else {
            return;
        };
        let StmtKind::Return(Some(ret)) = &second.kind else {
            return;
        };
        if !matches!(&ret.kind, ExprKind::Name(n) if n == name) {
            return;
        }
        let (from, to) = (first.pos.offset as usize, ret.end.offset as usize);
        let (Some(whole), Some(text)) = (self.span(from, to), self.expr_text(value)) else {
            return;
        };
        if whole.contains("//") || text.contains('\n') {
            return;
        }
        let text = format!("return {text}");
        self.report(
            "MSL126",
            "Return the value directly instead of binding it first".to_string(),
            first.pos,
            from,
            to,
            text,
        );
    }

    /// `var i = 0` / `while i < n:` ... `i += 1` is `for i in 0..n:`.
    fn counter_while(&mut self, body: &[Stmt], at: usize) {
        let StmtKind::While {
            cond,
            body: loop_body,
        } = &body[at].kind
        else {
            return;
        };
        let ExprKind::Binary {
            op: BinaryOp::Lt,
            left,
            right: bound,
        } = &cond.kind
        else {
            return;
        };
        let ExprKind::Name(name) = &left.kind else {
            return;
        };
        let Some(bind_at) = body[..at].iter().rposition(|s| {
            matches!(
                &s.kind,
                StmtKind::Bind {
                    pattern: Pattern { kind: PatternKind::Name(n), .. },
                    ..
                } if n == name
            )
        }) else {
            return;
        };
        let first = &body[bind_at];
        let StmtKind::Bind {
            mutable: true,
            ty: None,
            value: start,
            group: None,
            ..
        } = &first.kind
        else {
            return;
        };
        if !plain_number(start, self.source()) || {
            let between = uses_in(*name, &body[bind_at + 1..at]);
            between.reads + between.writes > 0
        } {
            return;
        }
        let Some((last, inner)) = loop_body.split_last() else {
            return;
        };
        let StmtKind::Assign {
            target: AssignTarget::Name(t),
            value: step,
            ..
        } = &last.kind
        else {
            return;
        };
        let ExprKind::Binary {
            op: BinaryOp::Add,
            left: sl,
            right: sr,
        } = &step.kind
        else {
            return;
        };
        if t != name
            || !matches!(&sl.kind, ExprKind::Name(n) if n == name)
            || self.expr_text(sr) != Some("1")
        {
            return;
        }
        let invariant = plain_number(bound, self.source())
            || matches!(&bound.kind, ExprKind::Name(n) if uses_in(*n, inner).writes == 0);
        let inside = uses_in(*name, inner);
        let after = uses_in(*name, &body[at + 1..]);
        let source = self.source();
        let while_at = body[at].pos.offset as usize;
        let bind_line = source[..first.pos.offset as usize]
            .rfind('\n')
            .map_or(0, |i| i + 1);
        let bind_alone = source[bind_line..first.pos.offset as usize]
            .trim()
            .is_empty();
        let bind_end = start.end.offset as usize;
        let bind_eol = source[bind_end..].find('\n').map(|i| bind_end + i);
        let (Some(s_text), Some(n_text)) = (self.expr_text(start), self.expr_text(bound)) else {
            return;
        };
        let colon = source[bound.end.offset as usize..].trim_start();
        let header_end = source.len() - colon.len() + 1;
        let last_line = source[..last.pos.offset as usize]
            .rfind('\n')
            .map_or(0, |i| i + 1);
        let last_alone = source[last_line..last.pos.offset as usize]
            .trim()
            .is_empty();
        let step_end = step.end.offset as usize;
        let tail = &source[step_end..];
        let eol = tail.find('\n').unwrap_or(tail.len());
        let (Some(bind_eol), Some(whole)) = (bind_eol, source.get(bind_line..step_end)) else {
            return;
        };
        if !invariant
            || inside.writes > 0
            || after.reads + after.writes > 0
            || !colon.starts_with(':')
            || !bind_alone
            || !source[bind_end..bind_eol].trim().is_empty()
            || !last_alone
            || !tail[..eol].trim().is_empty()
            || whole.contains("//")
            || whole.contains("continue")
            || header_end > last_line
        {
            return;
        }
        let text = format!(
            "{}for {} in {s_text}..{n_text}:{}",
            &source[bind_eol + 1..while_at],
            self.syms.str(name),
            &source[header_end..last_line]
        );
        self.report(
            "MSL122",
            "Count with `for i in start..end:` instead of a `var` and a `while` with `i += 1`"
                .to_string(),
            first.pos,
            bind_line,
            step_end + eol,
            text.trim_end_matches('\n').to_string(),
        );
    }

    /// `for i in 0..xs.length():` that only reads `xs[i]` is `for x in xs:`.
    fn index_loop(&mut self, s: &Stmt) {
        let StmtKind::For { name, iter, body } = &s.kind else {
            return;
        };
        let Some(text) = self.expr_text(iter) else {
            return;
        };
        let Some(list) = text
            .strip_prefix("0..")
            .and_then(|t| t.strip_suffix(".length()"))
            .filter(|l| !l.is_empty() && l.chars().all(|c| c.is_alphanumeric() || c == '_'))
        else {
            return;
        };
        let total = uses_in(*name, body).reads;
        let indexed = self
            .span(s.pos.offset as usize, self.body_end(body))
            .map_or(0, |t| {
                let pattern = format!("{list}[{}]", self.syms.str(name));
                t.matches(&pattern).count()
            });
        if total > 0 && total == indexed {
            let message = format!(
                "Loop over the list directly: `for item in {list}:` instead of indexing {list}[{}]",
                self.syms.str(name)
            );
            self.findings
                .push(finding("MSL123", message, self.file, s.pos));
        }
    }

    fn body_end(&self, body: &[Stmt]) -> usize {
        let mut end = 0;
        for s in body {
            let mut e = Ends {
                end: s.pos.offset as usize,
            };
            visit::walk_stmt(&mut e, s);
            end = end.max(e.end);
        }
        end
    }

    /// A loop whose whole body appends one value to, or adds one value into, a fresh accumulator.
    fn accumulate_loop(&mut self, body: &[Stmt], at: usize) {
        let (Some(first), Some(second)) = (body.get(at), body.get(at + 1)) else {
            return;
        };
        let StmtKind::Bind {
            mutable: true,
            pattern:
                Pattern {
                    kind: PatternKind::Name(name),
                    ..
                },
            value,
            ..
        } = &first.kind
        else {
            return;
        };
        let StmtKind::For {
            body: loop_body, ..
        } = &second.kind
        else {
            return;
        };
        let [only] = loop_body.as_slice() else { return };
        let appends = |s: &Stmt| -> bool {
            let StmtKind::Call(e) = &s.kind else {
                return false;
            };
            let ExprKind::Call { callee, args } = &e.kind else {
                return false;
            };
            let ExprKind::Member { left, name: m } = &callee.kind else {
                return false;
            };
            args.len() == 1
                && self.syms.str(m) == "append"
                && matches!(&left.kind, ExprKind::Name(n) if n == name)
        };
        let empty_list = matches!(&value.kind, ExprKind::List(items) if items.is_empty())
            || self
                .expr_text(value)
                .is_some_and(|t| t.starts_with("List[") && t.ends_with("]()"));
        let guarded = matches!(&only.kind, StmtKind::If { binding: None, body, else_body, .. } if else_body.is_empty() && matches!(body.as_slice(), [one] if appends(one)));
        let (message, hit) = if empty_list && (appends(only) || guarded) {
            (
                "Build the list with `xs.map(fn x: ...)` or `xs.filter(fn x: ...)` instead of a loop that appends",
                true,
            )
        } else if matches!(&value.kind, ExprKind::Number(_))
            && matches!(&only.kind, StmtKind::Assign { target: AssignTarget::Name(n), compound: Some(BinaryOp::Add), .. } if n == name)
        {
            (
                "Total with `xs.sum()` or `xs.map(...).sum()` instead of a loop that adds",
                true,
            )
        } else {
            ("", false)
        };
        if hit {
            self.findings
                .push(finding("MSL124", message, self.file, first.pos));
        }
    }

    /// `for x in xs: out.append(x)` is `out.extend(xs)`.
    fn append_all(&mut self, s: &Stmt) {
        let StmtKind::For { name, iter, body } = &s.kind else {
            return;
        };
        let [only] = body.as_slice() else { return };
        let StmtKind::Call(e) = &only.kind else {
            return;
        };
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let ExprKind::Member { name: m, .. } = &callee.kind else {
            return;
        };
        let [arg] = args.as_slice() else { return };
        let element = match &arg.value.kind {
            ExprKind::Name(n) => *n == *name,
            ExprKind::Call { callee, args } if args.is_empty() => matches!(
                &callee.kind,
                ExprKind::Member { left, name: c }
                    if self.syms.str(c) == "clone"
                        && matches!(&left.kind, ExprKind::Name(n) if *n == *name)
            ),
            _ => false,
        };
        let _ = iter;
        if self.syms.str(m) == "append" && element {
            self.findings.push(finding(
                "MSL125",
                "Append every element with `out.extend(xs)` instead of a loop",
                self.file,
                s.pos,
            ));
        }
    }
}

/// The furthest end offset of any expression below a statement.
struct Ends {
    end: usize,
}

impl Visitor for Ends {
    fn expr(&mut self, e: &Expr) {
        self.end = self.end.max(e.end.offset as usize);
    }
}

/// Whether the delimiters in `text` pair up; a parenthesized expression's span leaves one side out.
fn balanced(text: &str) -> bool {
    let mut open = 0i32;
    for c in text.chars() {
        match c {
            '(' | '[' | '{' => open += 1,
            ')' | ']' | '}' => open -= 1,
            _ => {}
        }
        if open < 0 {
            return false;
        }
    }
    open == 0
}

/// A name or a field path over names: `k`, `it.sku`.
fn is_path(e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Name(_) => true,
        ExprKind::Member { left, .. } => is_path(left),
        _ => false,
    }
}

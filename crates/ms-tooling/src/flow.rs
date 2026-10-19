//! Turns one module's callable bodies into ordered significant steps: calls,
//! branches, loops, match arms, try sites, cleanup scopes, and exits.
//! Bindings and arithmetic are elided. Labels are the source lines
//! themselves, so they are exact and need no wording of their own.

use crate::facts::key_name;
use crate::tree::Node;
use ms_syntax::visit::{Visitor, walk_expr};
use ms_syntax::{Arm, Expr, ExprKind, Pos, Stmt, StmtKind, UnaryOp};
use std::collections::HashMap;

/// A call site of the inspection, as the flow needs it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Site {
    pub target: String,
    pub kind: String,
}

pub struct FlowBuilder<'a> {
    pub file: &'a str,
    pub lines: Vec<&'a str>,
    /// Call sites by id (`file#call#offset`).
    pub sites: &'a HashMap<String, Site>,
    /// Entity id to fact key.
    pub keys: &'a HashMap<String, String>,
}

/// What `statement` needs of a statement; a module-level constant's initializer
/// is a synthetic `return`.
pub struct StmtView<'a> {
    pub pos: Pos,
    pub shape: Shape,
    pub target: Option<&'a Expr>,
    pub value: Option<&'a Expr>,
    pub body: &'a [Stmt],
    pub else_body: &'a [Stmt],
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Shape {
    Branch,
    With,
    Exit,
    Return,
    Plain,
}

impl<'a> StmtView<'a> {
    pub fn of(s: &'a Stmt) -> StmtView<'a> {
        let mut view = StmtView {
            pos: s.pos,
            shape: Shape::Plain,
            target: None,
            value: None,
            body: &[],
            else_body: &[],
        };
        match &s.kind {
            StmtKind::Bind { value, .. } => view.value = Some(value),
            StmtKind::Assign { target, value, .. } => {
                if let ms_syntax::AssignTarget::Member(t) = target {
                    view.target = Some(t);
                }
                view.value = Some(value);
            }
            StmtKind::Call(e) => view.value = Some(e),
            StmtKind::Return(e) => {
                view.shape = Shape::Return;
                view.value = e.as_ref();
            }
            StmtKind::Break | StmtKind::Continue => view.shape = Shape::Exit,
            StmtKind::If { cond, body, else_body, .. } => {
                view.shape = Shape::Branch;
                (view.value, view.body, view.else_body) = (Some(cond), body, else_body);
            }
            StmtKind::While { cond, body } => {
                view.shape = Shape::Branch;
                (view.value, view.body) = (Some(cond), body);
            }
            StmtKind::For { iter, body, .. } => {
                view.shape = Shape::Branch;
                (view.value, view.body) = (Some(iter), body);
            }
            StmtKind::With { value, body, .. } => {
                view.shape = Shape::With;
                (view.value, view.body) = (Some(value), body);
            }
        }
        view
    }

    /// The synthetic `return value` of a module-level constant.
    pub fn constant(init_pos: Pos, value: &'a Expr) -> StmtView<'a> {
        StmtView { pos: init_pos, shape: Shape::Return, target: None, value: Some(value), body: &[], else_body: &[] }
    }
}

fn exit_label(s: &Stmt) -> &'static str {
    match s.kind {
        StmtKind::Continue => "continue",
        _ => "break",
    }
}

impl FlowBuilder<'_> {
    fn source(&self, pos: Pos) -> String {
        let line = pos.line as usize;
        if line < 1 || line > self.lines.len() {
            return String::new();
        }
        let text = self.lines[line - 1].trim_end_matches('\r').trim();
        text.strip_suffix(':').unwrap_or(text).trim().to_string()
    }

    /// Records where a step came from so a diff can mark it.
    fn at(&self, mut n: Node, pos: Pos) -> Node {
        n.file = self.file.to_string();
        n.line = pos.line as usize;
        n
    }

    fn node(&self, kind: &str, label: String, pos: Pos) -> Node {
        self.at(Node { kind: kind.into(), label, ..Node::default() }, pos)
    }

    pub fn body(&self, statements: &[Stmt]) -> Vec<Node> {
        statements.iter().flat_map(|s| self.statement(&StmtView::of(s), Some(s))).collect()
    }

    pub fn statement(&self, s: &StmtView, original: Option<&Stmt>) -> Vec<Node> {
        match s.shape {
            Shape::Branch => {
                let mut node = self.node("branch", self.source(s.pos), s.pos);
                node.children = self.events(s.value);
                node.children.extend(self.body(s.body));
                if !s.else_body.is_empty() {
                    node.children.push(Node {
                        kind: "branch".into(),
                        label: "else".into(),
                        children: self.body(s.else_body),
                        ..Node::default()
                    });
                }
                return vec![node];
            }
            Shape::With => {
                let mut node = self.node("with", format!("{}  [closed on exit]", self.source(s.pos)), s.pos);
                node.children = self.events(s.value);
                node.children.extend(self.body(s.body));
                return vec![node];
            }
            Shape::Exit => {
                let label = original.map_or("break", exit_label);
                return vec![self.node("exit", label.into(), s.pos)];
            }
            Shape::Return | Shape::Plain => {}
        }
        let mut out;
        match s.value {
            Some(Expr { kind: ExprKind::Match { scrutinee, arms }, .. }) => {
                out = self.events(s.target);
                out.extend(self.events(Some(scrutinee)));
                out.push(self.match_node(s.pos, arms));
            }
            _ => {
                out = self.events(s.target);
                out.extend(self.events(s.value));
            }
        }
        if s.shape == Shape::Return {
            out.push(self.node("exit", self.source(s.pos), s.pos));
        }
        out
    }

    fn match_node(&self, pos: Pos, arms: &[Arm]) -> Node {
        let mut node = self.node("match", self.source(pos), pos);
        for arm in arms {
            let mut child = self.node("arm", self.source(arm.pos), arm.pos);
            let mut steps = self.events(arm.value.as_ref());
            steps.extend(self.body(&arm.body));
            for step in steps {
                if step.kind == "exit" && child.label.ends_with(&step.label) {
                    continue;
                }
                child.children.push(step);
            }
            node.children.push(child);
        }
        node
    }

    /// Lists the calls and try markers inside one expression, outermost first.
    fn events(&self, e: Option<&Expr>) -> Vec<Node> {
        let Some(e) = e else { return Vec::new() };
        let mut collector = Events { builder: self, out: Vec::new(), pending_try: false };
        walk_expr(&mut collector, e);
        let mut out = collector.out;
        if collector.pending_try {
            out.push(self.node("try", "try".into(), e.pos));
        }
        out
    }

    fn call(&self, e: &Expr) -> Option<Node> {
        let site = self.sites.get(&format!("{}#call#{}", self.file, e.pos.offset))?;
        if site.kind == "construct" {
            return None;
        }
        if let Some(key) = self.keys.get(&site.target) {
            return Some(Node {
                kind: "call".into(),
                label: format!("call {}", key_name(key)),
                reference: key.clone(),
                ..Node::default()
            });
        }
        Some(Node { kind: "native".into(), label: format!("native {}", site.target), ..Node::default() })
    }
}

struct Events<'a, 'b> {
    builder: &'a FlowBuilder<'b>,
    out: Vec<Node>,
    pending_try: bool,
}

impl Visitor for Events<'_, '_> {
    fn expr(&mut self, x: &Expr) {
        if matches!(x.kind, ExprKind::Unary { op: UnaryOp::Try, .. }) {
            self.pending_try = true;
            return;
        }
        if !matches!(x.kind, ExprKind::Call { .. }) {
            return;
        }
        let Some(node) = self.builder.call(x) else { return };
        let mut node = self.builder.at(node, x.pos);
        if self.pending_try {
            node.label = format!("try {}", node.label);
            node.kind = "try".into();
            self.pending_try = false;
        }
        self.out.push(node);
    }
}

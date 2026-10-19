//! Ownership facts for reference-counted lowering. See `OWNERSHIP.md`.
//!
//! Manuscript keeps reference semantics, so this pass rejects nothing. It
//! classifies every use of a local binding (borrowed, retained, captured,
//! written), marks last uses, and summarizes which parameters a callee lets
//! escape. MIR uses those facts to elide count updates, move at last use and
//! decide which allocations never escape.

use crate::hir::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::collections::{HashMap, HashSet};

impl Hir<'_> {
    /// Ownership facts for every callable, with escape summaries solved to a
    /// fixpoint across the program.
    pub fn ownership(&self) -> Ownership {
        let callables = self.callables();
        let modules: HashMap<Name, ModuleHir> = self.modules().map(|m| (m.data.file, m)).collect();
        let mut summaries: HashMap<Key, Summary> = HashMap::new();
        let mut facts: HashMap<Key, CallableOwnership> = HashMap::new();
        loop {
            let mut changed = false;
            for c in &callables {
                let key = (c.module.file, c.id());
                let Some(module) = modules.get(&c.module.file) else {
                    continue;
                };
                let result = analyze(module, c, &summaries);
                let summary = result.summary(c);
                if summaries.get(&key) != Some(&summary) {
                    summaries.insert(key, summary);
                    changed = true;
                }
                facts.insert(key, result);
            }
            if !changed {
                break;
            }
        }
        Ownership { facts }
    }
}

type Key = (Name, NodeId);

/// How a callee treats its arguments.
#[derive(Clone, Default, PartialEq, Eq)]
struct Summary {
    escapes: HashMap<Name, bool>,
    self_escapes: bool,
}

/// Ownership facts of a whole program.
pub struct Ownership {
    facts: HashMap<Key, CallableOwnership>,
}

impl Ownership {
    /// Facts of one callable.
    pub fn of(&self, c: &Callable) -> Option<&CallableOwnership> {
        self.facts.get(&(c.module.file, c.id()))
    }
}

/// How a use treats the value.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum UseKind {
    /// Read transiently; the value is not kept past the use.
    Borrow,
    /// The value is stored, returned or bound: the holder keeps a count.
    Retain,
    /// A lambda snapshots the value at creation.
    Capture,
    /// The binding is reassigned (keyed by the assignment statement).
    Write,
}

/// One use of a local binding.
#[derive(Clone, Debug)]
pub struct Use {
    /// The name expression, the lambda for a capture or the statement for a write.
    pub node: NodeId,
    /// The binding's identity.
    pub binding: usize,
    /// How the value is used.
    pub kind: UseKind,
    /// No use of the binding can follow on any path from here. Uses in a loop
    /// are never last when the next iteration reads the binding.
    pub last: bool,
}

/// How a binding came to exist.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Role {
    /// A function parameter.
    Parameter,
    /// A method receiver.
    SelfValue,
    /// The injected test fixture.
    Fixture,
    /// An immutable `let` of a name.
    Let,
    /// A `var` of a name.
    Var,
    /// A destructuring or `if let` pattern variable.
    Pattern,
    /// A `for` variable.
    Loop,
    /// A `with` resource; cleanup is a use at scope exit.
    With,
    /// A match arm payload variable.
    Arm,
    /// A lambda parameter.
    LambdaParameter,
}

/// Summary of one binding.
#[derive(Clone)]
pub struct BindingFacts {
    /// The binding.
    pub binding: BindingRef,
    /// How it was introduced.
    pub role: Role,
    /// Number of uses, writes excluded.
    pub uses: usize,
    /// Some use retains the value (stores, returns, binds or passes it to an
    /// escaping parameter).
    pub retained: bool,
    /// A lambda captures it.
    pub captured: bool,
    /// It is assigned after its definition.
    pub reassigned: bool,
    /// Its initial value is a literal, constructor or lambda: a new object no
    /// other holder references.
    pub fresh: bool,
}

impl BindingFacts {
    /// The value never leaves the callable: no use retains or captures it, so
    /// a fresh allocation bound here may be scalar-replaced or stack-allocated.
    pub fn local_only(&self) -> bool {
        self.fresh && !self.retained && !self.captured && !self.reassigned
    }
}

/// Ownership facts of one callable, lambdas included.
#[derive(Default)]
pub struct CallableOwnership {
    /// Uses by (node, binding identity).
    pub uses: HashMap<(NodeId, usize), Use>,
    /// Bindings by identity.
    pub bindings: HashMap<usize, BindingFacts>,
    /// Whether each parameter's value escapes the callable, in parameter order.
    pub parameter_escapes: Vec<bool>,
    /// Whether the receiver escapes.
    pub self_escapes: bool,
}

impl CallableOwnership {
    /// The use of `binding` at `node`.
    pub fn use_at(&self, node: NodeId, binding: &BindingRef) -> Option<&Use> {
        self.uses.get(&(node, binding.uid))
    }

    fn summary(&self, c: &Callable) -> Summary {
        Summary {
            escapes: c
                .parameters
                .iter()
                .zip(&self.parameter_escapes)
                .map(|(p, e)| (p.name, *e))
                .collect(),
            self_escapes: self.self_escapes,
        }
    }
}

type Live = HashSet<usize>;

#[derive(Copy, Clone, PartialEq, Eq)]
enum Ctx {
    Borrow,
    Retain,
}

struct Pass<'a> {
    m: &'a ModuleHir,
    summaries: &'a HashMap<Key, Summary>,
    out: CallableOwnership,
    breaks: Vec<Live>,
    continues: Vec<Live>,
    /// Live set at `return`: resources of enclosing `with` blocks, plus the
    /// captured variables inside a lambda.
    exit: Live,
}

fn analyze(m: &ModuleHir, c: &Callable, summaries: &HashMap<Key, Summary>) -> CallableOwnership {
    let mut p = Pass {
        m,
        summaries,
        out: CallableOwnership::default(),
        breaks: Vec::new(),
        continues: Vec::new(),
        exit: Live::new(),
    };
    for b in &c.parameters {
        p.define(b, Role::Parameter, false);
    }
    if let Some(b) = &c.self_binding {
        p.define(b, Role::SelfValue, false);
    }
    if let Some(b) = &c.fixture {
        p.define(b, Role::Fixture, false);
    }
    match c.body() {
        Body::Block(body) => {
            p.block(body, Live::new());
        }
        Body::Expr(e) => {
            p.expr(e, Ctx::Retain, &mut Live::new());
        }
    }
    p.finish();
    let mut out = p.out;
    out.parameter_escapes = c
        .parameters
        .iter()
        .map(|b| {
            out.bindings
                .get(&b.uid)
                .is_some_and(|f| f.retained || f.captured)
        })
        .collect();
    out.self_escapes = c
        .self_binding
        .as_ref()
        .and_then(|b| out.bindings.get(&b.uid))
        .is_some_and(|f| f.retained || f.captured);
    out
}

impl<'a> Pass<'a> {
    /// Registers a binding at its definition. Backwards, uses are seen first
    /// and leave a provisional entry that the definition completes.
    fn define(&mut self, b: &BindingRef, role: Role, fresh: bool) {
        let facts = self.provisional(b);
        facts.role = role;
        facts.fresh = fresh;
    }

    fn provisional(&mut self, b: &BindingRef) -> &mut BindingFacts {
        self.out
            .bindings
            .entry(b.uid)
            .or_insert_with(|| BindingFacts {
                binding: b.clone(),
                role: Role::Pattern,
                uses: 0,
                retained: false,
                captured: false,
                reassigned: false,
                fresh: false,
            })
    }

    /// Records a use. Loop bodies are walked until the live set settles, so
    /// the last walk's entry replaces earlier ones; counts come from `finish`.
    fn record(&mut self, node: NodeId, b: &BindingRef, kind: UseKind, live: &mut Live) {
        let last = live.insert(b.uid) && kind != UseKind::Write;
        self.provisional(b);
        self.out.uses.insert(
            (node, b.uid),
            Use {
                node,
                binding: b.uid,
                kind,
                last,
            },
        );
    }

    /// Derives the per-binding summaries from the settled uses.
    fn finish(&mut self) {
        for u in self.out.uses.values() {
            let facts = self.out.bindings.get_mut(&u.binding).expect("recorded");
            match u.kind {
                UseKind::Borrow => facts.uses += 1,
                UseKind::Retain => {
                    facts.uses += 1;
                    facts.retained = true;
                }
                UseKind::Capture => {
                    facts.uses += 1;
                    facts.captured = true;
                }
                UseKind::Write => facts.reassigned = true,
            }
        }
    }

    /// Walks statements backwards from the live set after them.
    fn block(&mut self, body: &[Stmt], mut live: Live) -> Live {
        for s in body.iter().rev() {
            live = self.stmt(s, live);
        }
        live
    }

    fn stmt(&mut self, s: &Stmt, mut live: Live) -> Live {
        match &s.kind {
            StmtKind::Bind {
                mutable,
                pattern,
                value,
                ..
            } => {
                let simple = matches!(pattern.kind, PatternKind::Name(_));
                let ctx = if simple { Ctx::Retain } else { Ctx::Borrow };
                self.expr(value, ctx, &mut live);
                let fresh = self.fresh(value);
                self.pattern(pattern, if *mutable { Role::Var } else { Role::Let }, fresh);
            }
            StmtKind::Assign { target, value, .. } => {
                // Backwards, the store comes first: it ends the old value's life.
                match target {
                    AssignTarget::Name(_) => {
                        if let Some(b) = self.m.assigned(value) {
                            live.remove(&b.uid);
                            self.record(s.id, &b, UseKind::Write, &mut Live::new());
                        }
                    }
                    AssignTarget::Member(t) => self.expr(t, Ctx::Borrow, &mut live),
                }
                self.expr(value, Ctx::Retain, &mut live);
            }
            StmtKind::Call(e) => self.expr(e, Ctx::Borrow, &mut live),
            StmtKind::Return(e) => {
                live = self.exit.clone();
                if let Some(e) = e {
                    self.expr(e, Ctx::Retain, &mut live);
                }
            }
            StmtKind::Break => live = self.breaks.last().cloned().unwrap_or_default(),
            StmtKind::Continue => live = self.continues.last().cloned().unwrap_or_default(),
            StmtKind::If {
                binding,
                cond,
                body,
                else_body,
            } => {
                let mut joined = self.block(body, live.clone());
                if let Some(p) = binding {
                    self.pattern(p, Role::Pattern, false);
                }
                joined.extend(self.block(else_body, live));
                live = joined;
                self.expr(cond, Ctx::Borrow, &mut live);
            }
            StmtKind::While { cond, body } => live = self.looping(Some(cond), None, body, live),
            StmtKind::For { iter, body, .. } => {
                if let Some(b) = self.m.stmt(s).loop_binding {
                    self.define(&b, Role::Loop, false);
                }
                live = self.looping(None, Some(iter), body, live);
            }
            StmtKind::With { value, body, .. } => {
                let facts = self.m.stmt(s);
                let resource = facts.loop_binding;
                let mut inner = live;
                if let Some(b) = &resource {
                    self.define(b, Role::With, false);
                    inner.insert(b.uid);
                    self.exit.insert(b.uid);
                }
                live = self.block(body, inner);
                if let Some(b) = &resource {
                    // Defined here; cleanup at scope exit was the last use.
                    live.remove(&b.uid);
                }
                self.expr(value, Ctx::Retain, &mut live);
            }
        }
        live
    }

    /// A loop head fixpoint: the next iteration's reads keep bindings live.
    fn looping(
        &mut self,
        cond: Option<&Expr>,
        iter: Option<&Expr>,
        body: &[Stmt],
        after: Live,
    ) -> Live {
        let mut head = after.clone();
        loop {
            self.breaks.push(after.clone());
            self.continues.push(head.clone());
            let mut entry = self.block(body, head.clone());
            self.continues.pop();
            self.breaks.pop();
            entry.extend(after.iter().copied());
            if let Some(c) = cond {
                self.expr(c, Ctx::Borrow, &mut entry);
            }
            if entry.is_subset(&head) {
                head.extend(entry);
                break;
            }
            head.extend(entry);
        }
        let mut live = head;
        if let Some(i) = iter {
            self.expr(i, Ctx::Borrow, &mut live);
        }
        live
    }

    fn pattern(&mut self, p: &Pattern, role: Role, fresh: bool) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.m.pattern_binding(p) {
                    let role = match (role, b.mutable) {
                        (Role::Let | Role::Var, true) => Role::Var,
                        (Role::Let | Role::Var, false) => Role::Let,
                        (r, _) => r,
                    };
                    self.define(&b, role, fresh);
                }
            }
            PatternKind::List(items) => items
                .iter()
                .for_each(|i| self.pattern(i, Role::Pattern, false)),
            PatternKind::Record(fields) => fields
                .iter()
                .for_each(|f| self.pattern(&f.pattern, Role::Pattern, false)),
        }
    }

    /// Initializers that make a new object nothing else references.
    fn fresh(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::List(_) | ExprKind::Map(_) | ExprKind::Lambda(_) | ExprKind::Text(_) => true,
            ExprKind::Call { .. } => matches!(self.m.resolution(e), Resolution::Constructor { .. }),
            _ => false,
        }
    }

    /// Walks an expression backwards: children in reverse evaluation order.
    fn expr(&mut self, e: &Expr, ctx: Ctx, live: &mut Live) {
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Text(parts) => {
                for part in parts.iter().rev() {
                    if let TextPart::Interp(i) = part {
                        self.expr(i, Ctx::Borrow, live);
                    }
                }
            }
            ExprKind::Name(_) => {
                if let Resolution::Local(b) = self.m.resolution(e) {
                    self.record(
                        e.id,
                        &b,
                        if ctx == Ctx::Retain {
                            UseKind::Retain
                        } else {
                            UseKind::Borrow
                        },
                        live,
                    );
                }
            }
            ExprKind::Member { left, .. } => self.expr(left, Ctx::Borrow, live),
            ExprKind::Apply { left, value, .. } => match value {
                Some(v) => {
                    self.expr(v, Ctx::Borrow, live);
                    self.expr(left, Ctx::Borrow, live);
                }
                None => self.expr(left, Ctx::Borrow, live),
            },
            ExprKind::Index { left, index } => {
                self.expr(index, Ctx::Borrow, live);
                self.expr(left, Ctx::Borrow, live);
            }
            ExprKind::List(items) => {
                for i in items.iter().rev() {
                    self.expr(i, Ctx::Retain, live);
                }
            }
            ExprKind::Map(entries) => {
                for entry in entries.iter().rev() {
                    self.expr(&entry.value, Ctx::Retain, live);
                    self.expr(&entry.key, Ctx::Retain, live);
                }
            }
            ExprKind::Unary { op, operand } => {
                let inner = if *op == UnaryOp::Try {
                    ctx
                } else {
                    Ctx::Borrow
                };
                self.expr(operand, inner, live);
            }
            ExprKind::Binary { op, left, right } => {
                if matches!(op, BinaryOp::And | BinaryOp::Or) {
                    // The right operand runs on only some paths.
                    let skipped = live.clone();
                    self.expr(right, Ctx::Borrow, live);
                    live.extend(skipped);
                } else {
                    self.expr(right, Ctx::Borrow, live);
                }
                self.expr(left, Ctx::Borrow, live);
            }
            ExprKind::Lambda(l) => self.lambda(e, l, live),
            ExprKind::Call { callee, args } => self.call(e, callee, args, live),
            ExprKind::Match { scrutinee, arms } => {
                let after = live.clone();
                let mut joined = Live::new();
                for arm in arms {
                    let mut arm_live = after.clone();
                    if let Some(v) = &arm.value {
                        self.expr(v, ctx, &mut arm_live);
                    }
                    arm_live = self.block(&arm.body, arm_live);
                    for b in self.m.arm(arm).bindings.iter().flatten() {
                        self.define(b, Role::Arm, false);
                    }
                    joined.extend(arm_live);
                }
                *live = joined;
                self.expr(scrutinee, Ctx::Borrow, live);
            }
        }
    }

    fn lambda(&mut self, e: &Expr, l: &Lambda, live: &mut Live) {
        let captures = self.m.captures(e);
        let captured: Live = captures.iter().map(|b| b.uid).collect();
        for b in self.m.lambda_parameters(e) {
            self.define(&b, Role::LambdaParameter, false);
        }
        // The closure may run again, so captured variables never die in its body.
        let saved = (
            std::mem::replace(&mut self.exit, captured.clone()),
            std::mem::take(&mut self.breaks),
            std::mem::take(&mut self.continues),
        );
        self.block(&l.body, captured);
        (self.exit, self.breaks, self.continues) = saved;
        for b in &captures {
            self.record(e.id, b, UseKind::Capture, live);
        }
    }

    fn call(&mut self, e: &Expr, callee: &Expr, args: &[Argument], live: &mut Live) {
        let target = self.m.resolution(e);
        let summary = self.summary(&target);
        for a in args.iter().rev() {
            let ctx = match (&target, &summary) {
                (Resolution::Constructor { .. }, _) => Ctx::Retain,
                (Resolution::Native(_), _) => Ctx::Borrow,
                (Resolution::Function(s), None) if !s.native.as_str().is_empty() => Ctx::Borrow,
                (Resolution::Method(m), None)
                    if !m.native.as_str().is_empty() && m.native != "contract" =>
                {
                    Ctx::Borrow
                }
                (_, Some(s)) => self.argument_ctx(e, a, s),
                _ => Ctx::Retain,
            };
            self.expr(&a.value, ctx, live);
        }
        match (&target, &callee.kind) {
            (Resolution::Method(m), ExprKind::Member { left, .. }) => {
                let ctx = match &summary {
                    Some(s) if s.self_escapes => Ctx::Retain,
                    Some(_) => Ctx::Borrow,
                    None if !m.native.as_str().is_empty() && m.native != "contract" => Ctx::Borrow,
                    None => Ctx::Retain,
                };
                self.expr(left, ctx, live);
            }
            _ => self.expr(callee, Ctx::Borrow, live),
        }
    }

    fn argument_ctx(&self, call: &Expr, a: &Argument, s: &Summary) -> Ctx {
        let slots = self.m.info(call).arguments.unwrap_or_default();
        let label = slots
            .iter()
            .find(|slot| slot.pos == a.pos)
            .map(|slot| slot.name);
        match label.and_then(|l| s.escapes.get(&l)) {
            Some(false) => Ctx::Borrow,
            _ => Ctx::Retain,
        }
    }

    fn summary(&self, target: &Resolution) -> Option<&'a Summary> {
        match target {
            Resolution::Function(s) | Resolution::Constant(s) => {
                let decl = s.decl.as_ref()?;
                self.summaries.get(&(s.module, decl.id()))
            }
            Resolution::Method(m) => self.summaries.get(&(m.module, m.decl.as_ref()?.id())),
            _ => None,
        }
    }
}

//! The forward walk: classifies every use, tracks lexical borrows, and
//! reports the rules a program breaks.

use super::classify::{Class, Classifier};
use super::live::Liveness;
use super::modes::{CallModes, Key, ParamMode, Summary, call_modes};
use super::places::{Place, Step};
use super::*;
use ms_syntax::ast::*;
use ms_syntax::{Phase, Pos, visit};
use std::sync::Arc;

struct Positions(HashMap<NodeId, Pos>);

impl visit::Visitor for Positions {
    fn expr(&mut self, e: &Expr) {
        self.0.insert(e.id, e.pos);
    }
    fn stmt(&mut self, s: &Stmt) {
        self.0.insert(s.id, s.pos);
    }
}

/// The spelling of the explicit duplicate in diagnostics.
const COPY: &str = "clone";

pub struct Context<'a> {
    pub m: &'a ModuleHir,
    pub c: &'a Callable,
    pub classes: &'a Classifier,
    pub summaries: &'a HashMap<Key, Summary>,
    pub live: &'a Liveness,
    /// Lambdas known to escape, from the previous iteration.
    pub escaped: &'a HashSet<NodeId>,
}

pub struct Outcome {
    pub facts: CallableOwnership,
    pub diagnostics: Vec<Diagnostic>,
    pub summary: Summary,
    pub escaped: HashSet<NodeId>,
}

/// What an expression's value is used for.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum Demand {
    /// Ownership is taken: a binding, return, stored element, consuming argument.
    Consume,
    /// Read in place.
    Read,
    /// The value is unused.
    Discard,
}

/// Who may change a binding.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum Perm {
    Mutable,
    Immutable,
    /// Borrows from elsewhere: neither changeable nor movable.
    Borrowed,
    /// A variable inside an escaping closure's body: the closure owns a
    /// snapshot, so it is read-only there. A change is reported once, where
    /// the closure is made.
    Captured,
}

struct Meta {
    binding: BindingRef,
    role: Role,
    class: Class,
    perm: Perm,
    /// Borrowed-from places, for a borrowing binding.
    origins: Vec<Place>,
    /// The lambda a binding holds, for escape tracking.
    lambda: Option<NodeId>,
    /// A parameter, by index.
    parameter: Option<usize>,
    is_receiver: bool,
}

/// A live borrow: until `holder` is last used, its origins stay unchanged.
#[derive(Clone)]
struct Borrow {
    holder: usize,
    holder_name: Name,
    origins: Vec<(Place, bool)>,
    pos: Pos,
    why: String,
}

/// A place expression resolved to its root.
struct PlaceInfo {
    root: BindingRef,
    root_node: NodeId,
    resolved: Vec<Place>,
    projection: bool,
    text: String,
}

pub fn analyze(cx: &Context) -> Outcome {
    let mut w = Walker {
        cx,
        facts: CallableOwnership::default(),
        diags: Vec::new(),
        meta: HashMap::new(),
        active: Vec::new(),
        pending: Vec::new(),
        declared: Vec::new(),
        consumed: HashSet::new(),
        escaped: cx.escaped.clone(),
        positions: HashMap::new(),
        mutated: Vec::new(),
        captured: Vec::new(),
        hidden: 0,
    };
    w.run();
    let declared = Summary::declared(&cx.c.func);
    let summary = Summary {
        receiver: match (declared.receiver, w.receiver_consumed()) {
            (ParamMode::Borrow, true) => ParamMode::Consume,
            (mode, _) => mode,
        },
        params: declared
            .params
            .iter()
            .enumerate()
            .map(|(i, (name, mode))| {
                let consumed =
                    cx.c.parameters
                        .get(i)
                        .is_some_and(|b| w.consumed.contains(&b.uid));
                match (mode, consumed) {
                    (ParamMode::Borrow, true) => (*name, ParamMode::Consume),
                    (mode, _) => (*name, *mode),
                }
            })
            .collect(),
    };
    w.facts.parameters = summary.params.iter().map(|(_, m)| *m).collect();
    w.facts.receiver = cx.c.self_binding.as_ref().map(|_| summary.receiver);
    Outcome {
        facts: w.facts,
        diagnostics: w.diags,
        summary,
        escaped: w.escaped,
    }
}

struct Walker<'a> {
    cx: &'a Context<'a>,
    facts: CallableOwnership,
    diags: Vec<Diagnostic>,
    meta: HashMap<usize, Meta>,
    active: Vec<Borrow>,
    /// Holders whose last use ran in this statement: released at its end.
    pending: Vec<usize>,
    /// Bindings in scope, innermost last.
    declared: Vec<usize>,
    /// Parameters and the receiver that were moved from.
    consumed: HashSet<usize>,
    escaped: HashSet<NodeId>,
    /// Source positions of the callable's statements and expressions.
    positions: HashMap<NodeId, Pos>,
    /// Captured bindings a lambda body changes, innermost last.
    mutated: Vec<HashSet<usize>>,
    /// Variables each enclosing lambda captures, innermost last.
    captured: Vec<HashSet<usize>>,
    hidden: usize,
}

impl Walker<'_> {
    // ------------------------------------------------------------ setup

    fn run(&mut self) {
        let cx = self.cx;
        let c = cx.c;
        let (params, mutating): (&[ms_syntax::ast::Param], bool) =
            match (c.func.method(), c.func.func()) {
                (Some(m), _) => (&m.func.params, m.mutating),
                (None, Some(f)) => (&f.params, false),
                (None, None) => (&[], false),
            };
        for (i, b) in c.parameters.iter().enumerate() {
            let var = params.get(i).is_some_and(|p| p.mutable);
            let perm = if var { Perm::Mutable } else { Perm::Immutable };
            self.declare(b, Role::Parameter, perm, Some(i), false);
        }
        if let Some(b) = &c.self_binding {
            let perm = if mutating {
                Perm::Mutable
            } else {
                Perm::Immutable
            };
            self.declare(b, Role::SelfValue, perm, None, true);
        }
        if let Some(b) = &c.fixture {
            self.declare(b, Role::Fixture, Perm::Immutable, None, false);
        }
        let mut positions = Positions(HashMap::new());
        match c.body() {
            Body::Block(body) => visit::walk_block(&mut positions, body),
            Body::Expr(e) => visit::walk_expr(&mut positions, e),
        }
        self.positions = positions.0;
        match c.body() {
            Body::Block(body) => self.block(body),
            Body::Expr(e) => self.expr(e, Demand::Consume),
        }
    }

    fn receiver_consumed(&self) -> bool {
        self.cx
            .c
            .self_binding
            .as_ref()
            .is_some_and(|b| self.consumed.contains(&b.uid))
    }

    fn declare(
        &mut self,
        b: &BindingRef,
        role: Role,
        perm: Perm,
        parameter: Option<usize>,
        is_receiver: bool,
    ) {
        let class = self.cx.classes.class(&b.ty);
        self.meta.insert(
            b.uid,
            Meta {
                binding: b.clone(),
                role,
                class,
                perm,
                origins: Vec::new(),
                lambda: None,
                parameter,
                is_receiver,
            },
        );
        self.declared.push(b.uid);
        self.facts.bindings.insert(
            b.uid,
            BindingFacts {
                binding: b.clone(),
                role,
                class,
                owned: perm != Perm::Borrowed
                    && !matches!(
                        role,
                        Role::Parameter | Role::SelfValue | Role::LambdaParameter | Role::Fixture
                    ),
                borrows: Vec::new(),
            },
        );
    }

    /// Declares a binding that borrows from `origins`.
    fn declare_borrow(
        &mut self,
        b: &BindingRef,
        role: Role,
        origins: Vec<Place>,
        pos: Pos,
        why: &str,
    ) {
        self.declare(b, role, Perm::Borrowed, None, false);
        if let Some(f) = self.facts.bindings.get_mut(&b.uid) {
            f.owned = false;
            f.borrows = origins.clone();
        }
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.origins = origins.clone();
        }
        self.active.push(Borrow {
            holder: b.uid,
            holder_name: b.name,
            origins: origins.into_iter().map(|p| (p, false)).collect(),
            pos,
            why: why.to_string(),
        });
    }

    // ------------------------------------------------------ diagnostics

    fn error(&mut self, pos: Pos, message: impl Into<String>) {
        let message = message.into();
        if self
            .diags
            .iter()
            .any(|d| d.pos == pos && d.message == message)
        {
            return;
        }
        self.diags.push(Diagnostic {
            file: Arc::from(self.cx.m.data.file.as_str()),
            pos,
            phase: Phase::Type,
            message,
            end: None,
            fix: None,
        });
    }

    fn at(&self, node: NodeId) -> String {
        self.positions
            .get(&node)
            .map(|p| format!("{}:{}", p.line, p.column))
            .unwrap_or_else(|| "later".to_string())
    }

    // ------------------------------------------------------------ types

    fn class_of(&self, e: &Expr) -> Class {
        self.cx.classes.class(&self.cx.m.ty(e))
    }

    fn name_of(&self, uid: usize) -> Name {
        self.meta
            .get(&uid)
            .map(|m| m.binding.name)
            .unwrap_or_else(|| n("?"))
    }

    // ----------------------------------------------------- liveness

    fn is_last(&self, node: NodeId, b: &BindingRef) -> bool {
        self.cx.live.uses.get(&(node, b.uid)).is_none_or(|u| u.last)
    }

    fn next_use(&self, node: NodeId, b: &BindingRef) -> Option<NodeId> {
        self.cx.live.uses.get(&(node, b.uid)).and_then(|u| u.next)
    }

    fn record(&mut self, node: NodeId, b: &BindingRef, access: Access) {
        let last = access != Access::Write && self.is_last(node, b);
        self.facts.uses.insert(
            (node, b.uid),
            Use {
                node,
                binding: b.uid,
                access,
                last,
            },
        );
        if last && self.active.iter().any(|a| a.holder == b.uid) {
            self.pending.push(b.uid);
        }
    }

    // ------------------------------------------------------- borrows

    /// Reports a change to `places` while a live borrow covers them.
    fn check_change(
        &mut self,
        pos: Pos,
        places: &[Place],
        what: &str,
        shown: &str,
        ignore: Option<usize>,
    ) {
        let found = self.active.iter().find(|a| {
            Some(a.holder) != ignore
                && a.origins
                    .iter()
                    .any(|(o, _)| places.iter().any(|p| p.overlaps(o)))
        });
        if let Some(a) = found {
            let (holder, why, bpos) = (a.holder_name, a.why.clone(), a.pos);
            self.error(
                pos,
                format!(
                    "cannot {what} `{shown}` while `{holder}` borrows it ({why}, at {}:{}); finish using `{holder}` before this, or take an independent value with `{shown}.{COPY}()`",
                    bpos.line, bpos.column
                ),
            );
        }
    }

    /// Reports a read of `places` while a closure holds them exclusively.
    fn check_read(&mut self, pos: Pos, places: &[Place], shown: &str) {
        let found = self.active.iter().find(|a| {
            a.origins
                .iter()
                .any(|(o, exclusive)| *exclusive && places.iter().any(|p| p.overlaps(o)))
        });
        if let Some(a) = found {
            let (holder, bpos) = (a.holder_name, a.pos);
            self.error(
                pos,
                format!(
                    "cannot use `{shown}` while closure `{holder}` (made at {}:{}) changes it; call or drop the closure first, or copy the value before creating it",
                    bpos.line, bpos.column
                ),
            );
        }
    }

    fn release_pending(&mut self) {
        let pending = std::mem::take(&mut self.pending);
        self.active.retain(|a| !pending.contains(&a.holder));
    }

    fn join_active(a: Vec<Borrow>, b: Vec<Borrow>) -> Vec<Borrow> {
        let mut out = a;
        for x in b {
            if !out.iter().any(|y| y.holder == x.holder) {
                out.push(x);
            }
        }
        out
    }

    // ------------------------------------------------------- places

    fn is_place(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::Name(_) => matches!(self.cx.m.resolution(e), Resolution::Local(_)),
            ExprKind::Member { left, .. } => self.is_place(left),
            ExprKind::Index { left, .. } => self.is_place(left),
            ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => self.cx.m.info(e).native_str() == "index" && self.is_place(left),
            _ => false,
        }
    }

    fn resolve(&self, p: &Place) -> Vec<Place> {
        match self.meta.get(&p.root) {
            Some(m) if m.perm == Perm::Borrowed && !m.origins.is_empty() => {
                m.origins.iter().map(|o| o.join(&p.path)).collect()
            }
            _ => vec![p.clone()],
        }
    }

    /// Evaluates the index expressions of a place chain and returns the place.
    fn place(&mut self, e: &Expr) -> Option<(PlaceInfo, Place)> {
        match &e.kind {
            ExprKind::Name(_) => {
                let Resolution::Local(b) = self.cx.m.resolution(e) else {
                    return None;
                };
                let p = Place::local(b.uid);
                let info = PlaceInfo {
                    resolved: self.resolve(&p),
                    root: b.clone(),
                    root_node: e.id,
                    projection: false,
                    text: b.name.as_str().to_string(),
                };
                Some((info, p))
            }
            ExprKind::Member { left, name } => {
                let (mut info, p) = self.place(left)?;
                let p = p.then(Step::Field(*name));
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}.{}", info.text, name);
                Some((info, p))
            }
            ExprKind::Index { left, index } => {
                let (mut info, p) = self.place(left)?;
                self.expr(index, Demand::Read);
                let p = p.then(Step::Element);
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}[..]", info.text);
                Some((info, p))
            }
            ExprKind::Apply {
                left,
                value: Some(v),
                ..
            } => {
                let (mut info, p) = self.place(left)?;
                self.expr(v, Demand::Read);
                let p = p.then(Step::Element);
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}[..]", info.text);
                Some((info, p))
            }
            _ => None,
        }
    }

    // --------------------------------------------------- statements

    fn block(&mut self, body: &[Stmt]) {
        let mark = self.declared.len();
        for s in body {
            self.stmt(s);
            self.release_pending();
        }
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.active.retain(|a| !ended.contains(&a.holder));
    }

    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::Bind {
                mutable,
                pattern,
                value,
                ..
            } => self.bind(s, *mutable, pattern, value),
            StmtKind::Assign { target, value, .. } => self.assign(s, target, value),
            StmtKind::Call(e) => self.expr(e, Demand::Discard),
            StmtKind::Return(e) => {
                if let Some(e) = e {
                    self.expr(e, Demand::Consume);
                }
            }
            StmtKind::Break | StmtKind::Continue => {}
            StmtKind::If {
                binding,
                cond,
                body,
                else_body,
            } => self.if_stmt(s, binding.as_ref(), cond, body, else_body),
            StmtKind::While { cond, body } => {
                self.expr(cond, Demand::Read);
                self.release_pending();
                let entry = self.active.clone();
                self.block(body);
                self.active = Self::join_active(entry, std::mem::take(&mut self.active));
            }
            StmtKind::For { iter, body, .. } => self.for_stmt(s, iter, body),
            StmtKind::With { value, body, .. } => {
                self.expr(value, Demand::Consume);
                self.release_pending();
                let mark = self.declared.len();
                if let Some(b) = self.cx.m.stmt(s).loop_binding {
                    self.declare(&b, Role::With, Perm::Immutable, None, false);
                }
                self.block(body);
                let ended: Vec<usize> = self.declared.drain(mark..).collect();
                self.active.retain(|a| !ended.contains(&a.holder));
            }
        }
    }

    fn if_stmt(
        &mut self,
        s: &Stmt,
        binding: Option<&Pattern>,
        cond: &Expr,
        body: &[Stmt],
        else_body: &[Stmt],
    ) {
        let mark = self.declared.len();
        let arm_mark = self.active.len();
        match binding {
            Some(p) => {
                let scrutinee = self.scrutinee(s.id, cond);
                self.pattern_bindings(p, &scrutinee, Role::Pattern);
            }
            None => self.expr(cond, Demand::Read),
        }
        self.release_pending();
        let entry = self.active.clone();
        self.block(body);
        let then_state = std::mem::replace(&mut self.active, entry);
        // The payload bindings and their borrows end with the then-branch.
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.active.retain(|a| !ended.contains(&a.holder));
        self.active
            .truncate(self.active.len().max(arm_mark).min(self.active.len()));
        self.block(else_body);
        let else_state = std::mem::take(&mut self.active);
        let then_state: Vec<Borrow> = then_state
            .into_iter()
            .filter(|a| !ended.contains(&a.holder))
            .collect();
        self.active = Self::join_active(then_state, else_state);
    }

    fn for_stmt(&mut self, s: &Stmt, iter: &Expr, body: &[Stmt]) {
        let mark = self.declared.len();
        let source = self.scrutinee(s.id, iter);
        self.release_pending();
        // The iterable stays unchanged for the whole loop.
        let hidden = usize::MAX - self.hidden;
        self.hidden += 1;
        if !source.origins.is_empty() {
            self.active.push(Borrow {
                holder: hidden,
                holder_name: n("for"),
                origins: source.origins.iter().cloned().map(|p| (p, false)).collect(),
                pos: iter.pos,
                why: "the loop is iterating it".to_string(),
            });
        }
        if let Some(b) = self.cx.m.stmt(s).loop_binding {
            let class = self.cx.classes.class(&b.ty);
            if class == Class::Copy || source.owned {
                self.declare(&b, Role::Loop, Perm::Immutable, None, false);
                if let Some(f) = self.facts.bindings.get_mut(&b.uid) {
                    f.owned = false;
                }
            } else {
                self.declare_borrow(
                    &b,
                    Role::Loop,
                    source.origins.clone(),
                    iter.pos,
                    "loop variable",
                );
            }
        }
        let entry = self.active.clone();
        self.block(body);
        let end = std::mem::take(&mut self.active);
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.active = Self::join_active(entry, end)
            .into_iter()
            .filter(|a| a.holder != hidden && !ended.contains(&a.holder))
            .collect();
    }

    fn bind(&mut self, s: &Stmt, mutable: bool, pattern: &Pattern, value: &Expr) {
        let PatternKind::Name(_) = pattern.kind else {
            let scrutinee = self.scrutinee(s.id, value);
            self.pattern_bindings(pattern, &scrutinee, Role::Pattern);
            return;
        };
        let Some(b) = self.cx.m.pattern_binding(pattern) else {
            self.expr(value, Demand::Consume);
            return;
        };
        let role = if mutable { Role::Var } else { Role::Let };
        let class = self.cx.classes.class(&b.ty);
        if class != Class::Copy
            && let Some(origins) = self.projection_origins(value)
        {
            // Reading part of a value that stays where it is.
            self.expr(value, Demand::Read);
            if mutable {
                let text = self.expr_text(value);
                self.error(
                    pattern.pos,
                    format!(
                        "`var {}` cannot take part of another value: `{text}` stays where it is; copy it with `{text}.{COPY}()` to own it",
                        b.name
                    ),
                );
                self.declare(&b, role, Perm::Mutable, None, false);
            } else {
                self.declare_borrow(&b, role, origins, pattern.pos, "binding of a part of it");
            }
            return;
        }
        if let ExprKind::Lambda(_) = &value.kind {
            self.expr_lambda_binding(value, &b, role, mutable);
            return;
        }
        // A borrowing binding passes its borrow on to a `let`.
        if class != Class::Copy
            && !mutable
            && let ExprKind::Name(_) = &value.kind
            && let Resolution::Local(src) = self.cx.m.resolution(value)
            && self
                .meta
                .get(&src.uid)
                .is_some_and(|m| m.perm == Perm::Borrowed)
        {
            let origins = self.resolve(&Place::local(src.uid));
            self.expr(value, Demand::Read);
            self.declare_borrow(
                &b,
                role,
                origins,
                pattern.pos,
                "binding of a borrowed value",
            );
            return;
        }
        self.expr(value, Demand::Consume);
        self.declare(
            &b,
            role,
            if mutable {
                Perm::Mutable
            } else {
                Perm::Immutable
            },
            None,
            false,
        );
    }

    fn expr_lambda_binding(&mut self, value: &Expr, b: &BindingRef, role: Role, mutable: bool) {
        let ExprKind::Lambda(l) = &value.kind else {
            return;
        };
        let escaping = self.escaped.contains(&value.id);
        let origins = self.lambda(value, l, escaping);
        self.declare(
            b,
            role,
            if mutable {
                Perm::Mutable
            } else {
                Perm::Immutable
            },
            None,
            false,
        );
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.lambda = Some(value.id);
        }
        if !escaping && !origins.is_empty() {
            self.active.push(Borrow {
                holder: b.uid,
                holder_name: b.name,
                origins,
                pos: value.pos,
                why: "closure capture".to_string(),
            });
        }
    }

    fn assign(&mut self, s: &Stmt, target: &AssignTarget, value: &Expr) {
        self.expr(value, Demand::Consume);
        match target {
            AssignTarget::Name(name) => {
                let Some(b) = self.cx.m.assigned(value) else {
                    return;
                };
                self.check_store(s.pos, &b, *name);
                let places = vec![Place::local(b.uid)];
                self.check_change(s.pos, &places, "reassign", b.name.as_str(), None);
                self.mark_mutated(b.uid);
                self.record(s.id, &b, Access::Write);
                self.facts.drops_old.insert(s.id);
            }
            AssignTarget::Member(t) => {
                if let Some((info, _)) = self.place(t) {
                    self.mutate(t.pos, &info, "change");
                } else {
                    self.error(t.pos, "an assignment target must be a variable or a field path of one, like `p.x` or `rows[i].x`; `get(..)` and other calls return read-only views, so index the collection or bind the part with var first");
                }
            }
        }
    }

    /// Whole-binding reassignment needs a `var`.
    fn check_store(&mut self, pos: Pos, b: &BindingRef, name: Name) {
        let Some(m) = self.meta.get(&b.uid) else {
            return;
        };
        match m.perm {
            Perm::Mutable => {}
            Perm::Immutable if m.parameter.is_some() => self.error(
                pos,
                format!("cannot assign to parameter `{name}`: it is not declared var; write `var {name}: <Type>` in the signature and `var` at every call"),
            ),
            Perm::Immutable | Perm::Borrowed | Perm::Captured => self.error(
                pos,
                format!("cannot assign to `{name}`: it is not a var; declare it `var {name} = ...`"),
            ),
        }
    }

    // ------------------------------------------------------- mutation

    fn mark_mutated(&mut self, uid: usize) {
        for set in &mut self.mutated {
            set.insert(uid);
        }
    }

    /// A change in place through a place expression (`var` argument,
    /// mutating receiver, field assignment).
    fn mutate(&mut self, pos: Pos, info: &PlaceInfo, what: &str) {
        let root = info.root.clone();
        let (perm, role, parameter, receiver) = {
            let m = &self.meta[&root.uid];
            (m.perm, m.role, m.parameter, m.is_receiver)
        };
        let text = info.text.clone();
        match perm {
            Perm::Mutable | Perm::Captured => {}
            Perm::Borrowed => {
                let from = self
                    .meta
                    .get(&root.uid)
                    .and_then(|m| m.origins.first())
                    .map(|o| self.name_of(o.root).to_string())
                    .unwrap_or_else(|| "another value".to_string());
                self.error(
                    pos,
                    format!(
                        "cannot {what} `{text}`: `{}` only borrows from `{from}`; copy it first with `var {} = {}.{COPY}()`",
                        root.name, root.name, root.name
                    ),
                );
            }
            Perm::Immutable if receiver => self.error(
                pos,
                format!("cannot {what} `{text}`: this method does not change its receiver; declare it `var fn` to allow that"),
            ),
            Perm::Immutable if parameter.is_some() => self.error(
                pos,
                format!(
                    "cannot {what} `{text}`: parameter `{}` is not declared var; write `var {}: <Type>` in the signature and pass `var` at every call",
                    root.name, root.name
                ),
            ),
            Perm::Immutable => {
                let _ = role;
                self.error(
                    pos,
                    format!(
                        "cannot {what} `{text}`: `{}` is declared with let, which is immutable including its contents; declare it `var {}` to change it",
                        root.name, root.name
                    ),
                );
            }
        }
        self.check_change(pos, &info.resolved, what, &text, Some(root.uid));
        self.mark_mutated(root.uid);
        self.record(info.root_node, &root, Access::Mutate);
    }

    /// A read through a place.
    fn read_place(&mut self, pos: Pos, info: &PlaceInfo) {
        let text = info.text.clone();
        self.check_read(pos, &info.resolved, &text);
        let root = info.root.clone();
        self.record(info.root_node, &root, Access::Borrow);
    }

    // ------------------------------------------------------ patterns

    /// Evaluates a matched or destructured value and says how its parts are held.
    fn scrutinee(&mut self, stmt: NodeId, e: &Expr) -> Scrutinee {
        if self.is_place(e) {
            let class = self.class_of(e);
            let whole = matches!(e.kind, ExprKind::Name(_));
            if whole
                && class != Class::Copy
                && let Resolution::Local(b) = self.cx.m.resolution(e)
                && self.meta.get(&b.uid).is_some_and(|m| {
                    m.perm != Perm::Borrowed
                        && m.role != Role::Parameter
                        && m.role != Role::SelfValue
                        || self.is_consumable_param(&b)
                })
                && self.is_last(e.id, &b)
            {
                self.expr(e, Demand::Consume);
                self.facts.consumed_scrutinees.insert(stmt);
                return Scrutinee {
                    owned: true,
                    origins: Vec::new(),
                };
            }
            let Some((info, _)) = self.place(e) else {
                return Scrutinee {
                    owned: true,
                    origins: Vec::new(),
                };
            };
            self.read_place(e.pos, &info);
            return Scrutinee {
                owned: false,
                origins: info.resolved,
            };
        }
        if let Some(origins) = self.projection_origins(e) {
            self.expr(e, Demand::Read);
            return Scrutinee {
                owned: false,
                origins,
            };
        }
        self.expr(e, Demand::Consume);
        Scrutinee {
            owned: true,
            origins: Vec::new(),
        }
    }

    fn is_consumable_param(&self, b: &BindingRef) -> bool {
        self.meta
            .get(&b.uid)
            .is_some_and(|m| m.perm == Perm::Immutable && m.parameter.is_some())
    }

    fn pattern_bindings(&mut self, p: &Pattern, source: &Scrutinee, role: Role) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.cx.m.pattern_binding(p) {
                    self.payload(&b, source, role, p.pos);
                }
            }
            PatternKind::List(items) => items
                .iter()
                .for_each(|i| self.pattern_bindings(i, source, role)),
            PatternKind::Record(fields) => fields
                .iter()
                .for_each(|f| self.pattern_bindings(&f.pattern, source, role)),
        }
    }

    fn payload(&mut self, b: &BindingRef, source: &Scrutinee, role: Role, pos: Pos) {
        let class = self.cx.classes.class(&b.ty);
        if class == Class::Copy || source.owned {
            self.declare(b, role, Perm::Immutable, None, false);
        } else {
            self.declare_borrow(b, role, source.origins.clone(), pos, "pattern binding");
        }
    }

    // --------------------------------------------------- expressions

    /// Origins of an expression that reads part of a value in place: a
    /// projection or a native accessor on a place.
    fn projection_origins(&mut self, e: &Expr) -> Option<Vec<Place>> {
        if self.is_place(e) {
            if matches!(e.kind, ExprKind::Name(_)) {
                return None;
            }
            // Resolve without evaluating index expressions twice.
            return self.pure_places(e);
        }
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let modes = call_modes(self.cx.m, e, args, self.cx.summaries);
        if !modes.accessor {
            return None;
        }
        let ExprKind::Member { left, .. } = &callee.kind else {
            return None;
        };
        if !self.is_place(left) {
            return None;
        }
        let origins = self.pure_places(left)?;
        Some(origins.iter().map(|o| o.then(Step::Element)).collect())
    }

    /// Places an accessor call reads in place, without evaluating it.
    fn pure_origins(&self, e: &Expr) -> Option<Vec<Place>> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        if !call_modes(self.cx.m, e, args, self.cx.summaries).accessor {
            return None;
        }
        let ExprKind::Member { left, .. } = &callee.kind else {
            return None;
        };
        let origins = self.pure_places(left)?;
        Some(origins.iter().map(|o| o.then(Step::Element)).collect())
    }

    /// The resolved places of a place chain without evaluating it.
    fn pure_places(&self, e: &Expr) -> Option<Vec<Place>> {
        match &e.kind {
            ExprKind::Name(_) => {
                let Resolution::Local(b) = self.cx.m.resolution(e) else {
                    return None;
                };
                Some(self.resolve(&Place::local(b.uid)))
            }
            ExprKind::Member { left, name } => Some(
                self.pure_places(left)?
                    .iter()
                    .map(|p| p.then(Step::Field(*name)))
                    .collect(),
            ),
            ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => Some(
                self.pure_places(left)?
                    .iter()
                    .map(|p| p.then(Step::Element))
                    .collect(),
            ),
            _ => None,
        }
    }

    fn expr_text(&self, e: &Expr) -> String {
        match &e.kind {
            ExprKind::Name(n) => n.as_str().to_string(),
            ExprKind::Member { left, name } => format!("{}.{}", self.expr_text(left), name),
            ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => {
                format!("{}[..]", self.expr_text(left))
            }
            ExprKind::Call { callee, .. } => format!("{}(..)", self.expr_text(callee)),
            _ => "this value".to_string(),
        }
    }

    fn expr(&mut self, e: &Expr, d: Demand) {
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Text(parts) => {
                for part in parts {
                    if let TextPart::Interp(i) = part {
                        self.expr(i, Demand::Read);
                    }
                }
            }
            ExprKind::Name(_) => {
                if let Resolution::Local(b) = self.cx.m.resolution(e) {
                    self.use_local(e, &b, d);
                }
            }
            ExprKind::Member { .. } | ExprKind::Index { .. } | ExprKind::Apply { .. } => {
                self.projection(e, d)
            }
            ExprKind::List(items) => items.iter().for_each(|i| self.expr(i, Demand::Consume)),
            ExprKind::Map(entries) => {
                for entry in entries {
                    self.expr(&entry.key, Demand::Consume);
                    self.expr(&entry.value, Demand::Consume);
                }
            }
            ExprKind::Unary { op, operand } => {
                let inner = if *op == UnaryOp::Try { d } else { Demand::Read };
                self.expr(operand, inner);
            }
            ExprKind::Binary { left, right, .. } => {
                self.expr(left, Demand::Read);
                self.expr(right, Demand::Read);
            }
            ExprKind::Lambda(l) => {
                let escaping = d == Demand::Consume || self.escaped.contains(&e.id);
                self.lambda(e, l, escaping);
            }
            ExprKind::Call { callee, args } => self.call(e, callee, args, d),
            ExprKind::Match { scrutinee, arms } => self.match_expr(e, scrutinee, arms, d),
        }
        self.temporary(e, d);
    }

    /// An owned value nobody consumed is dropped at the end of the statement.
    fn temporary(&mut self, e: &Expr, d: Demand) {
        if d == Demand::Consume || self.is_place(e) || matches!(e.kind, ExprKind::Name(_)) {
            return;
        }
        if matches!(
            e.kind,
            ExprKind::Call { .. }
                | ExprKind::List(_)
                | ExprKind::Map(_)
                | ExprKind::Match { .. }
                | ExprKind::Lambda(_)
                | ExprKind::Binary { .. }
        ) && self.class_of(e) != Class::Copy
        {
            self.facts.temporaries.insert(e.id);
        }
    }

    fn use_local(&mut self, e: &Expr, b: &BindingRef, d: Demand) {
        let Some(class) = self.meta.get(&b.uid).map(|m| m.class) else {
            return;
        };
        let place = Place::local(b.uid);
        let resolved = self.resolve(&place);
        if d != Demand::Consume || class == Class::Copy {
            self.check_read(e.pos, &resolved, b.name.as_str());
            let access = if d == Demand::Consume {
                Access::Copy
            } else {
                Access::Borrow
            };
            self.record(e.id, b, access);
            return;
        }
        self.move_out(e, b, &resolved);
    }

    /// Moves a whole binding out: it must own its value and never use it again.
    fn move_out(&mut self, e: &Expr, b: &BindingRef, resolved: &[Place]) {
        let (perm, role, parameter, lambda, receiver) = {
            let m = &self.meta[&b.uid];
            (m.perm, m.role, m.parameter, m.lambda, m.is_receiver)
        };
        let name = b.name;
        let var_param = parameter.is_some() && perm == Perm::Mutable;
        if self.captured.iter().any(|c| c.contains(&b.uid)) && perm != Perm::Captured {
            self.error(
                e.pos,
                format!("this closure would move `{name}` out of the variable it captured, but a closure can run more than once; return `{name}.{COPY}()` instead"),
            );
            self.record(e.id, b, Access::Move);
            return;
        }
        if perm == Perm::Borrowed || perm == Perm::Captured {
            self.error(
                e.pos,
                format!("cannot move `{name}` out: it only borrows its value ({}); use `{name}.{COPY}()` to get an owned copy", role_text(role, perm)),
            );
            self.record(e.id, b, Access::Move);
            return;
        } else if var_param || (receiver && perm == Perm::Mutable) {
            self.error(
                e.pos,
                format!("cannot move `{name}` out of the function: the caller keeps ownership of a var parameter; return `{name}.{COPY}()` or change the value in place"),
            );
        } else if !self.is_last(e.id, b) {
            let later = self
                .next_use(e.id, b)
                .map(|n| format!(" at {}", self.at(n)))
                .unwrap_or_default();
            self.error(
                e.pos,
                format!("`{name}` is moved here but used again{later}; a value has one owner, so pass `{name}.{COPY}()` to keep the original, or move it only at its last use"),
            );
        }
        self.check_change(e.pos, resolved, "move", name.as_str(), Some(b.uid));
        self.mark_mutated(b.uid);
        self.record(e.id, b, Access::Move);
        if parameter.is_some() || receiver {
            self.consumed.insert(b.uid);
        }
        if let Some(l) = lambda {
            self.escaped.insert(l);
        }
    }

    fn projection(&mut self, e: &Expr, d: Demand) {
        if !self.is_place(e) {
            // A part of a computed value.
            match &e.kind {
                ExprKind::Member { left, .. } => self.expr(
                    left,
                    if d == Demand::Consume {
                        Demand::Consume
                    } else {
                        Demand::Read
                    },
                ),
                ExprKind::Index { left, index } => {
                    self.expr(
                        left,
                        if d == Demand::Consume {
                            Demand::Consume
                        } else {
                            Demand::Read
                        },
                    );
                    self.expr(index, Demand::Read);
                }
                ExprKind::Apply { left, value, .. } => {
                    self.expr(left, Demand::Read);
                    if let Some(v) = value {
                        self.expr(v, Demand::Read);
                    }
                }
                _ => {}
            }
            return;
        }
        let Some((info, _)) = self.place(e) else {
            return;
        };
        let class = self.class_of(e);
        if d == Demand::Consume && class != Class::Copy {
            self.error(
                e.pos,
                format!(
                    "cannot move `{0}` out of `{1}`: only a whole variable can move; take an owned copy with `{0}.{COPY}()`",
                    info.text, info.root.name
                ),
            );
        }
        self.read_place(e.pos, &info);
    }

    // ---------------------------------------------------------- calls

    fn call(&mut self, e: &Expr, callee: &Expr, args: &[Argument], d: Demand) {
        let cx = self.cx;
        let modes = call_modes(cx.m, e, args, cx.summaries);
        self.facts.calls.insert(e.id, modes.clone());
        let name = self.call_name(callee);
        let receiver_expr = match (&callee.kind, cx.m.resolution(e)) {
            (ExprKind::Member { left, .. }, Resolution::Method(_)) => Some(&**left),
            _ => None,
        };
        // Argument markers: `var` exactly where the callee changes the argument.
        let param_names: Vec<Name> =
            cx.m.info(e)
                .arguments
                .unwrap_or_default()
                .iter()
                .map(|s| s.name)
                .collect();
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            let param = param_names.get(i).copied().unwrap_or_else(|| n("?"));
            match (mode, a.mutable) {
                (ParamMode::Mutate, false) => self.error(
                    a.value.pos,
                    format!("parameter `{param}` of `{name}` is declared var, so the call must say so; write `var {}`", self.expr_text(&a.value)),
                ),
                (ParamMode::Borrow | ParamMode::Consume, true) => self.error(
                    a.value.pos,
                    format!("`{name}` does not change its parameter `{param}`; remove `var` from the argument"),
                ),
                _ => {}
            }
        }
        // Evaluate in order. What an operand keeps hold of for the whole call
        // is checked against the others afterwards.
        let mut operands: Vec<(String, Vec<(Place, bool)>)> = Vec::new();
        let reported = self.diags.len();
        if let Some(r) = receiver_expr {
            let mode = modes.receiver.unwrap_or(ParamMode::Borrow);
            let held = self.held(r, mode);
            self.receiver(r, mode);
            operands.push((format!("the receiver `{}`", self.expr_text(r)), held));
        } else {
            self.expr(callee, Demand::Read);
        }
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            let mut held = self.held(&a.value, mode);
            held.extend(self.argument(a, mode, &modes));
            operands.push((format!("argument `{}`", self.expr_text(&a.value)), held));
        }
        // An operand that already failed its own check is not reported twice.
        if self.diags.len() == reported {
            self.check_overlap(e.pos, &name, &operands);
        }
        // Results.
        if modes.returns_receiver && d != Demand::Discard {
            let recv = receiver_expr.map(|r| self.expr_text(r)).unwrap_or_default();
            self.error(
                e.pos,
                format!("`{name}` changes `{recv}` in place and its result cannot be used, because the collection has one owner; call it as a statement and keep using `{recv}`"),
            );
        }
        if modes.accessor && d == Demand::Consume && self.class_of(e) != Class::Copy {
            let recv = receiver_expr.map(|r| self.expr_text(r)).unwrap_or_default();
            self.error(
                e.pos,
                format!("`{name}` borrows its result from `{recv}`; use it in place, or take an owned copy with `{name}(..).{COPY}()`"),
            );
        }
    }

    fn call_name(&self, callee: &Expr) -> String {
        match &callee.kind {
            ExprKind::Name(n) => n.as_str().to_string(),
            ExprKind::Member { name, .. } => name.as_str().to_string(),
            _ => "the callee".to_string(),
        }
    }

    /// The places an operand keeps hold of while the call runs: a variable
    /// changed or moved by it, or a value that is read in place. Copies and
    /// computed values are finished before the call starts.
    fn held(&self, e: &Expr, mode: ParamMode) -> Vec<(Place, bool)> {
        if matches!(e.kind, ExprKind::Lambda(_)) {
            return Vec::new();
        }
        let write = mode != ParamMode::Borrow;
        if mode != ParamMode::Mutate && self.class_of(e) == Class::Copy {
            return Vec::new();
        }
        let places = if self.is_place(e) {
            self.pure_places(e)
        } else {
            self.pure_origins(e)
        };
        places
            .unwrap_or_default()
            .into_iter()
            .map(|p| (p, write))
            .collect()
    }

    fn receiver(&mut self, r: &Expr, mode: ParamMode) {
        match mode {
            ParamMode::Borrow => self.expr(r, Demand::Read),
            ParamMode::Consume => self.expr(r, Demand::Consume),
            ParamMode::Mutate => {
                if self.is_place(r) {
                    if let Some((info, _)) = self.place(r) {
                        self.mutate(r.pos, &info, "change");
                    }
                } else {
                    // A temporary changed in place: nothing keeps it.
                    self.expr(r, Demand::Read);
                }
            }
        }
    }

    /// Evaluates an argument; returns what a closure argument holds.
    fn argument(&mut self, a: &Argument, mode: ParamMode, modes: &CallModes) -> Vec<(Place, bool)> {
        match mode {
            ParamMode::Borrow => {
                if let ExprKind::Lambda(l) = &a.value.kind {
                    // Callbacks the callee runs and drops do not escape.
                    let escaping = !modes.callbacks_borrowed || self.escaped.contains(&a.value.id);
                    return self.lambda(&a.value, l, escaping);
                }
                self.expr(&a.value, Demand::Read);
            }
            ParamMode::Consume => self.expr(&a.value, Demand::Consume),
            ParamMode::Mutate => {
                if self.is_place(&a.value) {
                    if let Some((info, _)) = self.place(&a.value) {
                        self.mutate(a.value.pos, &info, "change");
                    }
                } else {
                    self.error(
                        a.value.pos,
                        "a var argument must be a variable or a field of one, not a computed value; bind the value to a var first",
                    );
                    self.expr(&a.value, Demand::Read);
                }
            }
        }
        Vec::new()
    }

    /// A changed place may not overlap another operand of the same call.
    fn check_overlap(&mut self, pos: Pos, name: &str, operands: &[(String, Vec<(Place, bool)>)]) {
        for (i, (label, log)) in operands.iter().enumerate() {
            for (place, write) in log {
                if !*write {
                    continue;
                }
                let clash = operands.iter().enumerate().find(|(j, (_, other))| {
                    *j != i && other.iter().any(|(q, _)| q.overlaps(place))
                });
                if let Some((_, (other, _))) = clash {
                    self.error(
                        pos,
                        format!("{label} of `{name}` is changed in place but overlaps {other}; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first"),
                    );
                    return;
                }
            }
        }
    }

    // ---------------------------------------------------------- match

    fn match_expr(&mut self, e: &Expr, scrutinee: &Expr, arms: &[Arm], d: Demand) {
        let source = self.scrutinee(e.id, scrutinee);
        self.release_pending();
        let entry = self.active.clone();
        let mut joined: Vec<Borrow> = Vec::new();
        for arm in arms {
            self.active = entry.clone();
            let mark = self.declared.len();
            for b in self.cx.m.arm(arm).bindings.iter().flatten() {
                self.payload(b, &source, Role::Arm, arm.pos);
            }
            self.block(&arm.body);
            // `block` ended its own declarations; the arm bindings end here.
            if let Some(v) = &arm.value {
                self.expr(v, d);
                self.release_pending();
            }
            let ended: Vec<usize> = self.declared.drain(mark..).collect();
            let end: Vec<Borrow> = std::mem::take(&mut self.active)
                .into_iter()
                .filter(|a| !ended.contains(&a.holder))
                .collect();
            joined = Self::join_active(joined, end);
        }
        self.active = Self::join_active(entry, joined);
    }

    // --------------------------------------------------------- lambda

    /// Walks a lambda: returns the places it holds while it lives (empty when
    /// it escapes, because it then owns its captures).
    fn lambda(&mut self, e: &Expr, l: &Lambda, escaping: bool) -> Vec<(Place, bool)> {
        let m = self.cx.m;
        let captures = m.captures(e);
        if escaping {
            self.escaped.insert(e.id);
        }
        let params = m.lambda_parameters(e);
        // The body, in its own scope.
        let saved_active = if escaping {
            Some(std::mem::take(&mut self.active))
        } else {
            None
        };
        let saved_meta: Vec<(usize, Perm)> = captures
            .iter()
            .filter_map(|b| self.meta.get(&b.uid).map(|m| (b.uid, m.perm)))
            .collect();
        if escaping {
            // The closure holds its own snapshot: read-only inside.
            for (uid, _) in &saved_meta {
                if let Some(m) = self.meta.get_mut(uid) {
                    m.perm = Perm::Captured;
                }
            }
        }
        self.mutated.push(HashSet::new());
        self.captured.push(captures.iter().map(|b| b.uid).collect());
        let mark = self.declared.len();
        for (i, b) in params.iter().enumerate() {
            let var = l.params.get(i).is_some_and(|p| p.mutable);
            self.declare(
                b,
                Role::LambdaParameter,
                if var { Perm::Mutable } else { Perm::Immutable },
                None,
                false,
            );
        }
        self.block(&l.body);
        self.declared.truncate(mark);
        self.captured.pop();
        let mutated = self.mutated.pop().unwrap_or_default();
        for (uid, perm) in saved_meta {
            if let Some(m) = self.meta.get_mut(&uid) {
                m.perm = perm;
            }
        }
        if let Some(a) = saved_active {
            self.active = a;
        }
        // Propagate changes to captured variables to enclosing lambdas.
        for uid in &mutated {
            self.mark_mutated(*uid);
        }
        // The capture itself.
        let mut held: Vec<(Place, bool)> = Vec::new();
        let mut facts = Vec::new();
        for b in &captures {
            let changed = mutated.contains(&b.uid);
            let class = self
                .meta
                .get(&b.uid)
                .map(|m| m.class)
                .unwrap_or(Class::Move);
            if escaping {
                if changed {
                    self.error(
                        e.pos,
                        format!("this closure changes captured `{0}`, so it cannot be returned, stored or passed to a consuming parameter; keep the closure local, or have it return a new value instead of changing `{0}`", b.name),
                    );
                }
                if class == Class::Copy {
                    self.record(e.id, b, Access::Copy);
                    facts.push((b.uid, CaptureMode::Copy));
                } else {
                    let resolved = self.resolve(&Place::local(b.uid));
                    self.capture_move(e, b, &resolved);
                    facts.push((b.uid, CaptureMode::Move));
                }
            } else {
                let place = Place::local(b.uid);
                let resolved = self.resolve(&place);
                if changed {
                    let info = PlaceInfo {
                        root: b.clone(),
                        root_node: e.id,
                        resolved: resolved.clone(),
                        projection: false,
                        text: b.name.as_str().to_string(),
                    };
                    self.mutate(e.pos, &info, "change");
                    facts.push((b.uid, CaptureMode::BorrowMut));
                } else {
                    self.check_read(e.pos, &resolved, b.name.as_str());
                    self.record(e.id, b, Access::Borrow);
                    facts.push((b.uid, CaptureMode::Borrow));
                }
                for p in resolved {
                    held.push((p, changed));
                }
            }
        }
        self.facts.lambdas.insert(
            e.id,
            LambdaFacts {
                escaping,
                captures: facts,
            },
        );
        held
    }

    fn capture_move(&mut self, e: &Expr, b: &BindingRef, resolved: &[Place]) {
        let perm = self.meta[&b.uid].perm;
        let name = b.name;
        if perm == Perm::Borrowed || perm == Perm::Captured {
            self.error(
                e.pos,
                format!("this closure outlives the statement but captures `{name}`, which only borrows its value; capture `{name}.{COPY}()` instead"),
            );
        } else if !self.is_last(e.id, b) {
            let later = self
                .next_use(e.id, b)
                .map(|n| format!(" at {}", self.at(n)))
                .unwrap_or_default();
            self.error(
                e.pos,
                format!("this closure outlives the statement, so it takes `{name}` with it, but `{name}` is used again{later}; capture `{name}.{COPY}()` to keep the original"),
            );
        }
        self.check_change(e.pos, resolved, "move", name.as_str(), Some(b.uid));
        self.record(e.id, b, Access::Move);
        let (parameter, receiver) = {
            let m = &self.meta[&b.uid];
            (m.parameter, m.is_receiver)
        };
        if parameter.is_some() || receiver {
            self.consumed.insert(b.uid);
        }
        if let Some(l) = self.meta[&b.uid].lambda {
            self.escaped.insert(l);
        }
    }
}

/// How the parts of a matched or destructured value are held.
struct Scrutinee {
    /// The parts belong to the pattern bindings.
    owned: bool,
    /// Otherwise the places they borrow from.
    origins: Vec<Place>,
}

fn role_text(role: Role, perm: Perm) -> &'static str {
    if perm == Perm::Captured {
        return "a variable captured by the closure";
    }
    match role {
        Role::Arm => "a match payload",
        Role::Loop => "a loop variable",
        Role::Pattern => "a pattern variable",
        _ => "a borrow",
    }
}

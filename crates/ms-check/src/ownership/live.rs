//! Backward liveness of local bindings: which uses are the last on every path.
//!
//! The ownership walk asks this oracle whether a move is the final use of a
//! binding. A use is **last** when no later use of the same value can run:
//! reassigning a binding ends the old value's life, a loop keeps reads alive
//! until the final iteration, and a scope-closed resource and a closure's captured
//! variables stay live to the end of their scope.
//!
//! Liveness is kept per place: a binding and a path of fields (`b`, `b.items`). `uses` answers for
//! the whole binding (is any part of it used later), and `places` answers for the place a
//! field-path read names (is it, a prefix of it or an extension of it used later).

use crate::fxmap::HashMap;
use crate::hir::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::rc::Rc;

/// Liveness of one use.
#[derive(Copy, Clone, Debug)]
pub struct UseLive {
    /// No later use of the value can run.
    pub last: bool,
    /// The earliest later use, for diagnostics.
    pub next: Option<NodeId>,
}

/// Per-use liveness of one callable, keyed by (node, binding identity).
#[derive(Default)]
pub struct Liveness {
    /// Name uses, and lambda creations for captures.
    pub uses: HashMap<(NodeId, usize), UseLive>,
    /// Field-path reads (`b.f.g`, by the outermost member expression and the root binding): no
    /// later use of the place, a prefix of it or an extension of it can run.
    pub places: HashMap<(NodeId, usize), UseLive>,
    /// Lambda creations (node, captured binding) after which the binding is assigned again on
    /// some path, with the node of the assigned value. A store ends the old value's life, so
    /// `uses` calls the capture the last use, yet a closure that copied the value in goes stale.
    pub assigned_after: HashMap<(NodeId, usize), NodeId>,
}

/// Offset added to a binding identity to key "assigned again later" in the live set, apart from
/// the uses of the binding itself.
const STORED: usize = 1 << 62;

/// The fields below a binding; `None` is the binding itself, so the common place needs no
/// allocation and copying a path is a count, not a copy.
type Path = Option<Rc<[Name]>>;

fn path_of(fields: Vec<Name>) -> Path {
    (!fields.is_empty()).then(|| fields.into())
}

fn fields(path: &Path) -> &[Name] {
    path.as_deref().unwrap_or(&[])
}

struct Entry {
    uid: usize,
    path: Path,
    node: NodeId,
}

/// Places live after a point, each with its earliest later use, in one array sorted by binding so
/// a query or a kill touches only the places of one binding, however many others are live (a
/// function with N bindings used after their definitions otherwise paid N per query, N^2 in all),
/// and copying the set (at every branch, loop pass and `return`) is one allocation.
#[derive(Clone, Default)]
struct Live {
    entries: Vec<Entry>,
}

impl Clone for Entry {
    fn clone(&self) -> Entry {
        Entry {
            uid: self.uid,
            path: self.path.clone(),
            node: self.node,
        }
    }
}

impl Live {
    fn new() -> Live {
        Live::default()
    }

    /// Places in all, so the loop fixpoint can tell whether a join added any.
    fn len(&self) -> usize {
        self.entries.len()
    }

    /// The entries of `uid`.
    fn group(&self, uid: usize) -> std::ops::Range<usize> {
        let start = self.entries.partition_point(|e| e.uid < uid);
        let len = self.entries[start..].partition_point(|e| e.uid == uid);
        start..start + len
    }

    fn get(&self, uid: usize, path: &[Name]) -> Option<NodeId> {
        self.entries[self.group(uid)]
            .iter()
            .find(|e| fields(&e.path) == path)
            .map(|e| e.node)
    }

    /// Records the place with `node`, replacing its earlier use.
    fn insert(&mut self, uid: usize, path: Path, node: NodeId) {
        let group = self.group(uid);
        match self.entries[group.clone()]
            .iter_mut()
            .find(|e| fields(&e.path) == fields(&path))
        {
            Some(known) => known.node = node,
            None => self.entries.insert(group.end, Entry { uid, path, node }),
        }
    }

    /// Keeps the earlier of two uses of a place.
    fn merge(&mut self, uid: usize, path: &Path, node: NodeId) {
        let group = self.group(uid);
        match self.entries[group.clone()]
            .iter_mut()
            .find(|e| fields(&e.path) == fields(path))
        {
            Some(known) => {
                if node.0 < known.node.0 {
                    known.node = node;
                }
            }
            None => self.entries.insert(
                group.end,
                Entry {
                    uid,
                    path: path.clone(),
                    node,
                },
            ),
        }
    }

    /// Drops every place of `uid` that `drop` accepts.
    fn remove_where(&mut self, uid: usize, drop: impl Fn(&[Name]) -> bool) {
        let group = self.group(uid);
        let mut keep = group.start;
        for at in group.clone() {
            if !drop(fields(&self.entries[at].path)) {
                self.entries.swap(keep, at);
                keep += 1;
            }
        }
        self.entries.drain(keep..group.end);
    }
}

impl FromIterator<(usize, Vec<Name>, NodeId)> for Live {
    fn from_iter<I: IntoIterator<Item = (usize, Vec<Name>, NodeId)>>(iter: I) -> Live {
        let mut out = Live::new();
        for (uid, path, node) in iter {
            out.insert(uid, path_of(path), node);
        }
        out
    }
}

/// Whether one path is a prefix of the other.
fn related(a: &[Name], b: &[Name]) -> bool {
    a.iter().zip(b).all(|(x, y)| x == y)
}

/// Marks the last step of a key as a store: the place is overwritten there, not read.
fn store_step() -> Name {
    n("=")
}

/// The earliest later use of `uid` at a place related to `path`. A store counts for the whole
/// binding (`path` empty: assigning a field uses the binding) but not for a place: overwriting
/// `b.f` does not read the `b.f` an earlier move took.
fn next_use(live: &Live, uid: usize, path: &[Name]) -> Option<NodeId> {
    let store = store_step();
    live.entries[live.group(uid)]
        .iter()
        .filter(|e| {
            let p = fields(&e.path);
            related(p, path) && (path.is_empty() || p.last() != Some(&store))
        })
        .map(|e| e.node)
        .min()
}

/// The binding and fields a chain of member reads names, with the root name's node.
fn field_chain<'a>(m: &ModuleHir, e: &'a Expr) -> Option<(&'a Expr, BindingRef, Vec<Name>)> {
    let mut path = Vec::new();
    let mut at = e;
    while let ExprKind::Member { left, name } = &at.kind {
        path.push(*name);
        at = left;
    }
    path.reverse();
    match (&at.kind, m.resolution(at)) {
        (ExprKind::Name(_), Resolution::Local(b)) if !path.is_empty() => Some((at, b, path)),
        _ => None,
    }
}

/// Whether the call is an index assignment `place[key] = value` whose key is a variable or
/// a field path of one, which the parser writes as `place.[]=(key, value)`. Such a key is
/// consumed at the store, after the value ran. Any other key expression runs before the
/// value, in source order, like an argument.
pub(super) fn is_index_store(callee: &Expr, args: &[ms_syntax::ast::Argument]) -> bool {
    args.len() == 2
        && matches!(&callee.kind, ExprKind::Member { name, .. }
            if ms_syntax::Names::global().str(*name) == ms_syntax::parser::INDEX_SET)
        && is_place(&args[0].value)
}

/// A name or a chain of member reads on one.
fn is_place(e: &Expr) -> bool {
    let mut at = e;
    while let ExprKind::Member { left, .. } = &at.kind {
        at = left;
    }
    matches!(at.kind, ExprKind::Name(_))
}

fn join(into: &mut Live, from: &Live) {
    if into.entries.is_empty() {
        into.entries.clone_from(&from.entries);
        return;
    }
    for e in &from.entries {
        into.merge(e.uid, &e.path, e.node);
    }
}

/// Computes liveness of a callable body.
pub fn liveness(m: &ModuleHir, c: &Callable) -> Liveness {
    let mut p = Pass {
        m,
        out: Liveness::default(),
        breaks: Vec::new(),
        continues: Vec::new(),
        exit: Live::new(),
    };
    match c.body() {
        Body::Block(body) => {
            p.block(body, Live::new());
        }
        Body::Expr(e) => p.expr(e, &mut Live::new()),
    }
    p.out
}

struct Pass<'a> {
    m: &'a ModuleHir,
    out: Liveness,
    breaks: Vec<Live>,
    continues: Vec<Live>,
    /// Live at `return`: resources of enclosing scopes, and the captured
    /// variables inside a lambda.
    exit: Live,
}

impl Pass<'_> {
    fn record(&mut self, node: NodeId, b: &BindingRef, live: &mut Live) {
        self.record_at(node, node, b, Vec::new(), live);
    }

    /// A use of the place `path` below `b`, named by the expression `node` (the root name for the
    /// binding's own table, `place_node` for the place table).
    fn record_at(
        &mut self,
        node: NodeId,
        place_node: NodeId,
        b: &BindingRef,
        path: Vec<Name>,
        live: &mut Live,
    ) {
        let next = next_use(live, b.uid, &[]);
        self.out.uses.insert(
            (node, b.uid),
            UseLive {
                last: next.is_none(),
                next,
            },
        );
        let near = next_use(live, b.uid, &path);
        self.out.places.insert(
            (place_node, b.uid),
            UseLive {
                last: near.is_none(),
                next: near,
            },
        );
        live.insert(b.uid, path_of(path), node);
    }

    /// The store to `uid` ends the life of the old value of the whole binding. Its "assigned
    /// again" marks go too: nothing before the definition captures the binding, and leaving them
    /// grows the live set by one entry per assigned binding, so every statement after a long run
    /// of bindings costs the run (quadratic).
    fn kill(live: &mut Live, uid: usize) {
        live.remove_where(uid, |_| true);
        live.remove_where(uid | STORED, |_| true);
    }

    /// Marks `uid` as assigned at `node`, for closures created before it.
    fn mark_stored(live: &mut Live, uid: usize, node: NodeId) {
        live.insert(uid | STORED, None, node);
    }

    fn block(&mut self, body: &[Stmt], mut live: Live) -> Live {
        for s in body.iter().rev() {
            live = self.stmt(s, live);
        }
        live
    }

    fn stmt(&mut self, s: &Stmt, mut live: Live) -> Live {
        match &s.kind {
            StmtKind::Bind { pattern, value, .. } => {
                self.define_pattern(pattern, &mut live);
                self.expr(value, &mut live);
            }
            StmtKind::Assign { target, value, .. } => {
                match target {
                    AssignTarget::Name(_) => {
                        if let Some(b) = self.m.assigned(value) {
                            // The store ends the old value's life.
                            Self::kill(&mut live, b.uid);
                            Self::mark_stored(&mut live, b.uid, value.id);
                        }
                    }
                    AssignTarget::Member(t) => {
                        if let Some((root, b, mut path)) = field_chain(self.m, t) {
                            // The store ends the life of what the place held, and of the parts
                            // below it; the binding itself is used.
                            live.remove_where(b.uid, |p| p.starts_with(&path));
                            path.push(store_step());
                            self.record_at(root.id, t.id, &b, path, &mut live);
                        } else {
                            self.expr(t, &mut live);
                        }
                    }
                }
                self.expr(value, &mut live);
            }
            StmtKind::Call(e) => self.expr(e, &mut live),
            StmtKind::Return(e) => {
                live = self.exit.clone();
                if let Some(e) = e {
                    self.expr(e, &mut live);
                }
            }
            StmtKind::Break => live = self.breaks.last().cloned().unwrap_or_default(),
            StmtKind::Continue => live = self.continues.last().cloned().unwrap_or_default(),
            StmtKind::If {
                binding,
                cond,
                mutable: _,
                body,
                else_body,
            } => {
                let mut joined = self.block(body, live.clone());
                if let Some(p) = binding {
                    self.define_pattern(p, &mut joined);
                }
                join(&mut joined, &self.block(else_body, live));
                live = joined;
                self.expr(cond, &mut live);
            }
            StmtKind::While { cond, body } => {
                live = self.looping(Some(cond), None, None, body, live)
            }
            StmtKind::For { .. } if self.m.stmt(s).expansion.is_some() => {
                let expansion = self.m.stmt(s).expansion.unwrap_or_default();
                live = self.block(&expansion, live);
            }
            StmtKind::For { iter, body, .. } => {
                let variable = self.m.stmt(s).loop_binding;
                live = self.looping(None, Some(iter), variable.map(|b| b.uid), body, live);
            }
        }
        live
    }

    fn define_pattern(&mut self, p: &Pattern, live: &mut Live) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.m.pattern_binding(p) {
                    Self::kill(live, b.uid);
                }
            }
            PatternKind::List(items) => items.iter().for_each(|i| self.define_pattern(i, live)),
            PatternKind::Type(fields) => fields
                .iter()
                .for_each(|f| self.define_pattern(&f.pattern, live)),
        }
    }

    /// A loop head fixpoint: the next iteration's reads keep bindings live.
    fn looping(
        &mut self,
        cond: Option<&Expr>,
        iter: Option<&Expr>,
        defined: Option<usize>,
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
            // The loop variable is defined per iteration, inside the loop.
            if let Some(uid) = defined {
                Self::kill(&mut entry, uid);
            }
            join(&mut entry, &after);
            if let Some(c) = cond {
                self.expr(c, &mut entry);
            }
            let before = head.len();
            join(&mut head, &entry);
            if head.len() == before {
                break;
            }
        }
        let mut live = head;
        if let Some(i) = iter {
            self.expr(i, &mut live);
        }
        live
    }

    /// Walks an expression backwards: children in reverse evaluation order.
    fn expr(&mut self, e: &Expr, live: &mut Live) {
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Void => {}
            ExprKind::Text(parts) => {
                for part in parts.iter().rev() {
                    if let TextPart::Interp(i) = part {
                        self.expr(i, live);
                    }
                }
            }
            ExprKind::Name(_) => {
                if let Resolution::Local(b) = self.m.resolution(e) {
                    self.record(e.id, &b, live);
                }
            }
            ExprKind::Member { left, .. } => {
                if let Some((root, b, path)) = field_chain(self.m, e) {
                    self.record_at(root.id, e.id, &b, path, live);
                } else {
                    self.expr(left, live);
                }
            }
            ExprKind::Apply { left, value, .. } => {
                if let Some(v) = value {
                    self.expr(v, live);
                }
                self.expr(left, live);
            }
            ExprKind::Index { left, index } => {
                self.expr(index, live);
                self.expr(left, live);
            }
            ExprKind::Probe(target) => self.expr(target, live),
            ExprKind::List(items) => items.iter().rev().for_each(|i| self.expr(i, live)),
            ExprKind::Map(entries) => {
                for entry in entries.iter().rev() {
                    self.expr(&entry.value, live);
                    self.expr(&entry.key, live);
                }
            }
            ExprKind::Unary { operand, .. } => self.expr(operand, live),
            ExprKind::Binary { op, left, right } => {
                if matches!(op, BinaryOp::And | BinaryOp::Or) {
                    // The right operand runs on some paths only.
                    let skipped = live.clone();
                    self.expr(right, live);
                    join(live, &skipped);
                } else {
                    self.expr(right, live);
                }
                self.expr(left, live);
            }
            ExprKind::Lambda(l) => self.lambda(e, l, live),
            ExprKind::Call { callee, args } => {
                if is_index_store(callee, args) {
                    // `m[k] = v` consumes `k` at the store, after `v` ran, so `v` may read
                    // `k`. Walking backwards, the key is the later use.
                    for a in args {
                        self.expr(&a.value, live);
                    }
                } else {
                    for a in args.iter().rev() {
                        self.expr(&a.value, live);
                    }
                }
                self.expr(callee, live);
            }
            ExprKind::Match { scrutinee, arms } => {
                let after = live.clone();
                let mut joined = Live::new();
                for arm in arms.iter().rev() {
                    let mut arm_live = after.clone();
                    if let Some(v) = &arm.value {
                        self.expr(v, &mut arm_live);
                    }
                    arm_live = self.block(&arm.body, arm_live);
                    for b in self.m.arm(arm).bindings.iter().flatten() {
                        Self::kill(&mut arm_live, b.uid);
                    }
                    join(&mut joined, &arm_live);
                }
                *live = joined;
                self.expr(scrutinee, live);
            }
        }
    }

    fn lambda(&mut self, e: &Expr, l: &Lambda, live: &mut Live) {
        let captures = self.m.captures(e);
        // The closure may run again, so its captured variables never die in its body.
        let captured: Live = captures.iter().map(|b| (b.uid, Vec::new(), e.id)).collect();
        let saved = (
            std::mem::replace(&mut self.exit, captured.clone()),
            std::mem::take(&mut self.breaks),
            std::mem::take(&mut self.continues),
        );
        self.block(&l.body, captured);
        (self.exit, self.breaks, self.continues) = saved;
        for b in &captures {
            self.record(e.id, b, live);
            if let Some(at) = live.get(b.uid | STORED, &[]) {
                self.out.assigned_after.insert((e.id, b.uid), at);
            }
        }
    }
}

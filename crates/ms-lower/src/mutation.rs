//! Which parameters a function changes.
//!
//! A parameter is changed when the body assigns through it, uses a collection mutator on it,
//! or passes it to a function that changes the matching parameter. The caller of such a
//! function sees the change in its own argument: the callee hands the updated value back and
//! the call site stores it into the argument's place, the same way a `var` parameter works.

use ms_check::hir::{Body, Callable, ModuleHir, Resolution};
use ms_check::types::{Kind, Name};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// A source function or method: module file and declaration node.
pub(crate) type FnKey = (Name, ms_syntax::NodeId);

/// A parameter of a source function: position (receiver first).
pub(crate) type ParamKey = (FnKey, usize);

/// The parameter of a callee that an argument feeds.
enum Target {
    Receiver,
    Param(Name),
}

/// A source call whose argument is rooted at a local.
struct Edge {
    root: usize,
    callee: FnKey,
    target: Target,
}

/// The base and index of an element read `xs[i]`. The parser reads `xs[name]` as an `Apply`
/// node that the checker resolves to an index, so both spellings count.
pub(crate) fn index_parts<'e>(hir: &ModuleHir, e: &'e Expr) -> Option<(&'e Expr, &'e Expr)> {
    match &e.kind {
        ExprKind::Index { left, index } => Some((left, index)),
        ExprKind::Apply {
            left,
            value: Some(index),
            ..
        } if is_index_apply(hir, e) => Some((left, index)),
        _ => None,
    }
}

/// Whether an `Apply` node is really an index read (`xs[i]`).
pub(crate) fn is_index_apply(hir: &ModuleHir, e: &Expr) -> bool {
    hir.info(e).native_str() == "index"
        || matches!(hir.resolution(e), Resolution::Native(n) if n.as_str() == "index")
}

/// Peels field selections and element reads off a place expression down to its base.
pub(crate) fn place_base<'e>(hir: &ModuleHir, e: &'e Expr) -> &'e Expr {
    let mut cur = e;
    loop {
        if let ExprKind::Member { left, .. } = &cur.kind {
            cur = left;
        } else if let Some((left, _)) = index_parts(hir, cur) {
            cur = left;
        } else {
            return cur;
        }
    }
}

/// Finds the root local of a place expression (`a`, `a.b.c`, `a[i].c`).
pub(crate) fn place_root(hir: &ModuleHir, e: &Expr) -> Option<usize> {
    let cur = place_base(hir, e);
    match hir.resolution(cur) {
        Resolution::Local(b) => Some(b.uid),
        _ => None,
    }
}

/// Whether evaluating `e` can return early through `try`.
pub(crate) fn has_try(e: &Expr) -> bool {
    struct Tries(bool);
    impl Visitor for Tries {
        fn expr(&mut self, e: &Expr) {
            self.0 |= matches!(
                &e.kind,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    ..
                }
            );
        }
    }
    let mut v = Tries(false);
    ms_syntax::visit::walk_expr(&mut v, e);
    v.0
}

/// How many times `e` reads or names the local `uid`.
pub(crate) fn uses_of(hir: &ModuleHir, e: &Expr, uid: usize) -> usize {
    struct Uses<'h> {
        hir: &'h ModuleHir,
        uid: usize,
        count: usize,
    }
    impl Visitor for Uses<'_> {
        fn expr(&mut self, e: &Expr) {
            if let Resolution::Local(b) = self.hir.resolution(e)
                && b.uid == self.uid
            {
                self.count += 1;
            }
        }
    }
    let mut v = Uses { hir, uid, count: 0 };
    ms_syntax::visit::walk_expr(&mut v, e);
    v.count
}

/// Whether the statements read, name, or change the local `uid` anywhere, closures included.
pub(crate) fn block_mentions(hir: &ModuleHir, body: &[Stmt], uid: usize) -> bool {
    struct Mentions<'h> {
        hir: &'h ModuleHir,
        uid: usize,
        found: bool,
    }
    impl Visitor for Mentions<'_> {
        fn expr(&mut self, e: &Expr) {
            if let Resolution::Local(b) = self.hir.resolution(e)
                && b.uid == self.uid
            {
                self.found = true;
            }
        }
        fn stmt(&mut self, s: &Stmt) {
            if let StmtKind::Assign {
                target: AssignTarget::Name(_),
                value,
                ..
            } = &s.kind
                && self.hir.assigned(value).is_some_and(|b| b.uid == self.uid)
            {
                self.found = true;
            }
        }
    }
    let mut v = Mentions {
        hir,
        uid,
        found: false,
    };
    ms_syntax::visit::walk_block(&mut v, body);
    v.found
}

/// The locals a body assigns to or mutates in place, and the source calls they feed.
struct Mutations<'h> {
    hir: &'h ModuleHir,
    roots: HashSet<usize>,
    edges: Vec<Edge>,
}

impl Visitor for Mutations<'_> {
    fn stmt(&mut self, s: &Stmt) {
        if let StmtKind::Assign { target, value, .. } = &s.kind {
            let root = match target {
                AssignTarget::Name(_) => self.hir.assigned(value).map(|b| b.uid),
                AssignTarget::Member(t) => place_root(self.hir, t),
            };
            self.roots.extend(root);
        }
    }

    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { callee, .. } = &e.kind else {
            return;
        };
        let Some(view) = self.hir.call(e) else {
            return;
        };
        let mut c: &Expr = callee;
        if let ExprKind::Apply { left, .. } = &c.kind {
            c = left;
        }
        match &view.target {
            Resolution::Method(m) if !m.native.as_str().is_empty() => {
                if let ExprKind::Member { left, .. } = &c.kind
                    && ms_check::effects::collection_mutation(m)
                {
                    self.roots.extend(place_root(self.hir, left));
                }
            }
            Resolution::Method(m) => {
                let Some(decl) = &m.decl else { return };
                let callee_key = (m.module, decl.id());
                if let ExprKind::Member { left, .. } = &c.kind
                    && let Some(root) = place_root(self.hir, left)
                {
                    self.edges.push(Edge {
                        root,
                        callee: callee_key,
                        target: Target::Receiver,
                    });
                }
                self.argument_edges(&view, callee_key);
            }
            Resolution::Function(sym) if sym.native.as_str().is_empty() => {
                let Some(decl) = &sym.decl else { return };
                self.argument_edges(&view, (sym.module, decl.id()));
            }
            _ => {}
        }
    }
}

impl Mutations<'_> {
    fn argument_edges(&mut self, view: &ms_check::hir::CallView<'_>, callee: FnKey) {
        for a in &view.arguments {
            if let Some(root) = place_root(self.hir, a.expr) {
                self.edges.push(Edge {
                    root,
                    callee,
                    target: Target::Param(a.slot.name),
                });
            }
        }
    }
}

/// A body to scan.
fn scan<'h>(hir: &'h ModuleHir, body: Body<'_>) -> Mutations<'h> {
    let mut v = Mutations {
        hir,
        roots: HashSet::new(),
        edges: Vec::new(),
    };
    match body {
        Body::Block(b) => ms_syntax::visit::walk_block(&mut v, b),
        Body::Expr(e) => ms_syntax::visit::walk_expr(&mut v, e),
    }
    v
}

/// Whether a parameter of this type is shared by reference in the source semantics.
fn by_reference(kind: Kind) -> bool {
    matches!(kind, Kind::Record | Kind::Alternative | Kind::Native)
}

/// The position of the callee parameter an edge feeds.
fn target_position(callables: &HashMap<FnKey, Rc<Callable>>, edge: &Edge) -> Option<usize> {
    let callee = callables.get(&edge.callee)?;
    let base = usize::from(callee.self_binding.is_some());
    match edge.target {
        Target::Receiver => callee.self_binding.is_some().then_some(0),
        Target::Param(n) => callee
            .parameters
            .iter()
            .position(|p| p.name == n)
            .map(|i| base + i),
    }
}

/// Whether a method changes its receiver, for a method used as a value.
pub(crate) fn method_changes_receiver(
    m: &ms_check::types::MethodRef,
    mutated: &HashSet<ParamKey>,
) -> bool {
    match (&m.decl, m.native.as_str()) {
        (Some(d), "contract") => d.method().is_some_and(|x| x.mutating),
        (_, "contract") => false,
        (_, native) if !native.is_empty() => ms_check::effects::collection_mutation(m),
        (Some(d), _) => mutated.contains(&((m.module, d.id()), 0)),
        _ => false,
    }
}

/// The variables whose changing methods `body` takes as values (`xs.append` without a call):
/// the value shares the variable, so it must live in memory.
pub(crate) fn changing_method_roots(
    hir: &ModuleHir,
    body: Body<'_>,
    mutated: &HashSet<ParamKey>,
) -> HashSet<usize> {
    struct Values<'h> {
        hir: &'h ModuleHir,
        mutated: &'h HashSet<ParamKey>,
        called: HashSet<ms_syntax::NodeId>,
        roots: HashSet<usize>,
    }
    impl Visitor for Values<'_> {
        fn expr(&mut self, e: &Expr) {
            if let ExprKind::Call { callee, .. } = &e.kind {
                self.called.insert(callee.id);
                if let ExprKind::Apply { left, .. } = &callee.kind {
                    self.called.insert(left.id);
                }
            }
            let ExprKind::Member { left, .. } = &e.kind else {
                return;
            };
            if self.called.contains(&e.id) || self.hir.ty(e).kind != Kind::Function {
                return;
            }
            let Resolution::Method(m) = self.hir.resolution(e) else {
                return;
            };
            if method_changes_receiver(&m, self.mutated)
                && let Resolution::Local(b) = self.hir.resolution(left)
            {
                self.roots.insert(b.uid);
            }
        }
    }
    let mut v = Values {
        hir,
        mutated,
        called: HashSet::new(),
        roots: HashSet::new(),
    };
    match body {
        Body::Block(b) => ms_syntax::visit::walk_block(&mut v, b),
        Body::Expr(e) => ms_syntax::visit::walk_expr(&mut v, e),
    }
    v.roots
}

/// The locals of `body` that it changes, directly or through calls.
pub(crate) fn mutated_locals(
    hir: &ModuleHir,
    body: Body<'_>,
    callables: &HashMap<FnKey, Rc<Callable>>,
    mutated: &HashSet<ParamKey>,
) -> HashSet<usize> {
    let values = match &body {
        Body::Block(b) => changing_method_roots(hir, Body::Block(b), mutated),
        Body::Expr(e) => changing_method_roots(hir, Body::Expr(e), mutated),
    };
    let m = scan(hir, body);
    let mut roots = m.roots;
    for e in &m.edges {
        if let Some(p) = target_position(callables, e)
            && mutated.contains(&(e.callee, p))
        {
            roots.insert(e.root);
        }
    }
    roots.extend(values);
    roots
}

/// The parameters (receiver first) every source function changes: declared `var`, or changed
/// by the body of a reference-shared type.
pub(crate) fn infer_mutated(
    mods: &HashMap<Name, Rc<ModuleHir>>,
    callables: &HashMap<FnKey, Rc<Callable>>,
) -> HashSet<ParamKey> {
    let mut mutated = HashSet::new();
    // (function, position) -> the (callee, callee position) it passes the parameter to.
    let mut feeds: Vec<(ParamKey, ParamKey)> = Vec::new();
    for (key, c) in callables {
        let bindings: Vec<&ms_check::types::BindingRef> =
            c.self_binding.iter().chain(c.parameters.iter()).collect();
        if bindings.is_empty() {
            continue;
        }
        let has_self = c.self_binding.is_some();
        for (i, b) in bindings.iter().enumerate() {
            let declared = if has_self && i == 0 {
                c.func.method().is_some_and(|m| m.mutating)
            } else {
                b.mutable
            };
            if declared {
                mutated.insert((*key, i));
            }
        }
        let Some(hir) = mods.get(&c.module.file) else {
            continue;
        };
        let m = scan(hir, c.body());
        for (i, b) in bindings.iter().enumerate() {
            if !by_reference(b.ty.kind) {
                continue;
            }
            if m.roots.contains(&b.uid) {
                mutated.insert((*key, i));
            }
        }
        for e in &m.edges {
            let Some(i) = bindings.iter().position(|b| b.uid == e.root) else {
                continue;
            };
            if !by_reference(bindings[i].ty.kind) {
                continue;
            }
            if let Some(q) = target_position(callables, e) {
                feeds.push(((*key, i), (e.callee, q)));
            }
        }
    }
    loop {
        let before = mutated.len();
        for (from, to) in &feeds {
            if mutated.contains(to) {
                mutated.insert(*from);
            }
        }
        if mutated.len() == before {
            return mutated;
        }
    }
}

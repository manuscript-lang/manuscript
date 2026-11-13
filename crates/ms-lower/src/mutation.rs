//! Which parameters a function changes, and which locals a body changes.
//!
//! A parameter is changed when it is declared `var`; the caller sees the change in its own
//! argument: the callee hands the updated value back and the call site stores it into the
//! argument's place. Local changes (assignment through a name, a collection mutator, a call that
//! changes a parameter) decide which locals live in memory slots.

use ms_check::api::ast::*;
use ms_check::api::hir::{Body, Callable, ModuleHir, Resolution};
use ms_check::api::types::{self as ct, Kind, Name};
use ms_check::api::visit::Visitor;
use ms_check::fxmap::{HashMap, HashSet};
use std::rc::Rc;

/// A source function or method: module file and declaration node.
pub(crate) type FnKey = (Name, ms_check::api::NodeId);

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
pub(crate) fn index_parts<'e>(
    syms: ms_check::api::Names,
    hir: &ModuleHir,
    e: &'e Expr,
) -> Option<(&'e Expr, &'e Expr)> {
    match &e.kind {
        ExprKind::Index { left, index } => Some((left, index)),
        ExprKind::Apply {
            left,
            value: Some(index),
            ..
        } if is_index_apply(syms, hir, e) => Some((left, index)),
        _ => None,
    }
}

/// Whether an `Apply` node is really an index read (`xs[i]`).
pub(crate) fn is_index_apply(syms: ms_check::api::Names, hir: &ModuleHir, e: &Expr) -> bool {
    hir.info(e).native_str(syms) == "index"
        || matches!(hir.resolution(e), Resolution::Native(n) if syms.str(n) == "index")
}

/// Peels field selections and element reads off a place expression down to its base.
pub(crate) fn place_base<'e>(syms: ms_check::api::Names, hir: &ModuleHir, e: &'e Expr) -> &'e Expr {
    let mut cur = e;
    loop {
        if let ExprKind::Member { left, .. } = &cur.kind {
            cur = left;
        } else if let Some((left, _)) = index_parts(syms, hir, cur) {
            cur = left;
        } else {
            return cur;
        }
    }
}

/// Finds the root local of a place expression (`a`, `a.b.c`, `a[i].c`).
pub(crate) fn place_root(syms: ms_check::api::Names, hir: &ModuleHir, e: &Expr) -> Option<usize> {
    let cur = place_base(syms, hir, e);
    match hir.resolution(cur) {
        Resolution::Local(b) => Some(b.uid),
        _ => None,
    }
}

/// Whether evaluating `e` can return early through `try`. A `try` inside a lambda returns from
/// the lambda, not from `e`.
pub(crate) fn has_try(e: &Expr) -> bool {
    struct Tries {
        found: bool,
        lambdas: usize,
    }
    impl Visitor for Tries {
        fn expr(&mut self, e: &Expr) {
            match &e.kind {
                ExprKind::Lambda(_) => self.lambdas += 1,
                ExprKind::Unary {
                    op: UnaryOp::Try, ..
                } if self.lambdas == 0 => self.found = true,
                _ => {}
            }
        }
        fn leave_expr(&mut self, e: &Expr) {
            if matches!(e.kind, ExprKind::Lambda(_)) {
                self.lambdas -= 1;
            }
        }
    }
    let mut v = Tries {
        found: false,
        lambdas: 0,
    };
    ms_check::api::visit::walk_expr(&mut v, e);
    v.found
}

/// Whether evaluating `e` runs a call, so evaluating it again would repeat a side effect.
pub(crate) fn has_call(e: &Expr) -> bool {
    struct Calls(bool);
    impl Visitor for Calls {
        fn expr(&mut self, e: &Expr) {
            self.0 |= matches!(&e.kind, ExprKind::Call { .. });
        }
    }
    let mut v = Calls(false);
    ms_check::api::visit::walk_expr(&mut v, e);
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
    ms_check::api::visit::walk_expr(&mut v, e);
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
    ms_check::api::visit::walk_block(&mut v, body);
    v.found
}

/// Whether `body` names the list `uid` only as the receiver of a read in place (`get`,
/// `length`, `is_empty`) or as the iterable of a `for`, never inside a closure: nothing can keep
/// the list or move it.
pub(crate) fn only_read_in_place(
    syms: ms_check::api::Names,
    hir: &ModuleHir,
    body: &[Stmt],
    uid: usize,
) -> bool {
    struct Reads<'h> {
        syms: ms_check::api::Names,
        hir: &'h ModuleHir,
        uid: usize,
        mentions: usize,
        reads: usize,
        lambdas: usize,
        captured: bool,
    }
    impl Reads<'_> {
        fn names(&self, e: &Expr) -> bool {
            matches!(self.hir.resolution(e), Resolution::Local(b) if b.uid == self.uid)
        }
    }
    impl Visitor for Reads<'_> {
        fn expr(&mut self, e: &Expr) {
            let syms = self.syms;
            match &e.kind {
                ExprKind::Lambda(_) => self.lambdas += 1,
                ExprKind::Call { callee, .. } => {
                    if let ExprKind::Member { left, name } = &callee.kind
                        && matches!(syms.str(name), "get" | "length" | "is_empty")
                        && self.names(left)
                    {
                        self.reads += 1;
                    }
                }
                _ => {}
            }
            if self.names(e) {
                self.mentions += 1;
                self.captured |= self.lambdas > 0;
            }
        }
        fn leave_expr(&mut self, e: &Expr) {
            if let ExprKind::Lambda(_) = &e.kind {
                self.lambdas -= 1;
            }
        }
        fn stmt(&mut self, s: &Stmt) {
            match &s.kind {
                StmtKind::For { iter, .. } if self.names(iter) => self.reads += 1,
                StmtKind::Assign {
                    target: AssignTarget::Name(_),
                    value,
                    ..
                } if self.hir.assigned(value).is_some_and(|b| b.uid == self.uid) => {
                    self.captured = true;
                }
                _ => {}
            }
        }
    }
    let mut v = Reads {
        syms,
        hir,
        uid,
        mentions: 0,
        reads: 0,
        lambdas: 0,
        captured: false,
    };
    ms_check::api::visit::walk_block(&mut v, body);
    !v.captured && v.mentions == v.reads
}

/// The locals a body assigns to or mutates in place, and the source calls they feed.
struct Mutations<'h> {
    syms: ms_check::api::Names,
    hir: &'h ModuleHir,
    roots: HashSet<usize>,
    edges: Vec<Edge>,
}

impl Visitor for Mutations<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let syms = self.syms;
        if let StmtKind::Assign { target, value, .. } = &s.kind {
            let root = match target {
                AssignTarget::Name(_) => self.hir.assigned(value).map(|b| b.uid),
                AssignTarget::Member(t) => place_root(syms, self.hir, t),
            };
            self.roots.extend(root);
        }
    }

    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
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
            Resolution::Method(m) if m.native != ct::Native::Source => {
                if let ExprKind::Member { left, .. } = &c.kind
                    && ms_check::api::ownership::collection_mutation(syms, m)
                {
                    self.roots.extend(place_root(syms, self.hir, left));
                }
            }
            Resolution::Method(m) => {
                let Some(decl) = &m.decl else { return };
                let callee_key = (m.module, decl.id());
                if let ExprKind::Member { left, .. } = &c.kind
                    && let Some(root) = place_root(syms, self.hir, left)
                {
                    self.edges.push(Edge {
                        root,
                        callee: callee_key,
                        target: Target::Receiver,
                    });
                }
                self.argument_edges(syms, &view, callee_key);
            }
            Resolution::Function(sym) if sym.native == ct::Native::Source => {
                let Some(decl) = &sym.decl else { return };
                self.argument_edges(syms, &view, (sym.module, decl.id()));
            }
            _ => {}
        }
    }
}

impl Mutations<'_> {
    fn argument_edges(
        &mut self,
        syms: ms_check::api::Names,
        view: &ms_check::api::hir::CallView<'_>,
        callee: FnKey,
    ) {
        for a in &view.arguments {
            if let Some(root) = place_root(syms, self.hir, a.expr) {
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
fn scan<'h>(syms: ms_check::api::Names, hir: &'h ModuleHir, body: Body<'_>) -> Mutations<'h> {
    let mut v = Mutations {
        syms,
        hir,
        roots: HashSet::default(),
        edges: Vec::new(),
    };
    match body {
        Body::Block(b) => ms_check::api::visit::walk_block(&mut v, b),
        Body::Expr(e) => ms_check::api::visit::walk_expr(&mut v, e),
    }
    v
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
    syms: ms_check::api::Names,
    m: &ms_check::api::types::MethodRef,
    mutated: &HashSet<ParamKey>,
) -> bool {
    match (&m.decl, m.native) {
        (Some(d), ct::Native::Contract) => d.method().is_some_and(|x| x.mutating),
        (_, ct::Native::Contract) => false,
        (_, native) if native.is_bodiless() => {
            ms_check::api::ownership::collection_mutation(syms, m)
        }
        (Some(d), _) => mutated.contains(&((m.module, d.id()), 0)),
        _ => false,
    }
}

/// The variables whose changing methods `body` takes as values (`xs.append` without a call):
/// the value shares the variable, so it must live in memory.
pub(crate) fn changing_method_roots(
    syms: ms_check::api::Names,
    hir: &ModuleHir,
    body: Body<'_>,
    mutated: &HashSet<ParamKey>,
) -> HashSet<usize> {
    struct Values<'h> {
        syms: ms_check::api::Names,
        hir: &'h ModuleHir,
        mutated: &'h HashSet<ParamKey>,
        called: HashSet<ms_check::api::NodeId>,
        roots: HashSet<usize>,
    }
    impl Visitor for Values<'_> {
        fn expr(&mut self, e: &Expr) {
            let syms = self.syms;
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
            if method_changes_receiver(syms, &m, self.mutated)
                && let Resolution::Local(b) = self.hir.resolution(left)
            {
                self.roots.insert(b.uid);
            }
        }
    }
    let mut v = Values {
        syms,
        hir,
        mutated,
        called: HashSet::default(),
        roots: HashSet::default(),
    };
    match body {
        Body::Block(b) => ms_check::api::visit::walk_block(&mut v, b),
        Body::Expr(e) => ms_check::api::visit::walk_expr(&mut v, e),
    }
    v.roots
}

/// The locals of `body` that it changes, directly or through calls.
pub(crate) fn mutated_locals(
    syms: ms_check::api::Names,
    hir: &ModuleHir,
    body: Body<'_>,
    callables: &HashMap<FnKey, Rc<Callable>>,
    mutated: &HashSet<ParamKey>,
) -> HashSet<usize> {
    let values = match &body {
        Body::Block(b) => changing_method_roots(syms, hir, Body::Block(b), mutated),
        Body::Expr(e) => changing_method_roots(syms, hir, Body::Expr(e), mutated),
    };
    let m = scan(syms, hir, body);
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

/// The parameters (receiver first) every source function changes: those it declares `var`. The
/// checker rejects a change through any other parameter, so no body scan is needed (over the
/// whole conformance corpus the earlier inference added nothing to this set).
pub(crate) fn infer_mutated(callables: &HashMap<FnKey, Rc<Callable>>) -> HashSet<ParamKey> {
    let mut mutated = HashSet::default();
    for (key, c) in callables {
        let has_self = c.self_binding.is_some();
        if has_self && c.func.method().is_some_and(|m| m.mutating) {
            mutated.insert((*key, 0));
        }
        let base = usize::from(has_self);
        for (i, b) in c.parameters.iter().enumerate() {
            if b.mutable {
                mutated.insert((*key, base + i));
            }
        }
    }
    mutated
}

//! The forward walk: classifies every use, tracks lexical borrows, and
//! reports the rules a program breaks.

use super::classify::{Class, Classifier, declares_close};
use super::live::Liveness;
use super::modes::{
    CallModes, Lend, ParamMode, Summaries, Summary, call_lend, call_modes, receiver_mode,
};
use super::places::{Place, Step};
use super::*;
use ms_syntax::ast::*;
use ms_syntax::{DiagnosticFix, Phase, Pos, visit};
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
    pub summaries: &'a Summaries,
    /// Every method of the program, to find the implementations an interface conversion uses.
    pub methods: &'a [MethodRef],
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

/// A call operand whose description is written only if a diagnostic needs it.
enum Operand<'e> {
    Receiver(&'e Expr),
    Argument(&'e Expr),
    /// An operand of an operator, index, literal or interpolation.
    Part(&'e Expr),
}

/// An operand with the places it holds for the whole call (changed when `true`) and the places
/// the calls inside it changed or moved while it was computed.
type Logged<'e> = (Operand<'e>, Vec<(Place, bool)>, Vec<Place>);

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
    /// An exclusive borrow (`var x = place`): changes go to the origin, which
    /// nothing else may touch until the last use; not movable or reassignable.
    MutBorrowed,
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
    /// The mutable borrow this one was taken through (`var it = b.items` where `b` borrows).
    parent: Option<usize>,
    /// For a part of a parameter matched or iterated at its last use: the scrutinee that takes
    /// ownership of the parameter if this part is moved out.
    deferred: Option<NodeId>,
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

/// What a returned expression is a part of.
struct LendSource {
    receiver: bool,
    params: Vec<Name>,
    /// The field chain from one source, when the expression is a plain chain of fields.
    path: Option<(Option<Name>, Vec<Name>)>,
    /// The value is an owned interface view of the sources (a view lender's result, or a local
    /// holding one): it is returned as an owned value, never as a plain reference.
    view: bool,
}

/// A place expression resolved to its root.
#[derive(Clone)]
struct PlaceInfo {
    root: BindingRef,
    root_node: NodeId,
    resolved: Vec<Place>,
    projection: bool,
    /// The path passes through a `ref` field: a read-only view of another value.
    through_ref: Option<Name>,
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
        callees: HashSet::new(),
        escaped: cx.escaped.clone(),
        positions: HashMap::new(),
        mutated: Vec::new(),
        captured: Vec::new(),
        hidden: 0,
        let_pos: HashMap::new(),
        used: cx.live.uses.keys().map(|(_, uid)| *uid).collect(),
        nested_cache: HashMap::new(),
        resources: Vec::new(),
        arm_payloads: Vec::new(),
        chain_places: HashMap::new(),
        keep_scrutinee: false,
        closed: HashSet::new(),
        lend_receiver: false,
        lend_params: Vec::new(),
        lend_path: None,
        owned_return: None,
        lent_return: None,
        wrap_returns: Vec::new(),
        plain_lent: false,
        view_return: false,
        view_locals: HashSet::new(),
        view_calls: HashSet::new(),
        view_move: None,
    };
    w.run();
    w.mixed_returns();
    w.unclosed_resources();
    w.consumed_param_resources();
    w.moved_payloads();
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
        result: Lend {
            // A view lender returns owned values on every path, so a new value beside a view
            // is no mix.
            lends: w.lent_return.is_some() && (w.owned_return.is_none() || w.view_return),
            view: w.view_return,
            receiver: w.lend_receiver,
            params: w.lend_params.clone(),
            path: if w.view_return {
                None
            } else {
                w.lend_path.clone().flatten()
            },
        },
    };
    w.facts.lends = summary.result.lends;
    w.facts.view = summary.result.view;
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
    /// Callee expressions of direct calls, which call a named function without making a value.
    callees: HashSet<NodeId>,
    escaped: HashSet<NodeId>,
    /// Source positions of the callable's statements and expressions.
    positions: HashMap<NodeId, Pos>,
    /// Captured bindings a lambda body changes, innermost last.
    mutated: Vec<HashSet<usize>>,
    /// Variables each enclosing lambda captures, innermost last.
    captured: Vec<HashSet<usize>>,
    hidden: usize,
    /// Where the `let` keyword of each `let` binding is, for the fix that makes it a `var`.
    let_pos: HashMap<usize, Pos>,
    /// Bindings that are read, changed or moved somewhere after their declaration.
    used: HashSet<usize>,
    /// `nested_writes` by expression, so a long chain is walked once.
    nested_cache: HashMap<NodeId, Vec<Place>>,
    /// Owned `let` and `var` resources: binding, name and declaration position.
    resources: Vec<(usize, Name, Pos, bool)>,
    /// Payload bindings of match arms over a consumed scrutinee.
    arm_payloads: Vec<usize>,
    /// The optional place each `?.` payload binding was read from.
    chain_places: HashMap<usize, PlaceInfo>,
    /// The scrutinee being walked stays borrowed, never consumed at its last use.
    keep_scrutinee: bool,
    /// Bindings that had `close()` called on them.
    closed: HashSet<usize>,
    /// Sources of the returned references so far: the receiver, parameters by label, and the
    /// one field chain every path returns (`Some(None)` once two paths differ).
    lend_receiver: bool,
    lend_params: Vec<Name>,
    lend_path: Option<Option<(Option<Name>, Vec<Name>)>>,
    /// The first `return` of an owned value and of a reference, for the mixed-path error.
    owned_return: Option<Pos>,
    lent_return: Option<Pos>,
    /// Returned references that are wrappers (`x?`, `ok(x)`, the error of a `try`): beside an
    /// owned path they become new values again instead of an error.
    wrap_returns: Vec<NodeId>,
    /// Some returned reference is the part itself, not a wrapper of it.
    plain_lent: bool,
    /// Some returned value is an interface view of the arguments (a lent value converted to an
    /// interface, a view lender's result, a local holding one): the function is a view lender.
    view_return: bool,
    /// Locals that hold an interface view: they own the view's box and borrow its payload's
    /// origins, so they are returned as owned values, never lent as plain references.
    view_locals: HashSet<usize>,
    /// `ok(x)` / `error(x)` returned as views: their payload is read, not consumed.
    view_calls: HashSet<NodeId>,
    /// The name of a view local being returned: moving it out of the function is allowed even
    /// though it borrows, because the result holds the same origins.
    view_move: Option<NodeId>,
}

/// A fix that inserts `text` at `pos`.
/// `.clone()` after the written expression `e`; none for a synthetic one.
/// Why a value of this type has no `.clone()`, for remedies that would otherwise suggest one.
fn no_clone(t: &Ty) -> Option<&'static str> {
    match t.kind {
        Kind::Function => Some("a function value cannot be cloned"),
        Kind::Contract if !t.is_std("Closeable") => Some(
            "an interface value cannot be cloned (convert a clone of the concrete value instead)",
        ),
        _ => None,
    }
}

fn copy_after(e: &Expr) -> Option<DiagnosticFix> {
    (e.end.offset > e.pos.offset).then(|| insert_at(e.end, &format!(".{COPY}()")))
}

fn insert_at(pos: Pos, text: &str) -> DiagnosticFix {
    DiagnosticFix {
        pos,
        end: pos,
        replacement: text.to_string(),
    }
}

/// `pos` moved forward by `n` bytes on its line.
fn forward(pos: Pos, n: usize) -> Pos {
    Pos {
        offset: pos.offset + n as u32,
        line: pos.line,
        column: pos.column + n as u32,
    }
}

/// `pos` moved back by `n` bytes on its line.
fn back(pos: Pos, n: u32) -> Pos {
    Pos {
        offset: pos.offset.saturating_sub(n),
        line: pos.line,
        column: pos.column.saturating_sub(n).max(1),
    }
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
            // The fixture is state the tests share and the hooks change.
            self.declare(b, Role::Fixture, Perm::Mutable, None, false);
        }
        let mut positions = Positions(HashMap::new());
        match c.body() {
            Body::Block(body) => visit::walk_block(&mut positions, body),
            Body::Expr(e) => visit::walk_expr(&mut positions, e),
        }
        self.positions = positions.0;
        match c.body() {
            Body::Block(body) => self.block(body),
            Body::Expr(e) => self.returned(e),
        }
    }

    /// The value is made from another resource, which owns and closes it: `group.spawn(..)`, or a
    /// reader that wraps a source it was given.
    fn derived_from_resource(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::Unary { operand, .. } => self.derived_from_resource(operand),
            ExprKind::Call { callee, args, .. } => {
                // A constructor takes its arguments: the value it builds owns them.
                if matches!(self.cx.m.resolution(e), Resolution::Constructor { .. }) {
                    return false;
                }
                let result = self.cx.m.ty(e);
                // A source holding the result's own type (`keep(r)`, `Optional.get(d)`) or a
                // value of it (`result.get()`) hands the value over: the binding owns it.
                // An owned `Optional` or `Result` of a part the source holds (`pop()`) hands the part
                // over too.
                let modes = call_modes(self.cx.m, e, args, self.cx.summaries);
                let wraps = |src: &Expr| {
                    self.class_of(src) == Class::Resource
                        && !ty_holds(&self.cx.m.ty(src), &result)
                        && !wraps_part(&self.cx.m.ty(src), &result)
                };
                let receiver = match &callee.kind {
                    ExprKind::Member { left, .. } => wraps(left),
                    _ => false,
                };
                // An argument the callee consumes belongs to the result now, not the other way.
                let kept = |i: usize| modes.arguments.get(i) == Some(&ParamMode::Consume);
                receiver
                    || args
                        .iter()
                        .enumerate()
                        .any(|(i, a)| !kept(i) && wraps(&a.value))
            }
            _ => false,
        }
    }

    /// Whether the scope can close a resource binding of `ty`: it has a close operation, or it
    /// is a record, alternative or collection that closes the resources it holds.
    fn closable(&self, s: &Stmt, ty: &Ty) -> bool {
        self.cx.m.stmt(s).cleanup.is_some()
            || matches!(
                ty.kind,
                Kind::Record | Kind::Alternative | Kind::Native | Kind::Variable
            )
    }

    /// Whether an owned binding of `ty` may hold a resource the scope must close: a resource,
    /// or a value whose type mentions a type parameter, which an instance may bind to one.
    /// Lowering closes the instance only when its type has a closer, so a plain instance
    /// costs nothing.
    fn may_close(&self, ty: &Ty) -> bool {
        match self.cx.classes.class(ty) {
            Class::Resource => true,
            Class::Move => holds_variable(ty),
            Class::Copy => false,
        }
    }

    /// Closes at scope end an owned resource nothing takes (a binding never moved: returned,
    /// passed on, stored, captured), or reports one with no close operation; it is
    /// otherwise a leak.
    fn unclosed_resources(&mut self) {
        let resources = std::mem::take(&mut self.resources);
        for (uid, name, pos, closable) in resources {
            let moves: Vec<NodeId> = self
                .facts
                .uses
                .values()
                .filter(|u| u.binding == uid && u.access == Access::Move)
                .map(|u| u.node)
                .collect();
            if !moves.is_empty() {
                // Moved on some path: the scope closes it on the paths that keep it. Lowering
                // tracks that with a flag cleared at each move.
                if closable {
                    self.facts.implicit_closes.insert(uid);
                    if self.closed.contains(&uid) {
                        self.facts.explicit_closes.insert(uid);
                    }
                    self.facts
                        .close_moves
                        .insert(uid, moves.into_iter().collect());
                }
                continue;
            }
            if closable {
                // Never handed on: the scope closes it, after any early `.close()` of its own
                // (close is idempotent).
                self.facts.implicit_closes.insert(uid);
                if self.closed.contains(&uid) {
                    self.facts.explicit_closes.insert(uid);
                }
            } else if !self.closed.contains(&uid) {
                self.error(
                    pos,
                    format!(
                        "`{name}` is a resource that is never closed: call `{name}.close()`, or return it so the caller owns it"
                    ),
                );
            }
        }
    }

    /// Records the payloads of a consumed match scrutinee that a path moves out: the new owner
    /// closes them, so the match must not.
    fn moved_payloads(&mut self) {
        for uid in std::mem::take(&mut self.arm_payloads) {
            let moved = self
                .facts
                .uses
                .values()
                .any(|u| u.binding == uid && u.access == Access::Move);
            if moved {
                self.facts.moved_payloads.insert(uid);
            }
        }
    }

    /// Closes at scope end a resource parameter the callee keeps on some path: the caller
    /// handed it over, so the paths that do not move it on close it.
    fn consumed_param_resources(&mut self) {
        for b in self.cx.c.parameters.iter() {
            let tracked = self.consumed.contains(&b.uid)
                && self.cx.classes.class(&b.ty) == Class::Resource
                && matches!(b.ty.kind, Kind::Record | Kind::Alternative | Kind::Native);
            if !tracked {
                continue;
            }
            let moves: HashSet<NodeId> = self
                .facts
                .uses
                .values()
                .filter(|u| u.binding == b.uid && u.access == Access::Move)
                .map(|u| u.node)
                .collect();
            self.facts.implicit_closes.insert(b.uid);
            self.facts.close_moves.insert(b.uid, moves);
        }
    }

    /// Evaluates a value handed back to the caller.
    fn returned(&mut self, e: &Expr) {
        if !self.captured.is_empty() {
            // A lambda never lends: an escaping closure owns its captures.
            self.expr(e, Demand::Consume);
            return;
        }
        // Each branch of a conditional or match expression is a returned value of its own.
        if let ExprKind::Match { scrutinee, arms } = &e.kind
            && arms.iter().all(|a| a.value.is_some())
        {
            self.match_expr(e, scrutinee, arms, Demand::Consume, true);
            return;
        }
        // A lent value converted to an interface on the way out (`return cause` as `Error`,
        // `error(cause)` as `Int!`, a widened lending call), a view lender's result or a local
        // holding a view: the result is an owned view whose payload stays in the arguments.
        if !self.implements_contract() && self.view_return_source(e) {
            return;
        }
        // A resource is never lent: returning one hands it to the caller, which closes it.
        let wrapped = self.wrapped_lend(e).is_some();
        if self.class_of(e) == Class::Move
            && (self.returns_as_declared(e) || wrapped)
            && !self.implements_contract()
        {
            if let Some(src) = self.lend_source(e) {
                // A part of an argument comes back as a reference into it: nothing moves. A
                // wrapper around it (`x?`, `ok(x)`) adds no storage and stays a reference too.
                self.lent_return.get_or_insert(e.pos);
                if wrapped {
                    self.facts.view_wraps.insert(e.id);
                    self.wrap_returns.push(e.id);
                } else {
                    self.plain_lent = true;
                }
                self.lend_receiver |= src.receiver;
                for p in src.params {
                    if !self.lend_params.contains(&p) {
                        self.lend_params.push(p);
                    }
                }
                self.lend_path = Some(match (self.lend_path.take(), src.path) {
                    (None, path) => path,
                    (Some(Some(a)), Some(b)) if a == b => Some(a),
                    _ => None,
                });
                self.expr(e, Demand::Read);
                return;
            }
            self.owned_return.get_or_insert(e.pos);
        }
        // A reference converted on the way out (a lending call widened to another error type or
        // an interface) is read: the conversion builds the new value from it.
        let converted = self.cx.m.info(e).error_source.is_some()
            && matches!(e.kind, ExprKind::Call { .. })
            && self.lends(e);
        self.expr(
            e,
            if converted {
                Demand::Read
            } else {
                Demand::Consume
            },
        );
    }

    /// Whether `e` is a `Copy` handle such as `Shared[T]`: it is not the storage it lends from,
    /// and another copy of the handle can change that storage, so what it lends is a copy.
    fn copy_handle(&self, e: &Expr) -> bool {
        self.class_of(e) == Class::Copy && self.cx.m.ty(e).is_std("Shared")
    }

    /// The fields from a variable to a place written as a plain chain of them.
    fn field_path(&self, e: &Expr) -> Option<Vec<Name>> {
        match &e.kind {
            ExprKind::Name(_) => Some(Vec::new()),
            ExprKind::Member { left, name } => {
                let mut f = self.field_path(left)?;
                f.push(*name);
                Some(f)
            }
            _ => None,
        }
    }

    /// Classifies `e` as a returned interface view when it is one, recording the sources and
    /// walking it; `false` when `e` is not a view (a plain reference or a new value).
    fn view_return_source(&mut self, e: &Expr) -> bool {
        let via = self.view_source(e);
        let src = match via {
            Some(x) => self.lend_source(x),
            None => self.lend_source(e).filter(|s| s.view),
        };
        let Some(src) = src else {
            return false;
        };
        self.lent_return.get_or_insert(e.pos);
        self.view_return = true;
        self.lend_receiver |= src.receiver;
        for p in src.params {
            if !self.lend_params.contains(&p) {
                self.lend_params.push(p);
            }
        }
        self.lend_path = Some(None);
        // The payload of `ok(x)` / `error(x)` is read into the view, not consumed.
        if self.result_payload(e).is_some() {
            self.view_calls.insert(e.id);
        }
        // A local holding a view is moved out: the box it owns becomes the result. The same
        // when a lender hands the local back whole (`return relay(e)`): the box moves into the
        // call and comes back as the result instead of being copied.
        let moved = via.unwrap_or(e);
        let moved = self.result_payload(moved).unwrap_or(moved);
        if let Some(operand) = self.whole_lent_operand(moved) {
            // The call reads its argument; lowering moves the box in and keeps it as the result.
            self.facts.view_moves.insert(operand.id);
            self.expr(e, Demand::Read);
        } else if let ExprKind::Name(_) = &moved.kind
            && let Resolution::Local(b) = self.cx.m.resolution(moved)
            && self.view_locals.contains(&b.uid)
            && b.ty.kind == Kind::Contract
        {
            self.view_calls.remove(&e.id);
            self.facts.view_moves.insert(moved.id);
            self.view_move = Some(moved.id);
            self.expr(e, Demand::Consume);
            self.view_move = None;
        } else {
            self.expr(e, Demand::Read);
        }
        true
    }

    /// The one operand a plain lending call `e` hands back whole (`relay(x)` for
    /// `relay(e: Error) Error: return e`), when it is a name of an interface view local at its
    /// last use: moving the local into the call lets the caller keep its box as the result.
    fn whole_lent_operand<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        if !matches!(e.kind, ExprKind::Call { .. }) {
            return None;
        }
        let lend = call_lend(self.cx.m, e, self.cx.summaries);
        if !lend.lends || lend.view {
            return None;
        }
        let operands = self.lend_operands(e, &lend)?;
        let [operand] = operands.as_slice() else {
            return None;
        };
        let Some((_, fields)) = &lend.path else {
            return None;
        };
        let Resolution::Local(b) = self.cx.m.resolution(operand) else {
            return None;
        };
        (fields.is_empty()
            && matches!(operand.kind, ExprKind::Name(_))
            && self.view_locals.contains(&b.uid)
            && b.ty.kind == Kind::Contract
            && self.is_last(operand.id, &b))
        .then_some(*operand)
    }

    /// The expression a conversion to an interface reads, when `e` converts a `Move`-class
    /// value: `e` itself (`cause` as `Error`, a widened lending call, `cause` as `Error?`), or
    /// the payload of `ok(x)` / `error(x)`. `None` when nothing is converted or the source is a
    /// scalar, which the interface copies.
    fn view_source<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let converted = |x: &Expr| {
            // A conversion to an interface with a `var fn` copies: a call through the view
            // could change leaves the view only borrows.
            let target = self.cx.m.ty(x);
            let iface = if target.is_std("Result") {
                target.args.get(1).cloned()
            } else {
                Some(target)
            };
            if iface.is_none_or(|t| crate::types::contract_mutates(&t)) {
                return false;
            }
            self.cx
                .m
                .info(x)
                .error_source
                .as_ref()
                .is_some_and(|src| self.cx.classes.class(src) == Class::Move)
        };
        if converted(e) {
            return Some(e);
        }
        let x = self.result_payload(e)?;
        converted(x).then_some(x)
    }

    /// Whether `e` is an interface view or holds one: a conversion of a lent value, a view
    /// lender's call, or a local holding a view.
    fn is_view(&self, e: &Expr) -> bool {
        self.view_source(e).is_some() || self.lend_source(e).is_some_and(|s| s.view)
    }

    /// Whether this callable implements an interface method. A call through the interface
    /// cannot know which implementation runs, so every implementation owns its result.
    fn implements_contract(&self) -> bool {
        let c = self.cx.c;
        if c.func.index.is_none() {
            return false;
        }
        let DeclKind::Impl(i) = &c.func.decl.0.decl.kind else {
            return false;
        };
        // A type's own methods are checked as an implementation of a synthesized interface.
        i.contract
            .as_ref()
            .is_some_and(|t| !t.name().ends_with(crate::passes::INHERENT_SUFFIX))
    }

    /// Whether the declared result type is an interface.
    fn result_is_interface(&self) -> bool {
        let c = self.cx.c;
        let result = match (c.func.method(), c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return false,
        };
        self.cx
            .m
            .type_ref(result)
            .is_some_and(|t| t.kind == Kind::Contract)
    }

    /// Whether a returned expression has the declared result type itself: a value converted on
    /// the way out (`Door` returned as `Door?`, a record as an interface) is a new value.
    fn returns_as_declared(&self, e: &Expr) -> bool {
        let c = self.cx.c;
        let result = match (c.func.method(), c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return false,
        };
        let Some(declared) = self.cx.m.type_ref(result) else {
            return false;
        };
        self.cx.m.info(e).error_source.is_none() && same(&self.cx.m.ty(e), &declared)
    }

    /// Reports a function that returns a reference on one path and an owned value on another:
    /// the caller could not tell whether to hold or drop the result.
    fn mixed_returns(&mut self) {
        if self.view_return {
            // Every path of a view lender returns an owned value. A plain reference to an
            // interface value is handed on as a view that owns nothing; a wrapper of a part
            // becomes a new value of its own, as beside an owned path; any other plain
            // reference has no owned form.
            for n in std::mem::take(&mut self.wrap_returns) {
                self.facts.view_wraps.remove(&n);
            }
            if self.plain_lent && !self.result_is_interface() {
                let lent = self.lent_return.unwrap_or_default();
                self.error(
                    lent,
                    format!(
                        "this function returns an interface view of its arguments on another path but a reference here; return `.{COPY}()` of the part, or convert it on every path"
                    ),
                );
            }
            return;
        }
        let (Some(owned), Some(lent)) = (self.owned_return, self.lent_return) else {
            return;
        };
        // A wrapper of a part is a reference only when every path lends; beside a new value it
        // is built as a new value of its own (its payload copied), as before.
        if !self.plain_lent {
            self.lent_return = None;
            for n in std::mem::take(&mut self.wrap_returns) {
                self.facts.view_wraps.remove(&n);
            }
            return;
        }
        self.error(
            owned,
            format!(
                "this function returns a reference into its arguments at {}:{} but a new value here; return `.clone()` of the part there, or build a new value on every path",
                lent.line, lent.column
            ),
        );
    }

    /// The arguments a lending call returns a reference into: the receiver and the parameters
    /// `lend` names, as written. `None` when one of them is converted on the way in (wrapped
    /// into an `Optional`, widened to an interface or another error type): the callee then lends
    /// a temporary, and the result is a new value of the caller's.
    fn lend_operands<'e>(&self, e: &'e Expr, lend: &Lend) -> Option<Vec<&'e Expr>> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return Some(Vec::new());
        };
        let mut out = Vec::new();
        if lend.receiver
            && let (ExprKind::Member { left, .. }, Resolution::Method(_)) =
                (&callee.kind, self.cx.m.resolution(e))
        {
            out.push(&**left);
        }
        let slots = self.cx.m.info(e).arguments.clone().unwrap_or_default();
        for (i, a) in args.iter().enumerate() {
            if slots.get(i).is_some_and(|s| lend.params.contains(&s.name)) {
                // A lent value converted to an interface on the way in is a view of it: what
                // the callee lends from the view is a reference into the value.
                if self.converted_argument(e, &a.value) && !self.converted_lend(&a.value) {
                    return None;
                }
                out.push(&a.value);
            }
        }
        // A copied argument is never lent from, whatever an optimistic summary says.
        out.retain(|a| self.class_of(a) != Class::Copy);
        Some(out)
    }

    /// Whether `arg` is a `Move`-class reference converted to an interface on the way in
    /// (`relay(cause)` for `relay(e: Error)`): the converted temporary is a view of it.
    fn converted_lend(&self, arg: &Expr) -> bool {
        self.view_source(arg).is_some_and(|x| std::ptr::eq(x, arg))
            && self.lend_source(arg).is_some()
    }

    /// Whether a lent operand of call `e` is a converted view temporary: the caller owns what
    /// the callee lends from it (the temporary itself when handed back whole, else a copy) and
    /// still holds the value it views.
    fn lends_through_view(&self, e: &Expr, lend: &Lend) -> bool {
        self.lend_operands(e, lend).is_some_and(|ops| {
            ops.iter()
                .any(|o| self.converted_lend(o) || self.is_view(o))
        })
    }

    /// Whether argument `arg` of call `e` is converted to its parameter's type on the way in.
    /// An argument whose type does not unify with the parameter's is converted; so is one
    /// wrapped into an `Optional`.
    fn converted_argument(&self, e: &Expr, arg: &Expr) -> bool {
        let Some(view) = self.cx.m.call(e) else {
            return true;
        };
        let Some(a) = view.arguments.iter().find(|a| a.expr.id == arg.id) else {
            return true;
        };
        // A widened error or interface value is recorded with its source type.
        if a.wrap_optional.is_some() || self.cx.m.info(arg).error_source.is_some() {
            return true;
        }
        let (sig, variables): (Option<Ty>, Vec<Ty>) = match &view.target {
            Resolution::Function(s) | Resolution::Constant(s) => {
                (s.ty.borrow().clone(), s.variables.borrow().clone())
            }
            Resolution::Method(m) => (Some(m.ty.clone()), m.variables.clone()),
            _ => return true,
        };
        let Some(sig) = sig else {
            return true;
        };
        let Some(p) = sig.params.iter().find(|p| p.name == a.slot.name) else {
            return true;
        };
        let mut vars = variable_set(&variables);
        vars.extend(variable_set(&sig.args));
        let mut bound = Subst::new();
        !unify(&p.ty, &self.cx.m.ty(arg), &vars, &mut bound)
    }

    /// The label of the parameter written at argument `i` of call `e`.
    fn argument_label(&self, e: &Expr, i: usize) -> Option<Name> {
        self.cx.m.info(e).arguments.as_ref()?.get(i).map(|s| s.name)
    }

    /// The value `e` wraps without adding storage on its way to a binding or a return: `e`
    /// itself when it is wrapped into an `Optional` (`x` as `x?`), or the payload of `ok(x)` /
    /// `error(x)`. `None` when the value is converted (an interface, a widened error).
    fn wrapped_lend<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let info = self.cx.m.info(e);
        if info.error_source.is_some() {
            return None;
        }
        if info.wrap_some.is_some() {
            return Some(e);
        }
        let inner = self.result_payload(e)?;
        let inner_info = self.cx.m.info(inner);
        (inner_info.error_source.is_none()
            && inner_info.wrap_some.is_none()
            && self.class_of(inner) != Class::Copy)
            .then_some(inner)
    }

    /// The error path of `try operand` returns the operand's error: a reference when the operand
    /// lends it from the arguments as it is, otherwise a new value, like any `return`.
    fn try_return(&mut self, e: &Expr, operand: &Expr) {
        if !self.captured.is_empty() || self.implements_contract() {
            return;
        }
        let result = match (self.cx.c.func.method(), self.cx.c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return,
        };
        let Some(declared) = self.cx.m.type_ref(result) else {
            return;
        };
        if self.cx.classes.class(&declared) == Class::Copy {
            return;
        }
        if self.class_of(operand) == Class::Move
            && let Some(src) = self.lend_source(operand)
        {
            self.lent_return.get_or_insert(e.pos);
            if src.view {
                // The error leaves as an interface view (converted on the way out, or a view
                // already): an owned value whose payload stays in the operand's sources.
                self.view_return = true;
            } else {
                self.facts.view_wraps.insert(e.id);
                self.wrap_returns.push(e.id);
            }
            self.lend_receiver |= src.receiver;
            for p in src.params {
                if !self.lend_params.contains(&p) {
                    self.lend_params.push(p);
                }
            }
            // The error is one case of the result, never a field chain of a source.
            self.lend_path = Some(None);
            return;
        }
        self.owned_return.get_or_insert(e.pos);
    }

    /// The payload expression of an `ok(x)` or `error(x)` constructor call.
    fn result_payload<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return None;
        };
        let Resolution::Constructor { ty, case: Some(_) } = self.cx.m.resolution(e) else {
            return None;
        };
        (ty.is_std("Result") && args.len() == 1 && args[0].name.is_none()).then(|| &args[0].value)
    }

    /// The parameters and receiver a returned expression is a part of, when it is one: a place
    /// rooted in a parameter or the receiver, or a lending call whose sources all are. `None`
    /// for an owned value, including a part of a local, a temporary or a default argument.
    fn lend_source(&self, e: &Expr) -> Option<LendSource> {
        // `ok(x)` and `error(x)` are references when `x` is: the wrapper adds no storage. A
        // payload converted on the way in (`error(cause)` as `Error`) or copied is a new value.
        if self.result_payload(e).is_some() {
            return self.lend_source(self.wrapped_lend(e)?);
        }
        // A field or element of what a lending call returns (`self.head().tags[0]`) is a part of
        // the same sources; a field chain extends the path, an element ends it.
        if let Some((call, fields)) = self.part_of_call(e) {
            let mut src = self.lend_source(call)?;
            // A part of an owned view is a part of a temporary.
            if src.view {
                return None;
            }
            src.path = match (src.path.take(), fields) {
                (Some((root, mut path)), Some(more)) => {
                    path.extend(more);
                    Some((root, path))
                }
                _ => None,
            };
            return Some(src);
        }
        if self.is_place(e) {
            let root = match &e.kind {
                ExprKind::Name(_) => e,
                _ => self.root_name(e)?,
            };
            let Resolution::Local(b) = self.cx.m.resolution(root) else {
                return None;
            };
            let m = self.meta.get(&b.uid)?;
            if self.consumed.contains(&b.uid) {
                return None;
            }
            let path = self.field_path(e);
            if matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed) {
                // A reference held by a local: a part of whatever it borrows, if those are all
                // parameters or the receiver.
                let mut out = LendSource {
                    receiver: false,
                    params: Vec::new(),
                    path: None,
                    view: self.view_locals.contains(&b.uid),
                };
                let places = self.pure_places(e)?;
                for place in places {
                    let origin = self.meta.get(&place.root)?;
                    match (origin.role, origin.parameter) {
                        (Role::SelfValue, _) => out.receiver = true,
                        (Role::Parameter, Some(i)) => {
                            let label = self.parameter_label(i)?;
                            if !out.params.contains(&label) {
                                out.params.push(label);
                            }
                        }
                        _ => return None,
                    }
                }
                return Some(out);
            }
            return match (m.role, m.parameter) {
                (Role::SelfValue, _) => Some(LendSource {
                    receiver: true,
                    params: Vec::new(),
                    path: path.map(|f| (None, f)),
                    view: false,
                }),
                (Role::Parameter, Some(i)) => {
                    let label = self.parameter_label(i)?;
                    Some(LendSource {
                        receiver: false,
                        params: vec![label],
                        path: path.map(|f| (Some(label), f)),
                        view: false,
                    })
                }
                _ => None,
            };
        }
        if let ExprKind::Call { .. } = &e.kind {
            let lend = call_lend(self.cx.m, e, self.cx.summaries);
            if !lend.lends {
                return None;
            }
            let operands = self.lend_operands(e, &lend)?;
            if operands.is_empty() {
                return None;
            }
            let mut out = LendSource {
                receiver: false,
                params: Vec::new(),
                path: None,
                view: lend.view,
            };
            let mut paths: Vec<Option<(Option<Name>, Vec<Name>)>> = Vec::new();
            for (k, operand) in operands.iter().enumerate() {
                let src = self.lend_source(operand)?;
                out.view |= src.view || self.view_source(operand).is_some();
                out.receiver |= src.receiver;
                for p in src.params {
                    if !out.params.contains(&p) {
                        out.params.push(p);
                    }
                }
                // The callee's one field chain, continued from this operand's own chain.
                let through = match (&lend.path, k, &src.path) {
                    (Some((None, fields)), 0, Some((root, mine))) if lend.receiver => {
                        Some((*root, [mine.clone(), fields.clone()].concat()))
                    }
                    (Some((Some(label), fields)), _, Some((root, mine)))
                        if self.lend_operand_label(e, operand) == Some(*label) =>
                    {
                        Some((*root, [mine.clone(), fields.clone()].concat()))
                    }
                    _ => None,
                };
                paths.push(through);
            }
            out.path = if operands.len() == 1 {
                paths.pop().flatten()
            } else {
                None
            };
            return Some(out);
        }
        None
    }

    /// The lending call a projection chain starts from, with the fields from it when the chain
    /// is fields only (`None` for an element).
    fn part_of_call<'e>(&self, e: &'e Expr) -> Option<(&'e Expr, Option<Vec<Name>>)> {
        match &e.kind {
            ExprKind::Member { left, name } => {
                if let ExprKind::Call { .. } = &left.kind {
                    return self.lends(left).then_some((&**left, Some(vec![*name])));
                }
                let (call, fields) = self.part_of_call(left)?;
                Some((
                    call,
                    fields.map(|mut f| {
                        f.push(*name);
                        f
                    }),
                ))
            }
            ExprKind::Index { left, .. }
            | ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => {
                if let ExprKind::Call { .. } = &left.kind {
                    return self.lends(left).then_some((&**left, None));
                }
                let (call, _) = self.part_of_call(left)?;
                Some((call, None))
            }
            _ => None,
        }
    }

    /// Whether a call hands back a reference into its operands.
    fn lends(&self, call: &Expr) -> bool {
        self.class_of(call) != Class::Copy
            && (self.native_lend_receiver(call).is_some()
                || call_lend(self.cx.m, call, self.cx.summaries).lends)
    }

    /// The label of the parameter `operand` is written for in call `e`.
    fn lend_operand_label(&self, e: &Expr, operand: &Expr) -> Option<Name> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return None;
        };
        let i = args.iter().position(|a| a.value.id == operand.id)?;
        self.argument_label(e, i)
    }

    /// The label of parameter `i` of this callable.
    fn parameter_label(&self, i: usize) -> Option<Name> {
        let c = self.cx.c;
        let params: &[ms_syntax::ast::Param] = match (c.func.method(), c.func.func()) {
            (Some(m), _) => &m.func.params,
            (None, Some(f)) => &f.params,
            (None, None) => &[],
        };
        params.get(i).map(|p| p.name)
    }

    /// Whether `e` is a native read that lowering lends in place (`crates/ms-lower/src/lend.rs`):
    /// `m.get(key)` on a `Map`, `xs.first()` or `xs.last()` on a `List`, with the receiver written.
    fn native_lend_receiver<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        let Resolution::Method(method) = self.cx.m.resolution(e) else {
            return None;
        };
        if method.native.as_str().is_empty() {
            return None;
        }
        let recv = self.cx.m.ty(left);
        let lends = match (name.as_str(), args.len()) {
            ("get", 1) => recv.is_std("Map"),
            ("first" | "last", 0) => recv.is_std("List"),
            _ => false,
        };
        lends.then_some(&**left)
    }

    /// Whether `e` is `map.get(key)` on a `Map`: an entry read in place.
    fn map_get(&self, e: &Expr) -> bool {
        let ExprKind::Call { callee, args } = &e.kind else {
            return false;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return false;
        };
        name.as_str() == "get"
            && args.len() == 1
            && self.cx.m.ty(left).is_std("Map")
            && matches!(self.cx.m.resolution(e), Resolution::Method(m) if !m.native.as_str().is_empty())
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
                parent: None,
                deferred: None,
            },
        );
        self.declared.push(b.uid);
        self.facts.bindings.insert(
            b.uid,
            BindingFacts {
                binding: b.clone(),
                role,
                class,
                owned: !matches!(perm, Perm::Borrowed | Perm::MutBorrowed)
                    && !matches!(
                        role,
                        Role::Parameter | Role::SelfValue | Role::LambdaParameter | Role::Fixture
                    ),
                borrows: Vec::new(),
                exclusive: false,
            },
        );
    }

    /// Declares a `var` binding that holds `origins` exclusively.
    fn declare_mut_borrow(
        &mut self,
        b: &BindingRef,
        role: Role,
        origins: Vec<Place>,
        pos: Pos,
        parent: Option<usize>,
    ) {
        self.declare(b, role, Perm::MutBorrowed, None, false);
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.parent = parent;
        }
        if let Some(f) = self.facts.bindings.get_mut(&b.uid) {
            f.owned = false;
            f.exclusive = true;
            f.borrows = origins.clone();
        }
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.origins = origins.clone();
        }
        self.active.push(Borrow {
            holder: b.uid,
            holder_name: b.name,
            origins: origins.into_iter().map(|p| (p, true)).collect(),
            pos,
            why: "mutable borrow".to_string(),
        });
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

    /// Remembers the scrutinee a borrowed part would make consume its parameter.
    fn defer(&mut self, b: &BindingRef, source: &Scrutinee) {
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.deferred = source.deferred;
        }
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

    /// Reports like `error_fix`, when a fix could be built.
    fn error_fix_opt(&mut self, pos: Pos, message: impl Into<String>, fix: Option<DiagnosticFix>) {
        match fix {
            Some(fix) => self.error_fix(pos, message, fix),
            None => self.error(pos, message),
        }
    }

    /// Reports like `error`, with a machine-applicable fix.
    fn error_fix(&mut self, pos: Pos, message: impl Into<String>, fix: DiagnosticFix) {
        let message = message.into();
        self.error(pos, message.clone());
        if let Some(d) = self.diags.last_mut()
            && d.pos == pos
            && d.message == message
        {
            d.fix = Some(fix);
        }
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
            !ignore.is_some_and(|i| self.related(a.holder, i))
                && a.origins
                    .iter()
                    .any(|(o, _)| places.iter().any(|p| p.overlaps(o)))
        });
        if let Some(a) = found {
            let (holder, why, bpos) = (a.holder_name, a.why.clone(), a.pos);
            let held_ty = self.meta.get(&a.holder).map(|m| m.binding.ty.clone());
            let remedy = if holder.as_str() == "for" {
                format!("iterate over a copy instead: `for ... in {shown}.{COPY}()`")
            } else if held_ty.as_ref().and_then(no_clone).is_some() {
                format!(
                    "or give `{holder}` its own value by converting a clone of the concrete value"
                )
            } else {
                format!(
                    "or give `{holder}` its own value by ending its initializer with `.{COPY}()`"
                )
            };
            self.error(
                pos,
                format!(
                    "cannot {what} `{shown}` while `{holder}` borrows it ({why}, at {}:{}); finish using `{holder}` before this, {remedy}",
                    bpos.line, bpos.column
                ),
            );
        }
    }

    /// Reports a read of `places` while a closure or a `var` borrow holds them
    /// exclusively; `reader` is the binding the read goes through.
    fn check_read(&mut self, pos: Pos, places: &[Place], shown: &str, reader: usize) {
        let found = self.active.iter().find(|a| {
            !self.related(a.holder, reader)
                && a.origins
                    .iter()
                    .any(|(o, exclusive)| *exclusive && places.iter().any(|p| p.overlaps(o)))
        });
        if let Some(a) = found {
            let (holder, bpos, why) = (a.holder_name, a.pos, a.why.clone());
            let text = if why == "mutable borrow" {
                format!(
                    "cannot use `{shown}` while `{holder}` (a mutable borrow at {}:{}) holds it; finish using `{holder}` first, or use the value through `{holder}`",
                    bpos.line, bpos.column
                )
            } else {
                format!(
                    "cannot use `{shown}` while closure `{holder}` (made at {}:{}) changes it; call or drop the closure first, or copy the value before creating it",
                    bpos.line, bpos.column
                )
            };
            self.error(pos, text);
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
            // A bound method (`value.method` as a function value) is a new closure, not a part.
            ExprKind::Member { left, .. } => {
                self.cx.m.ty(e).kind != Kind::Function && self.is_place(left)
            }
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
            Some(m)
                if matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed)
                    && !m.origins.is_empty() =>
            {
                m.origins.iter().map(|o| o.join(&p.path)).collect()
            }
            _ => vec![p.clone()],
        }
    }

    /// The step for `left[index]`: a list element at a non-negative literal index is told apart
    /// from the others; every other element access may alias any element.
    fn element_step(&self, left: &Expr, index: &Expr) -> Step {
        let ExprKind::Number(t) = &index.kind else {
            return Step::Element;
        };
        let literal = || ms_syntax::number::canonical(t.as_str()).parse::<u64>().ok();
        if self.cx.m.ty(left).is_std("List")
            && !t.as_str().contains(['.', 'e', 'E'])
            && !t.ends_with('d')
        {
            return literal().map_or(Step::Element, Step::Index);
        }
        Step::Element
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
                    through_ref: None,
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
                let p = p.then(self.element_step(left, index));
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
                let p = p.then(self.element_step(left, v));
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
                    self.returned(e);
                }
            }
            StmtKind::Break | StmtKind::Continue => {}
            StmtKind::If {
                binding,
                mutable,
                cond,
                body,
                else_body,
            } => self.if_stmt(s, binding.as_ref(), *mutable, cond, body, else_body),
            StmtKind::While { cond, body } => {
                self.expr(cond, Demand::Read);
                self.release_pending();
                let entry = self.active.clone();
                self.block(body);
                self.active = Self::join_active(entry, std::mem::take(&mut self.active));
            }
            StmtKind::For { iter, body, .. } => match self.cx.m.stmt(s).expansion {
                // A `for` over an `Iterator` is the loop the checker expanded it into.
                Some(expansion) => self.block(&expansion),
                None => self.for_stmt(s, iter, body),
            },
        }
    }

    fn if_stmt(
        &mut self,
        s: &Stmt,
        binding: Option<&Pattern>,
        mutable: bool,
        cond: &Expr,
        body: &[Stmt],
        else_body: &[Stmt],
    ) {
        let mark = self.declared.len();
        let arm_mark = self.active.len();
        match binding {
            Some(p) => {
                // A scalar entry is copied out of the map, so the entry's place is the map itself.
                let probed = match &cond.kind {
                    ExprKind::Probe(target) if mutable => Some(&**target),
                    ExprKind::Call { callee, .. } if mutable && self.map_get(cond) => {
                        match &callee.kind {
                            ExprKind::Member { left, .. } => Some(&**left),
                            _ => None,
                        }
                    }
                    _ => None,
                };
                let scrutinee = self.scrutinee(s.id, probed.unwrap_or(cond));
                if mutable {
                    self.mutable_payload(p, cond, &scrutinee);
                    self.payload_resource(s, p, cond, &scrutinee);
                } else {
                    self.pattern_bindings(p, &scrutinee, Role::Pattern);
                    self.payload_resource(s, p, cond, &scrutinee);
                }
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

    /// An `if let name = value` that owns a resource payload closes it when the branch ends,
    /// unless the branch moves it on.
    fn payload_resource(&mut self, s: &Stmt, p: &Pattern, value: &Expr, source: &Scrutinee) {
        if !source.owned || !matches!(p.kind, PatternKind::Name(_)) {
            return;
        }
        let Some(b) = self.cx.m.pattern_binding(p) else {
            return;
        };
        if self.may_close(&b.ty) && !self.derived_from_resource(value) {
            let closable = self.closable(s, &b.ty);
            self.resources.push((b.uid, b.name, p.pos, closable));
        }
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
                // An owned iteration hands each resource element to the loop variable, which
                // closes it at the end of the iteration unless the body moves it on.
                if class == Class::Resource
                    && source.owned
                    && matches!(b.ty.kind, Kind::Record | Kind::Alternative | Kind::Native)
                {
                    self.resources.push((b.uid, b.name, iter.pos, true));
                }
            } else {
                self.declare_borrow(
                    &b,
                    Role::Loop,
                    source.origins.clone(),
                    iter.pos,
                    "loop variable",
                );
                self.defer(&b, &source);
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
            let role = if mutable { Role::Var } else { Role::Pattern };
            self.pattern_bindings(pattern, &scrutinee, role);
            return;
        };
        let Some(b) = self.cx.m.pattern_binding(pattern) else {
            self.expr(value, Demand::Consume);
            return;
        };
        let role = if mutable { Role::Var } else { Role::Let };
        if !mutable {
            self.let_pos.insert(b.uid, s.pos);
        }
        let class = self.cx.classes.class(&b.ty);
        // `var x = handle.get()` would change a copy, not the shared value.
        if mutable
            && class != Class::Copy
            && let ExprKind::Call { callee, .. } = &value.kind
            && let ExprKind::Member { left, .. } = &callee.kind
            && self.copy_handle(left)
        {
            let text = self.expr_text(value);
            self.expr(value, Demand::Read);
            self.error(
                pattern.pos,
                format!(
                    "`var {}` cannot borrow `{text}` mutably: it is a read-only result; copy it with `{text}.{COPY}()` to own it",
                    b.name
                ),
            );
            self.declare(&b, role, Perm::Mutable, None, false);
            return;
        }
        // A scalar copies, `let` or `var`; any other binding of a place borrows it, shared for
        // `let` and exclusive for `var`.
        if class != Class::Copy
            && let Some(origins) = self.projection_origins(value)
        {
            // Reading part of a value that stays where it is.
            if mutable && let ExprKind::Call { .. } = &value.kind {
                self.bind_getter(s, &b, role, value);
                return;
            }
            if mutable {
                if let Some((info, _)) = self.place(value) {
                    // The origin must itself be changeable and free of other borrows.
                    let before = self.diags.len();
                    self.mutate(pattern.pos, &info, "borrow mutably");
                    if self.diags.len() == before {
                        let parent = self.borrow_parent(&info.root);
                        self.declare_mut_borrow(&b, role, info.resolved, pattern.pos, parent);
                    } else {
                        // Already reported; an owned binding avoids a cascade.
                        self.declare(&b, role, Perm::Mutable, None, false);
                    }
                } else if class == Class::Copy {
                    // A scalar computed by a call has no place to borrow; the binding owns it.
                    self.expr(value, Demand::Read);
                    self.declare(&b, role, Perm::Mutable, None, false);
                } else {
                    let text = self.expr_text(value);
                    self.expr(value, Demand::Read);
                    self.error(
                        pattern.pos,
                        format!(
                            "`var {}` cannot borrow `{text}` mutably: it is a read-only result; copy it with `{text}.{COPY}()` to own it",
                            b.name
                        ),
                    );
                    self.declare(&b, role, Perm::Mutable, None, false);
                }
            } else {
                // A part wrapped on the way in (`let o: String? = r.name`) stays a reference.
                if self.wrapped_lend(value).is_some() {
                    self.facts.view_wraps.insert(value.id);
                }
                // A part converted to an interface (`let e: Error = r.cause`) or a view
                // lender's result: the binding owns the view's box and borrows the sources.
                if self.is_view(value) {
                    self.view_locals.insert(b.uid);
                    if self.result_payload(value).is_some() {
                        self.view_calls.insert(value.id);
                    }
                }
                self.expr(value, Demand::Read);
                self.declare_borrow(&b, role, origins, pattern.pos, "binding of a part of it");
            }
            return;
        }
        // A name converted to an interface on the way into the binding (`let e: Error = cause`,
        // `let r: Int! = error(cause)`) is a view of it: the binding owns the view's box and
        // borrows the name, whether or not this is the name's last use.
        if !mutable
            && class != Class::Copy
            && let Some(inner) = self.view_source(value)
            && let ExprKind::Name(_) = &inner.kind
            && let Resolution::Local(src) = self.cx.m.resolution(inner)
            && self.meta.contains_key(&src.uid)
        {
            let origins = self.resolve(&Place::local(src.uid));
            self.view_locals.insert(b.uid);
            if self.result_payload(value).is_some() {
                self.view_calls.insert(value.id);
            }
            self.expr(value, Demand::Read);
            self.declare_borrow(&b, role, origins, pattern.pos, "binding of a view of it");
            return;
        }
        // A name wrapped on the way into the binding (`let o: Item? = item`, `let r = ok(x)`)
        // is a reference to it, as a plain name is, unless this is the source's last use.
        if !mutable
            && class != Class::Copy
            && let Some(inner) = self.wrapped_lend(value)
            && let ExprKind::Name(_) = &inner.kind
            && let Resolution::Local(src) = self.cx.m.resolution(inner)
            && let Some(src_meta) = self.meta.get(&src.uid)
            && self.cx.classes.class(&src.ty) != Class::Copy
            && (!self.is_last(inner.id, &src)
                || matches!(src_meta.perm, Perm::Borrowed | Perm::MutBorrowed))
        {
            let origins = self.resolve(&Place::local(src.uid));
            self.facts.view_wraps.insert(value.id);
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
        if let ExprKind::Lambda(_) = &value.kind {
            self.expr_lambda_binding(value, &b, role, mutable);
            return;
        }
        if let Some(recv) = self.changing_method_value(value) {
            self.method_value_binding(value, recv, &b, role, mutable);
            return;
        }
        // A name bound to another name of the same type is a reference to it: shared for `let`,
        // exclusive for `var` when the source can change (a `var` binding or borrow), as for a
        // part of it. A `var` of an immutable source takes the value over instead (below). Only
        // a primitive copies, and a binding of another type converts.
        if class != Class::Copy
            && let ExprKind::Name(_) = &value.kind
            && let Resolution::Local(src) = self.cx.m.resolution(value)
            && let Some(src_meta) = self.meta.get(&src.uid)
            && same(&src.ty, &b.ty)
            && (!mutable || matches!(src_meta.perm, Perm::Mutable | Perm::MutBorrowed))
            // At the source's last use the value moves instead, as before: the reference would
            // be indistinguishable, and `let tmp = a; a = b` keeps working.
            && (!self.is_last(value.id, &src)
                || matches!(src_meta.perm, Perm::Borrowed | Perm::MutBorrowed))
        {
            let origins = self.resolve(&Place::local(src.uid));
            if mutable {
                if let Some((info, _)) = self.place(value) {
                    let before = self.diags.len();
                    self.mutate(pattern.pos, &info, "borrow mutably");
                    if self.diags.len() == before {
                        let parent = self.borrow_parent(&info.root);
                        self.declare_mut_borrow(&b, role, origins, pattern.pos, parent);
                    } else {
                        self.declare(&b, role, Perm::Mutable, None, false);
                    }
                    return;
                }
            } else {
                // A view local named for the last time hands its box on: the new name is the
                // view local now, borrowing the same origins, and the old one owns nothing.
                // Named again later, the new name is a plain reference to the box.
                if self.view_locals.contains(&src.uid) && self.is_last(value.id, &src) {
                    let origins = self.meta[&src.uid].origins.clone();
                    self.view_locals.insert(b.uid);
                    self.facts.view_moves.insert(value.id);
                    self.view_move = Some(value.id);
                    self.expr(value, Demand::Consume);
                    self.view_move = None;
                    self.declare_borrow(&b, role, origins, pattern.pos, "binding of a view of it");
                    return;
                }
                // Named again later, the new name points at the view local's box, which ends
                // with it, not at what the view borrows.
                let origins = if self.view_locals.contains(&src.uid) {
                    vec![Place::local(src.uid)]
                } else {
                    origins
                };
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
        if self.may_close(&b.ty) && !self.derived_from_resource(value) {
            let closable = self.closable(s, &b.ty);
            self.resources.push((b.uid, b.name, pattern.pos, closable));
        }
    }

    /// `var x = f(b)` where `f` returns one chain of fields of one argument: an exclusive borrow of
    /// that place, which lowering names instead of calling `f` (`getter_borrows`). Any other
    /// reference result cannot be bound with `var`.
    fn bind_getter(&mut self, s: &Stmt, b: &BindingRef, role: Role, value: &Expr) {
        let pos = s.pos;
        let text = self.expr_text(value);
        let lend = call_lend(self.cx.m, value, self.cx.summaries);
        let operands = self.lend_operands(value, &lend).unwrap_or_default();
        let target = match (&lend.path, operands.as_slice()) {
            (Some((None, fields)), [recv]) if lend.receiver => Some((*recv, fields.clone())),
            (Some((Some(label), fields)), [arg])
                if self.lend_operand_label(value, arg) == Some(*label) =>
            {
                Some((*arg, fields.clone()))
            }
            _ => None,
        };
        let Some((operand, fields)) = target.filter(|(o, _)| self.is_place(o)) else {
            self.expr(value, Demand::Read);
            self.error(
                pos,
                format!(
                    "`var {}` cannot borrow `{text}` mutably: the result is a reference into more than one place; bind it with `let` to read it, or borrow the field it returns directly",
                    b.name
                ),
            );
            self.declare(b, role, Perm::Mutable, None, false);
            return;
        };
        let Some((mut info, _)) = self.place(operand) else {
            self.expr(value, Demand::Read);
            self.declare(b, role, Perm::Mutable, None, false);
            return;
        };
        info.resolved = info
            .resolved
            .iter()
            .map(|p| {
                fields
                    .iter()
                    .fold(p.clone(), |p, f| p.then(Step::Field(*f)))
            })
            .collect();
        info.text = text;
        let before = self.diags.len();
        self.mutate(pos, &info, "borrow mutably");
        if self.diags.len() == before {
            let parent = self.borrow_parent(&info.root);
            self.facts.getter_borrows.insert(value.id, fields);
            self.declare_mut_borrow(b, role, info.resolved, pos, parent);
        } else {
            self.declare(b, role, Perm::Mutable, None, false);
        }
    }

    /// `places` plus, for each one rooted in a local that holds borrows (a carrier or a closure),
    /// the sources it holds: a value derived from it (a call result, a binding of its `ref` field,
    /// a closure that captures it) must keep those sources unchanged too, even after the holder
    /// itself is gone.
    fn with_held(&self, places: Vec<Place>) -> Vec<Place> {
        let mut out = places.clone();
        for p in &places {
            let borrowed = self
                .meta
                .get(&p.root)
                .is_some_and(|m| matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed));
            if borrowed {
                continue;
            }
            for a in self.active.iter().filter(|a| a.holder == p.root) {
                for (o, _) in &a.origins {
                    if !out.contains(o) {
                        out.push(o.clone());
                    }
                }
            }
        }
        out
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
        if !escaping && !origins.is_empty() && self.used.contains(&b.uid) {
            self.active.push(Borrow {
                holder: b.uid,
                holder_name: b.name,
                origins,
                pos: value.pos,
                why: "closure capture".to_string(),
            });
        }
    }

    /// The receiver of a method value that changes it (`xs.append`).
    fn changing_method_value<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Member { left, .. } = &e.kind else {
            return None;
        };
        if self.cx.m.ty(e).kind != Kind::Function {
            return None;
        }
        let Resolution::Method(m) = self.cx.m.resolution(e) else {
            return None;
        };
        (receiver_mode(self.cx.summaries, &m) == Some(ParamMode::Mutate)).then_some(&**left)
    }

    /// Takes the receiver of a method value that changes it as a mutable borrow. The value
    /// shares the variable, so it cannot outlive the statement. Returns the place it holds.
    fn changing_method_use(&mut self, e: &Expr, recv: &Expr, escaping: bool) -> Vec<(Place, bool)> {
        if !self.is_place(recv) {
            // A temporary receiver has no other owner: the value keeps its own copy.
            self.expr(recv, Demand::Read);
            return Vec::new();
        }
        let whole = matches!(recv.kind, ExprKind::Name(_));
        let Some((info, _)) = self.place(recv).filter(|_| whole) else {
            self.error(
                e.pos,
                "a method value that changes its receiver must come from a variable, like `xs.append`; call the method, or write a closure",
            );
            return Vec::new();
        };
        if escaping {
            self.error(
                e.pos,
                format!("this method value changes `{0}`, so it cannot be returned, stored or passed to a consuming parameter; keep it local, or call the method instead", info.root.name),
            );
            return Vec::new();
        }
        self.mutate(e.pos, &info, "change");
        info.resolved.into_iter().map(|p| (p, true)).collect()
    }

    fn method_value_binding(
        &mut self,
        value: &Expr,
        recv: &Expr,
        b: &BindingRef,
        role: Role,
        mutable: bool,
    ) {
        let escaping = self.escaped.contains(&value.id);
        let origins = self.changing_method_use(value, recv, escaping);
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
        if !origins.is_empty() && self.used.contains(&b.uid) {
            self.active.push(Borrow {
                holder: b.uid,
                holder_name: b.name,
                origins,
                pos: value.pos,
                why: "method value".to_string(),
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
            // An escaping closure's captures are reported once by `lambda`.
            Perm::Mutable | Perm::Captured => {}
            // A scalar borrow is a name for its place: assigning writes through.
            Perm::MutBorrowed if m.class == Class::Copy => {}
            Perm::Immutable if m.parameter.is_some() => self.error(
                pos,
                format!("cannot assign to parameter `{name}`: it is not declared var; write `var {name}: <Type>` in the signature and `var` at every call"),
            ),
            Perm::MutBorrowed => self.error(
                pos,
                format!("cannot reassign `{name}`: it is a mutable borrow of another value; assign to its fields, or copy with `{name}.{COPY}()`"),
            ),
            Perm::Immutable | Perm::Borrowed => self.error(
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
        // `?.` desugars to a hidden `?N` binding of the payload. Changing it changes the
        // optional it was read from, so the binding becomes an exclusive borrow of that place.
        if root.name.as_str().starts_with('?') && perm != Perm::MutBorrowed {
            let Some(place) = self.chain_places.get(&root.uid).cloned() else {
                // Only a variable (or a part of one) can be changed through `?.`; a call result
                // such as `m.get(k)` is a read-only view.
                self.error(
                    pos,
                    format!("cannot {what} through `?.` on a value that is not a variable; bind it to a `var` first, or index the collection and assign"),
                );
                return;
            };
            // The read-only borrow `?N` held becomes the exclusive one.
            self.active.retain(|a| a.holder != root.uid);
            let before = self.diags.len();
            self.mutate(pos, &place, what);
            if self.diags.len() == before {
                let origins = place.resolved.clone();
                let parent = self.borrow_parent(&place.root);
                self.declare_mut_borrow(&root, role, origins, pos, parent);
            }
            return;
        }
        if let Some(field) = info.through_ref {
            self.error(
                pos,
                format!("cannot {what} `{text}`: `{field}` is a `ref` field, a read-only view of another value"),
            );
            return;
        }
        match perm {
            Perm::Mutable | Perm::Captured | Perm::MutBorrowed => {}
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
            Perm::Immutable if receiver => {
                let message = format!(
                    "cannot {what} `{text}`: this method does not change its receiver; declare it `var fn` to allow that"
                );
                match self.cx.c.func.method() {
                    Some(m) => self.error_fix(pos, message, insert_at(back(m.pos, 3), "var ")),
                    None => self.error(pos, message),
                }
            }
            Perm::Immutable if parameter.is_some() => {
                let message = format!(
                    "cannot {what} `{text}`: parameter `{}` is not declared var; write `var {}: <Type>` in the signature and pass `var` at every call",
                    root.name, root.name
                );
                let declared = match (self.cx.c.func.method(), self.cx.c.func.func()) {
                    (Some(m), _) => m.func.params.get(parameter.unwrap_or(0)).map(|p| p.pos),
                    (None, Some(f)) => f.params.get(parameter.unwrap_or(0)).map(|p| p.pos),
                    (None, None) => None,
                };
                match declared {
                    Some(at) => self.error_fix(pos, message, insert_at(at, "var ")),
                    None => self.error(pos, message),
                }
            }
            Perm::Immutable => {
                let _ = role;
                let message = format!(
                    "cannot {what} `{text}`: `{}` is declared with let, which is immutable including its contents; declare it `var {}` to change it",
                    root.name, root.name
                );
                match self.let_pos.get(&root.uid).copied() {
                    Some(at) => {
                        let end = Pos {
                            offset: at.offset + 3,
                            line: at.line,
                            column: at.column + 3,
                        };
                        self.error_fix(
                            pos,
                            message,
                            DiagnosticFix {
                                pos: at,
                                end,
                                replacement: "var".to_string(),
                            },
                        )
                    }
                    None => self.error(pos, message),
                }
            }
        }
        self.check_change(pos, &info.resolved, what, &text, Some(root.uid));
        self.mark_mutated(root.uid);
        self.record(info.root_node, &root, Access::Mutate);
    }

    /// A read through a place.
    fn read_place(&mut self, pos: Pos, info: &PlaceInfo) {
        let text = info.text.clone();
        self.check_read(pos, &info.resolved, &text, info.root.uid);
        let root = info.root.clone();
        self.record(info.root_node, &root, Access::Borrow);
    }

    // ------------------------------------------------------ patterns

    /// Evaluates a matched or destructured value and says how its parts are held.
    fn scrutinee(&mut self, stmt: NodeId, e: &Expr) -> Scrutinee {
        if self.is_place(e) {
            let class = self.class_of(e);
            let whole = matches!(e.kind, ExprKind::Name(_));
            let mut deferred = None;
            if whole
                && !std::mem::take(&mut self.keep_scrutinee)
                && class != Class::Copy
                && let Resolution::Local(b) = self.cx.m.resolution(e)
                && self.is_last(e.id, &b)
            {
                let owned_local = self.meta.get(&b.uid).is_some_and(|m| {
                    !matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed)
                        && m.role != Role::Parameter
                        && m.role != Role::SelfValue
                });
                // A parameter is borrowed unless a part of it is moved out of the match or loop.
                let param = self.is_consumable_param(&b);
                if owned_local || param && self.escaped.contains(&e.id) {
                    self.expr(e, Demand::Consume);
                    self.facts.consumed_scrutinees.insert(stmt);
                    return Scrutinee {
                        owned: true,
                        origins: Vec::new(),
                        deferred: None,
                    };
                }
                if param {
                    deferred = Some(e.id);
                }
            }
            let Some((info, _)) = self.place(e) else {
                return Scrutinee {
                    owned: true,
                    origins: Vec::new(),
                    deferred: None,
                };
            };
            self.read_place(e.pos, &info);
            return Scrutinee {
                owned: false,
                origins: info.resolved,
                deferred,
            };
        }
        if let Some(origins) = self.projection_origins(e) {
            self.expr(e, Demand::Read);
            return Scrutinee {
                owned: false,
                origins,
                deferred: None,
            };
        }
        self.expr(e, Demand::Consume);
        Scrutinee {
            owned: true,
            origins: Vec::new(),
            deferred: None,
        }
    }

    /// `if var name = value`: the payload is an exclusive borrow of the part of
    /// its origin the value reads in place, or an owned value otherwise.
    fn mutable_payload(&mut self, p: &Pattern, value: &Expr, source: &Scrutinee) {
        let Some(b) = self.cx.m.pattern_binding(p) else {
            return;
        };
        // `place[key]?` and `map.get(key)` both find an entry in place.
        let probe = matches!(value.kind, ExprKind::Probe(_)) || self.map_get(value);
        let value = match &value.kind {
            ExprKind::Probe(target) => &**target,
            _ => value,
        };
        let named = self.root_name(value);
        let root = named.and_then(|n| match self.cx.m.resolution(n) {
            Resolution::Local(r) => Some((r, n.id)),
            _ => None,
        });
        let (Some((root, root_node)), false) = (root, source.owned) else {
            self.declare(&b, Role::Pattern, Perm::Mutable, None, false);
            return;
        };
        let info = PlaceInfo {
            text: self.expr_text(value),
            root,
            root_node,
            resolved: source.origins.clone(),
            projection: true,
            through_ref: None,
        };
        if !probe {
            self.error(
                p.pos,
                format!(
                    "`if var` borrows an entry written as `place[key]?` or `map.get(key)`, but `{}` is not one; bind a copy with `if let`, then `var x = x.clone()`, or write the changed value back",
                    info.text
                ),
            );
            self.declare(&b, Role::Pattern, Perm::Mutable, None, false);
            return;
        }
        let before = self.diags.len();
        self.mutate(p.pos, &info, "borrow mutably");
        if self.diags.len() == before {
            let parent = self.borrow_parent(&info.root);
            self.declare_mut_borrow(&b, Role::Pattern, source.origins.clone(), p.pos, parent);
        } else {
            self.declare(&b, Role::Pattern, Perm::Mutable, None, false);
        }
    }

    /// The name expression a place chain or accessor call starts from.
    fn root_name<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        match &e.kind {
            ExprKind::Name(_) => Some(e),
            ExprKind::Member { left, .. }
            | ExprKind::Index { left, .. }
            | ExprKind::Apply { left, .. } => self.root_name(left),
            ExprKind::Call { callee, .. } => self.root_name(callee),
            _ => None,
        }
    }

    /// The mutable borrow a new borrow is taken through, if its root is one.
    fn borrow_parent(&self, root: &BindingRef) -> Option<usize> {
        self.meta
            .get(&root.uid)
            .filter(|m| m.perm == Perm::MutBorrowed)
            .map(|_| root.uid)
    }

    /// Whether `holder` is `of` or a mutable borrow `of` was taken through.
    fn related(&self, holder: usize, of: usize) -> bool {
        let mut cur = Some(of);
        while let Some(c) = cur {
            if c == holder {
                return true;
            }
            cur = self.meta.get(&c).and_then(|m| m.parent);
        }
        false
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
            let perm = if role == Role::Var {
                Perm::Mutable
            } else {
                Perm::Immutable
            };
            self.declare(b, role, perm, None, false);
        } else {
            self.declare_borrow(b, role, source.origins.clone(), pos, "pattern binding");
            self.defer(b, source);
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
        self.pure_origins(e)
    }

    /// The places a conditional's value is a reference into, when every arm yields one.
    fn arm_origins(&self, arms: &[Arm]) -> Option<Vec<Place>> {
        let mut out: Vec<Place> = Vec::new();
        for arm in arms {
            let v = arm.value.as_ref()?;
            // An owned view joined with plain references would leak or dangle.
            if self.is_view(v) {
                return None;
            }
            let places = if self.is_place(v) {
                self.pure_places(v)?
            } else {
                self.pure_origins(v)?
            };
            for p in places {
                // A payload of this match is not declared yet: it may own its part, which
                // ends with the arm.
                self.meta.get(&p.root)?;
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        Some(out)
    }

    /// The places a call result is a reference into, without evaluating it: the places of the
    /// arguments a lending callee returns a part of, or the container of a native read that is
    /// lent in place. `None` when the result owns, including when a source is a temporary.
    fn pure_origins(&self, e: &Expr) -> Option<Vec<Place>> {
        if self.class_of(e) == Class::Copy {
            return None;
        }
        if let ExprKind::Match { arms, .. } = &e.kind {
            return self.arm_origins(arms);
        }
        // `try f(a)` yields the payload of what `f` lends: a reference into the same places.
        if let ExprKind::Unary {
            op: UnaryOp::Try,
            operand,
        } = &e.kind
        {
            return if self.is_place(operand) {
                self.pure_places(operand)
            } else {
                self.pure_origins(operand)
            };
        }
        let ExprKind::Call { .. } = &e.kind else {
            return None;
        };
        let operands = match self.native_lend_receiver(e) {
            Some(recv) => vec![recv],
            None => {
                let lend = call_lend(self.cx.m, e, self.cx.summaries);
                if !lend.lends {
                    return None;
                }
                self.lend_operands(e, &lend)?
            }
        };
        if operands.is_empty() {
            return None;
        }
        let mut out = Vec::new();
        for operand in operands {
            let places = if self.is_place(operand) {
                self.pure_places(operand)?
            } else {
                self.pure_origins(operand)?
            };
            for p in places {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        Some(out)
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
            ExprKind::Member { left, name } => {
                let lefts = self.pure_places(left)?;
                let out: Vec<Place> = lefts.iter().map(|p| p.then(Step::Field(*name))).collect();
                Some(out)
            }
            ExprKind::Index { left, index } => {
                let step = self.element_step(left, index);
                Some(
                    self.pure_places(left)?
                        .iter()
                        .map(|p| p.then(step))
                        .collect(),
                )
            }
            ExprKind::Apply {
                left,
                value: Some(v),
                ..
            } => {
                let step = self.element_step(left, v);
                Some(
                    self.pure_places(left)?
                        .iter()
                        .map(|p| p.then(step))
                        .collect(),
                )
            }
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
        if d == Demand::Consume
            && let Some(src) = &self.cx.m.info(e).error_source
            && self.cx.classes.class(src) == Class::Resource
            && !declares_close(&self.cx.m.ty(e))
        {
            // An interface value is never closed for its owner, so owning a resource through one
            // drops its close, unless the interface hands the duty on with a `close` operation.
            let text = self.expr_text(e);
            let target = self.cx.m.ty(e);
            self.error(
                e.pos,
                format!("`{text}` is the resource `{src}`, and the `{target}` it would become never closes it; keep it as a `{src}` so its owner closes it, or pass it where `{target}` is only read"),
            );
        }
        if let Some(src) = self.cx.m.info(e).error_source.clone() {
            self.adapter_copies(e, &src);
        }
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Probe(_) => self.error(
                e.pos,
                "`?` after an index is only written as `if var name = place[key]?`, where it borrows the entry in place",
            ),
            ExprKind::Text(parts) => {
                let interps: Vec<&Expr> = parts
                    .iter()
                    .filter_map(|p| match p {
                        TextPart::Interp(i) => Some(i),
                        _ => None,
                    })
                    .collect();
                self.parts_overlap(e.pos, "this text", &interps);
                for i in interps {
                    self.expr(i, Demand::Read);
                }
            }
            ExprKind::Name(_) => match self.cx.m.resolution(e) {
                Resolution::Local(b) => self.use_local(e, &b, d),
                Resolution::Function(sym) if !self.callees.contains(&e.id) => {
                    if let Some(decl) = sym.decl.clone() {
                        let func = crate::syntax::FuncRef::of_decl(decl);
                        self.function_value_copies(e, sym.module, &func);
                    }
                }
                _ => {}
            },
            ExprKind::Member { .. } | ExprKind::Index { .. } | ExprKind::Apply { .. } => {
                if let (ExprKind::Member { .. }, Resolution::Method(m)) =
                    (&e.kind, self.cx.m.resolution(e))
                    && let Some(func) = m.decl.clone()
                {
                    // A method used as a value; calls take their receiver apart instead.
                    self.function_value_copies(e, m.module, &func);
                }
                // A generic function used as a value with its type arguments (`keep[T]`).
                if let ExprKind::Apply { .. } = &e.kind
                    && !self.callees.contains(&e.id)
                    && let Resolution::Function(sym) = self.cx.m.resolution(e)
                    && let Some(decl) = sym.decl.clone()
                {
                    let func = crate::syntax::FuncRef::of_decl(decl);
                    self.function_value_copies(e, sym.module, &func);
                }
                self.projection(e, d)
            }
            ExprKind::List(items) => {
                let parts: Vec<&Expr> = items.iter().collect();
                self.parts_overlap(e.pos, "this list", &parts);
                items.iter().for_each(|i| self.expr(i, Demand::Consume))
            }
            ExprKind::Map(entries) => {
                let parts: Vec<&Expr> = entries.iter().flat_map(|en| [&en.key, &en.value]).collect();
                self.parts_overlap(e.pos, "this map", &parts);
                for entry in entries {
                    self.expr(&entry.key, Demand::Consume);
                    self.expr(&entry.value, Demand::Consume);
                }
            }
            ExprKind::Unary { op, operand } => {
                if *op == UnaryOp::Try {
                    self.try_return(e, operand);
                }
                // `try` hands its payload on with the position's demand; a copied payload only
                // reads the result it comes out of.
                let inner = if *op == UnaryOp::Try && self.class_of(e) != Class::Copy {
                    d
                } else {
                    Demand::Read
                };
                self.expr(operand, inner);
            }
            ExprKind::Binary { left, right, op } => {
                self.parts_overlap(e.pos, &format!("`{}`", op.as_str()), &[left, right]);
                self.expr(left, Demand::Read);
                self.expr(right, Demand::Read);
            }
            ExprKind::Lambda(l) => {
                let escaping = d == Demand::Consume || self.escaped.contains(&e.id);
                self.lambda(e, l, escaping);
            }
            ExprKind::Call { callee, args } => self.call(e, callee, args, d),
            ExprKind::Match { scrutinee, arms } => self.match_expr(e, scrutinee, arms, d, false),
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
            self.check_read(e.pos, &resolved, b.name.as_str(), b.uid);
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
        if role == Role::LambdaParameter && self.cx.classes.class(&b.ty) == Class::Resource {
            // A function value is called with its arguments lent, so taking one would copy it,
            // and the caller still closes the original.
            self.error(
                e.pos,
                format!("cannot move `{name}` out: a function value only borrows its arguments, and the resource `{}` stays with its caller, which closes it; use `{name}` in place here", b.ty),
            );
            self.record(e.id, b, Access::Move);
            return;
        }
        if role == Role::LambdaParameter {
            // The lent argument is copied: in generic code its type must be `Clonable`.
            let t = b.ty.clone();
            self.require_clonable(
                e,
                &t,
                &format!("this function value keeps `{name}`, which it only borrows, so it"),
            );
        }
        if self.captured.iter().any(|c| c.contains(&b.uid)) && perm != Perm::Captured {
            if b.ty.kind == Kind::Function {
                self.error(
                    e.pos,
                    format!("this closure would move the function `{name}` out of the variable it captured, but a closure can run more than once; functions cannot be copied, so call `{name}` here or take it as a parameter of the closure"),
                );
            } else if self.cx.classes.class(&b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("this closure would move `{name}` out of the variable it captured, but a closure can run more than once, and a resource cannot be cloned; use `{name}` in place inside the closure"),
                );
            } else {
                self.error_fix_opt(
                    e.pos,
                    format!("this closure would move `{name}` out of the variable it captured, but a closure can run more than once; return `{name}.{COPY}()` instead"),
                    copy_after(e),
                );
            }
            self.record(e.id, b, Access::Move);
            return;
        }
        if matches!(perm, Perm::Borrowed | Perm::MutBorrowed | Perm::Captured)
            && self.view_move != Some(e.id)
        {
            // Moving a part out of a parameter's match or loop makes that scrutinee consume it;
            // the next pass of the fixpoint sees the parts as owned.
            if let Some(scrutinee) = self.meta[&b.uid].deferred {
                self.escaped.insert(scrutinee);
            }
            if self.cx.classes.class(&b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("cannot move `{name}` out: it only borrows its value ({}), and its owner closes it; a resource cannot be cloned, so use `{name}` in place", role_text(role, perm)),
                );
            } else if let Some(why) = no_clone(&b.ty) {
                self.error(
                    e.pos,
                    format!("cannot move `{name}` out: it only borrows its value ({}); {why}, so use `{name}` in place", role_text(role, perm)),
                );
            } else {
                self.error_fix(
                    e.pos,
                    format!("cannot move `{name}` out: it only borrows its value ({}); use `{name}.{COPY}()` to get an owned copy", role_text(role, perm)),
                    insert_at(forward(e.pos, name.as_str().len()), &format!(".{COPY}()")),
                );
            }
            self.record(e.id, b, Access::Move);
            return;
        } else if (var_param || (receiver && perm == Perm::Mutable))
            && self.cx.classes.class(&b.ty) == Class::Resource
        {
            self.error(
                e.pos,
                format!("cannot move `{name}` out of the function: the caller keeps ownership of a var parameter and closes it; a resource cannot be cloned, so change it in place"),
            );
        } else if var_param || (receiver && perm == Perm::Mutable) {
            self.error_fix_opt(
                e.pos,
                format!("cannot move `{name}` out of the function: the caller keeps ownership of a var parameter; return `{name}.{COPY}()` or change the value in place"),
                copy_after(e),
            );
        } else if !self.is_last(e.id, b) {
            let later = self
                .next_use(e.id, b)
                .map(|n| format!(" at {}", self.at(n)))
                .unwrap_or_default();
            if b.ty.kind == Kind::Function {
                self.error(
                    e.pos,
                    format!("`{name}` is moved here but used again{later}; a function value has one owner and cannot be cloned, so move it only at its last use or declare a named `fn`, which can be passed as often as needed"),
                );
            } else if self.cx.classes.class(&b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("`{name}` is moved here but used again{later}; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read"),
                );
            } else if let Some(why) = no_clone(&b.ty) {
                self.error(
                    e.pos,
                    format!("`{name}` is moved here but used again{later}; {why}, so move it only at its last use"),
                );
            } else {
                self.error_fix(
                    e.pos,
                    format!("`{name}` is moved here but used again{later}; a value has one owner, so pass `{name}.{COPY}()` to keep the original, or move it only at its last use"),
                    insert_at(forward(e.pos, name.as_str().len()), &format!(".{COPY}()")),
                );
            }
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
        if let Some(recv) = self.changing_method_value(e) {
            self.changing_method_use(
                e,
                recv,
                d == Demand::Consume || self.escaped.contains(&e.id),
            );
            return;
        }
        if !self.is_place(e) {
            // A part of a computed value. Copying a `Copy` part leaves the whole where it is.
            let take = d == Demand::Consume
                && self.class_of(e) != Class::Copy
                && self.cx.m.ty(e).kind != Kind::Function;
            if take
                && self.class_of(e) == Class::Resource
                && !matches!(
                    self.cx.m.resolution(e),
                    Resolution::Constructor { .. }
                        | Resolution::Function(_)
                        | Resolution::Constant(_)
                )
            {
                // Only a whole value moves: the resource would be copied out of a value that
                // still closes it.
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("cannot move `{text}` out of a computed value: a resource has one owner, and the value it comes from still closes it; bind the whole value first, then use the part in place"),
                );
            }
            match &e.kind {
                ExprKind::Member { left, .. } => {
                    self.expr(left, if take { Demand::Consume } else { Demand::Read })
                }
                ExprKind::Index { left, index } => {
                    self.parts_overlap(e.pos, "this index", &[left, index]);
                    self.expr(left, if take { Demand::Consume } else { Demand::Read });
                    self.expr(index, Demand::Read);
                }
                ExprKind::Apply { left, value, .. } => {
                    if let Some(v) = value {
                        self.parts_overlap(e.pos, "this index", &[left, v]);
                    }
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
        if d == Demand::Consume && class != Class::Copy && self.partial_move(e, &info, class) {
            return;
        }
        if d == Demand::Consume && class == Class::Resource {
            self.error(
                e.pos,
                format!(
                    "cannot move the resource `{0}` out of `{1}`: a resource cannot be cloned, and it leaves `{1}` only when `{1}` is a `let` or a parameter and no type on the path has a `close` of its own; use `{0}` in place, or move the whole `{1}`",
                    info.text, info.root.name
                ),
            );
        } else if d == Demand::Consume && class != Class::Copy {
            let message = if info.root.name.starts_with('?') {
                // The payload of an optional chain `a?.b`, which has no written name.
                format!(
                    "an optional chain `?.` cannot move a field out of the optional; take an owned copy by ending the access with `.{COPY}()`"
                )
            } else {
                format!(
                    "cannot move `{0}` out of `{1}`: only a whole variable can move; take an owned copy with `{0}.{COPY}()`",
                    info.text, info.root.name
                )
            };
            // A member's position is its name, so the copy goes right after it.
            match &e.kind {
                ExprKind::Member { name, .. } => self.error_fix(
                    e.pos,
                    message,
                    insert_at(forward(e.pos, name.as_str().len()), &format!(".{COPY}()")),
                ),
                _ => self.error(e.pos, message),
            }
        }
        self.read_place(e.pos, &info);
    }

    /// A field of an owned local or parameter moves out at its last use (`return b.items`,
    /// `f(b.items)`): the place is dead until it is stored again, and the rest of the value is
    /// still the binding's. Returns whether the move is accepted; if not, the caller reports
    /// that only a whole variable can move.
    fn partial_move(&mut self, e: &Expr, info: &PlaceInfo, class: Class) -> bool {
        let root = info.root.clone();
        let Some(meta) = self.meta.get(&root.uid) else {
            return false;
        };
        let owner = matches!(meta.perm, Perm::Immutable | Perm::Mutable)
            && !meta.is_receiver
            && !matches!(meta.role, Role::Fixture)
            && !(meta.parameter.is_some() && meta.perm == Perm::Mutable)
            && meta.lambda.is_none();
        let own_place = matches!(info.resolved.as_slice(), [only] if only.root == root.uid);
        if !owner
            || !own_place
            || class == Class::Copy
            || info.through_ref.is_some()
            || self.captured.iter().any(|c| c.contains(&root.uid))
        {
            return false;
        }
        // Only fields: an element of a collection stays where it is.
        let Some(path) = self.field_path(e) else {
            return false;
        };
        // A resource moves without a copy: only a `let` or a parameter, whose cleanup lowering
        // splits around the hole, and never a type parameter or a part of a closure capture.
        let resource = class == Class::Resource;
        if resource
            && (!matches!(meta.role, Role::Let | Role::Parameter)
                || meta.perm != Perm::Immutable
                || self.cx.m.ty(e).kind == Kind::Variable)
        {
            return false;
        }
        // A type that closes itself would close a record with a hole in it.
        let mut at = e;
        while let ExprKind::Member { left, .. } = &at.kind {
            let holder = self.cx.m.ty(left);
            if self.cx.classes.closes_itself(&holder) {
                return false;
            }
            at = left;
        }
        let last = self
            .cx
            .live
            .places
            .get(&(e.id, root.uid))
            .is_none_or(|u| u.last);
        if !last {
            let later = self
                .cx
                .live
                .places
                .get(&(e.id, root.uid))
                .and_then(|u| u.next)
                .map(|n| format!(" at {}", self.at(n)))
                .unwrap_or_default();
            self.error(
                e.pos,
                format!("`{0}` is moved here but used again{later}; a value has one owner, so use `{0}.{COPY}()` to keep the original, or move it only at its last use", info.text),
            );
            return true;
        }
        self.check_change(e.pos, &info.resolved, "move", &info.text, Some(root.uid));
        self.mark_mutated(root.uid);
        self.record(info.root_node, &root, Access::Borrow);
        if meta_is_parameter(self, root.uid) {
            self.consumed.insert(root.uid);
        }
        if resource {
            let at = self.facts.resource_moves.entry(root.uid).or_default();
            // The release at scope end tests one flag per moved place, so a place and a part of
            // it cannot both be moved.
            let clash = at.values().find(|o| {
                let n = o.len().min(path.len());
                o[..n] == path[..n] && o.len() != path.len()
            });
            if clash.is_some() {
                self.error(
                    e.pos,
                    format!(
                        "`{0}` and a part of it are both moved out of `{1}`: move the same field everywhere, or move the whole `{1}`",
                        info.text, root.name
                    ),
                );
                return true;
            }
            at.insert(e.id, path);
        }
        self.facts
            .partial_moves
            .insert(e.id, info.resolved[0].clone());
        true
    }

    // ---------------------------------------------------------- calls

    /// A copy of a value of `t` made by the language rather than by a call: a type parameter in
    /// `t` must be declared `Clonable`, as a call of a copying method requires.
    fn require_clonable(&mut self, e: &Expr, t: &Ty, what: &str) {
        if let Some(v) = unbounded_parameter(t) {
            self.error(
                e.pos,
                format!("{what} copies values of `{v}`, which may be a resource; declare `{v}: Clonable`"),
            );
        }
    }

    /// A conversion of `src` to the interface `e` has: an implementation that keeps a parameter
    /// the operation only lends is called through the interface with a copy of its argument. A
    /// resource cannot be copied, so the conversion is rejected; a type parameter passes the
    /// duty on to this callable, as a generic copy does.
    fn adapter_copies(&mut self, e: &Expr, src: &Ty) {
        let target = self.cx.m.ty(e);
        let Some(def) = &target.def else { return };
        let ops = def.operations.borrow().clone();
        for m in self.cx.methods {
            let (Some(contract), Some(decl)) = (&m.contract, &m.decl) else {
                continue;
            };
            if contract.id != target.id {
                continue;
            }
            let mut bound = Subst::new();
            if !unify(&m.receiver, src, &variable_set(&m.variables), &mut bound) {
                continue;
            }
            let Some(summary) = self.cx.summaries.get(&(m.module, decl.id())) else {
                continue;
            };
            let op = decl.name();
            let lent: Vec<Name> = ops
                .iter()
                .filter(|o| o.name == op)
                .filter_map(|o| o.decl.as_ref().and_then(|d| d.func()))
                .flat_map(|f| f.params.iter().filter(|p| !p.mutable).map(|p| p.name))
                .collect();
            for (name, mode) in &summary.params {
                if *mode != ParamMode::Consume || !lent.contains(name) {
                    continue;
                }
                let Some(p) = m.ty.params.iter().find(|p| p.name == *name) else {
                    continue;
                };
                let t = sub(&p.ty, &bound);
                if self.cx.classes.class(&t) == Class::Resource {
                    let text = self.expr_text(e);
                    self.error(
                        e.pos,
                        format!("`{text}` becomes a `{target}` whose `{op}` keeps its `{name}`, which the interface only lends, so every call through it hands over a copy; the resource `{t}` cannot be copied: pass something that is not a resource, or call `{src}`'s `{op}` directly"),
                    );
                } else {
                    let what = format!(
                        "`{text}` becomes a `{target}` whose `{op}` keeps its `{name}`, which the interface only lends, so it",
                        text = self.expr_text(e)
                    );
                    self.require_clonable(e, &t, &what);
                }
            }
        }
    }

    /// A named function used as a value is called with its arguments lent, so a parameter it
    /// keeps is a copy: rejected for a resource, a copy of the type parameter in generic code.
    fn function_value_copies(&mut self, e: &Expr, module: Name, func: &crate::syntax::FuncRef) {
        let Some(summary) = self.cx.summaries.get(&(module, func.id())) else {
            return;
        };
        let fty = self.cx.m.ty(e);
        for (i, (name, mode)) in summary.params.iter().enumerate() {
            if *mode != ParamMode::Consume {
                continue;
            }
            let Some(p) = fty.params.get(i) else { continue };
            if self.cx.classes.class(&p.ty) == Class::Resource {
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("`{text}` keeps its parameter `{name}`, but a function value only lends its arguments, so every call would hand it a copy; the resource `{}` cannot be copied: call `{text}` directly, or wrap it in a closure that uses `{name}` in place", p.ty),
                );
            } else {
                let t = p.ty.clone();
                let what = format!(
                    "`{}` keeps its parameter `{name}`, but a function value only lends its arguments, so it",
                    self.expr_text(e)
                );
                self.require_clonable(e, &t, &what);
            }
        }
    }

    fn call(&mut self, e: &Expr, callee: &Expr, args: &[Argument], d: Demand) {
        let cx = self.cx;
        let mut modes = call_modes(cx.m, e, args, cx.summaries);
        // `ok(x)` / `error(x)` kept as a reference (`view_wraps`) only reads its payload.
        if self.facts.view_wraps.contains(&e.id) || self.view_calls.contains(&e.id) {
            modes
                .arguments
                .iter_mut()
                .for_each(|m| *m = ParamMode::Borrow);
        }
        self.facts.calls.insert(e.id, modes.clone());
        let name = self.call_name(callee);
        let receiver_expr = match (&callee.kind, cx.m.resolution(e)) {
            (ExprKind::Member { left, .. }, Resolution::Method(_)) => Some(&**left),
            _ => None,
        };
        if let (ExprKind::Member { name, .. }, Some(r)) = (&callee.kind, receiver_expr)
            && name.as_str() == "close"
            && let Resolution::Local(b) = cx.m.resolution(r)
        {
            self.closed.insert(b.uid);
        }
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
                (ParamMode::Mutate, false) => self.error_fix(
                    a.value.pos,
                    format!("parameter `{param}` of `{name}` is declared var, so the call must say so; write `var {}`", self.expr_text(&a.value)),
                    insert_at(a.value.pos, "var "),
                ),
                (ParamMode::Borrow | ParamMode::Consume, true) => self.error_fix(
                    a.value.pos,
                    format!("`{name}` does not change its parameter `{param}`; remove `var` from the argument"),
                    DiagnosticFix {
                        pos: back(a.value.pos, 4),
                        end: a.value.pos,
                        replacement: String::new(),
                    },
                ),
                _ => {}
            }
        }
        // Evaluate in order. What an operand keeps hold of for the whole call
        // is checked against the others afterwards.
        let mut operands: Vec<Logged> = Vec::new();
        let reported = self.diags.len();
        if let Some(r) = receiver_expr {
            if self.cx.m.info(e).native_str() == "clone" && self.class_of(r) == Class::Resource {
                let text = self.expr_text(r);
                self.error(
                    e.pos,
                    format!("`{text}` holds a resource, which has one owner and cannot be cloned: a copy would be closed a second time; move it instead"),
                );
            }
            let mut mode = modes.receiver.unwrap_or(ParamMode::Borrow);
            // An owned resource taken out of a receiver that holds it (`o.get(default)`) is the
            // receiver's one owner handing it over, not a copy.
            if mode == ParamMode::Borrow
                && self.class_of(r) == Class::Resource
                && self.class_of(e) == Class::Resource
                && ty_contains(&self.cx.m.ty(r), &self.cx.m.ty(e))
            {
                mode = ParamMode::Consume;
            }
            let held = self.held(r, mode);
            self.receiver(r, mode);
            operands.push((Operand::Receiver(r), held, Vec::new()));
        } else {
            self.callees.insert(callee.id);
            self.expr(callee, Demand::Read);
        }
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            let mut held = self.held(&a.value, mode);
            held.extend(self.argument(a, mode, &modes, i));
            operands.push((Operand::Argument(&a.value), held, Vec::new()));
        }
        // An operand that already failed its own check is not reported twice. Only a held
        // place can clash, so the operands' inner changes are collected only when one is held.
        if self.diags.len() == reported && operands.iter().any(|(_, held, _)| !held.is_empty()) {
            for (operand, _, passing) in &mut operands {
                let x = match operand {
                    Operand::Receiver(x) | Operand::Argument(x) | Operand::Part(x) => *x,
                };
                *passing = self.nested_writes(x);
            }
            self.check_overlap(e.pos, &format!("`{name}`"), &operands);
        }
        // Results. A lending callee returns a reference into its arguments: holding it is a
        // borrow of them, storing or returning it needs a copy, and when a source is a
        // temporary the caller owns the result (lowering copies it out before the temporary
        // is dropped).
        let lend = call_lend(cx.m, e, cx.summaries);
        if lend.lends && self.class_of(e) != Class::Copy {
            match self.pure_origins(e) {
                Some(origins) if d == Demand::Consume => {
                    let mut roots: Vec<String> = origins
                        .iter()
                        .map(|p| self.name_of(p.root).as_str().to_string())
                        .collect();
                    roots.sort();
                    roots.dedup();
                    let ty = self.cx.m.ty(e);
                    if let Some(why) = no_clone(&ty) {
                        self.error(
                            e.pos,
                            format!(
                                "`{name}` returns a reference into `{}`, which this position would keep; {why}, so use it in place",
                                roots.join("`, `")
                            ),
                        );
                    } else {
                        self.error_fix_opt(
                            e.pos,
                            format!(
                                "`{name}` returns a reference into `{}`, which this position would keep; store `.{COPY}()` of it, or use it in place",
                                roots.join("`, `")
                            ),
                            copy_after(e),
                        );
                    }
                }
                Some(_) if self.lends_through_view(e, &lend) => {
                    // The callee lends from a view temporary of a held value: the caller owns
                    // the result (the view itself when it comes back whole) and holds the value.
                    let how = self.owned_lend(e, &lend, true);
                    self.facts.owned_lends.insert(e.id, how);
                }
                Some(_) => {}
                None => {
                    let how = self.owned_lend(e, &lend, false);
                    self.facts.owned_lends.insert(e.id, how);
                }
            }
        }
        if modes.returns_receiver && d != Demand::Discard {
            let recv = receiver_expr.map(|r| self.expr_text(r)).unwrap_or_default();
            self.error(
                e.pos,
                format!("`{name}` changes `{recv}` in place and its result cannot be used, because the collection has one owner; call it as a statement and keep using `{recv}`"),
            );
        }
    }

    /// How the caller owns the result of a lending call over a temporary: the whole of one
    /// temporary operand comes back (`id(make())`, or `relay(cause)` through a view temporary
    /// when `through_view`), so the caller keeps that temporary as the result instead of
    /// copying it; otherwise a copy is taken before the temporary is dropped.
    fn owned_lend(&self, e: &Expr, lend: &Lend, through_view: bool) -> OwnedLend {
        let whole = match (&lend.path, self.lend_operands(e, lend)) {
            (Some((source, fields)), Some(operands))
                if fields.is_empty()
                    && operands.len() == 1
                    && (through_view
                        || (!self.is_place(operands[0])
                            && !matches!(operands[0].kind, ExprKind::Name(_)))) =>
            {
                Some(*source)
            }
            _ => None,
        };
        match whole {
            Some(source) => OwnedLend::Whole(source),
            None => OwnedLend::Copy,
        }
    }

    fn call_name(&self, callee: &Expr) -> String {
        match &callee.kind {
            ExprKind::Name(n) => n.as_str().to_string(),
            ExprKind::Member { name, .. } => name.as_str().to_string(),
            ExprKind::Apply { left, .. } => self.call_name(left),
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

    /// The places changed or moved by the calls inside `e`, closures excluded: a `var` or
    /// consumed argument place, or a receiver changed in place.
    fn nested_writes(&mut self, e: &Expr) -> Vec<Place> {
        if let Some(v) = self.nested_cache.get(&e.id) {
            return v.clone();
        }
        let mut out = self.own_writes(e);
        let children: Vec<&Expr> = match &e.kind {
            ExprKind::Number(_)
            | ExprKind::Bool(_)
            | ExprKind::Unit
            | ExprKind::Name(_)
            | ExprKind::Lambda(_) => Vec::new(),
            ExprKind::Text(parts) => parts
                .iter()
                .filter_map(|p| match p {
                    TextPart::Interp(x) => Some(x),
                    _ => None,
                })
                .collect(),
            ExprKind::Member { left, .. } | ExprKind::Probe(left) => vec![left],
            ExprKind::Unary { operand, .. } => vec![operand],
            ExprKind::Apply { left, value, .. } => {
                std::iter::once(&**left).chain(value.as_deref()).collect()
            }
            ExprKind::Index { left, index }
            | ExprKind::Binary {
                left, right: index, ..
            } => {
                vec![left, index]
            }
            ExprKind::List(items) => items.iter().collect(),
            ExprKind::Map(entries) => entries.iter().flat_map(|en| [&en.key, &en.value]).collect(),
            ExprKind::Call { callee, args } => std::iter::once(&**callee)
                .chain(args.iter().map(|a| &a.value))
                .collect(),
            ExprKind::Match { scrutinee, arms } => std::iter::once(&**scrutinee)
                .chain(arms.iter().filter_map(|a| a.value.as_ref()))
                .collect(),
        };
        for child in children {
            for p in self.nested_writes(child) {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        self.nested_cache.insert(e.id, out.clone());
        out
    }

    /// The places one call changes or moves through its `var` and consumed operands.
    fn own_writes(&self, call: &Expr) -> Vec<Place> {
        let ExprKind::Call { callee, args } = &call.kind else {
            return Vec::new();
        };
        let modes = call_modes(self.cx.m, call, args, self.cx.summaries);
        let mut written: Vec<(&Expr, ParamMode)> = Vec::new();
        if let (ExprKind::Member { left, .. }, Resolution::Method(_)) =
            (&callee.kind, self.cx.m.resolution(call))
            && modes.receiver == Some(ParamMode::Mutate)
        {
            written.push((left, ParamMode::Mutate));
        }
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            if mode != ParamMode::Borrow {
                written.push((&a.value, mode));
            }
        }
        let mut out = Vec::new();
        for (operand, mode) in written {
            if !self.is_place(operand)
                || (mode == ParamMode::Consume && self.class_of(operand) == Class::Copy)
            {
                continue;
            }
            for p in self.pure_places(operand).unwrap_or_default() {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        out
    }

    /// The operands of one operator, index, literal or interpolation are computed in order,
    /// and one that lends or reads a place is held while the next runs; a change or move of
    /// that place by a later operand would leave a dangling reference.
    fn parts_overlap(&mut self, pos: Pos, name: &str, parts: &[&Expr]) {
        if parts.len() < 2 {
            return;
        }
        let mut operands: Vec<Logged> = parts
            .iter()
            .map(|p| {
                (
                    Operand::Part(p),
                    self.held(p, ParamMode::Borrow),
                    Vec::new(),
                )
            })
            .collect();
        // Only a held place can clash, so the operands' inner changes matter only then.
        if operands.iter().all(|(_, held, _)| held.is_empty()) {
            return;
        }
        for (part, _, passing) in &mut operands {
            let Operand::Part(p) = part else {
                unreachable!()
            };
            *passing = self.nested_writes(p);
        }
        self.check_overlap(pos, name, &operands);
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
    fn argument(
        &mut self,
        a: &Argument,
        mode: ParamMode,
        modes: &CallModes,
        index: usize,
    ) -> Vec<(Place, bool)> {
        // A native keeps this argument or hands it back in its result.
        let retained = modes.retained.get(index).copied().unwrap_or(false);
        match mode {
            ParamMode::Borrow => {
                if let ExprKind::Lambda(l) = &a.value.kind {
                    // Callbacks the callee runs and drops do not escape.
                    let escaping =
                        !modes.callbacks_borrowed || retained || self.escaped.contains(&a.value.id);
                    return self.lambda(&a.value, l, escaping);
                }
                self.expr(&a.value, Demand::Read);
                if retained
                    && self.cx.m.ty(&a.value).kind == Kind::Function
                    && let Resolution::Local(b) = self.cx.m.resolution(&a.value)
                {
                    // A function held by name is copied, so it stays usable here, but what the
                    // callee keeps must outlive this statement: its lambda and parameter escape.
                    if self.meta[&b.uid].parameter.is_some() {
                        self.consumed.insert(b.uid);
                    }
                    if let Some(l) = self.meta[&b.uid].lambda {
                        self.escaped.insert(l);
                    }
                }
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
    /// An operand's description, built only for a diagnostic: spelling a long call chain on every
    /// call would be quadratic in the chain.
    fn operand_text(&self, o: &Operand) -> String {
        match o {
            Operand::Receiver(e) => format!("the receiver `{}`", self.expr_text(e)),
            Operand::Argument(e) if matches!(e.kind, ExprKind::Lambda(_)) => {
                format!("the closure at {}", self.at(e.id))
            }
            Operand::Argument(e) => format!("argument `{}`", self.expr_text(e)),
            Operand::Part(e) => format!("operand `{}`", self.expr_text(e)),
        }
    }

    /// `context` names the call or expression the operands belong to, already quoted. A place an
    /// operand holds for the whole call clashes with a change of it by another operand: one held
    /// for the call, or one finished while that operand was computed, which leaves a held read
    /// or a held part dangling (a whole variable passed `var` keeps its slot).
    fn check_overlap(&mut self, pos: Pos, context: &str, operands: &[Logged]) {
        for (i, (label, log, passing)) in operands.iter().enumerate() {
            let writes = log
                .iter()
                .filter(|(_, w)| *w)
                .map(|(p, _)| (p, true))
                .chain(passing.iter().map(|p| (p, false)));
            for (place, held) in writes {
                let clash = operands.iter().enumerate().find(|(j, (_, other, _))| {
                    *j != i
                        && other
                            .iter()
                            .any(|(q, w)| q.overlaps(place) && (held || !*w || !q.path.is_empty()))
                });
                if let Some((_, (other, _, _))) = clash {
                    let (label, other) = (self.operand_text(label), self.operand_text(other));
                    self.error(
                        pos,
                        format!("{label} of {context} is changed in place but overlaps {other}; a changed value cannot also be read or changed through another operand, so pass distinct variables or copy one first"),
                    );
                    return;
                }
            }
        }
    }

    // ---------------------------------------------------------- match

    fn match_expr(&mut self, e: &Expr, scrutinee: &Expr, arms: &[Arm], d: Demand, returning: bool) {
        // A `?.` chain only borrows its receiver, even at its last use: a change through the
        // chain (`c?.bump()`) lands in the receiver.
        self.keep_scrutinee = arms.first().is_some_and(|a| a.chain);
        let source = self.scrutinee(e.id, scrutinee);
        self.keep_scrutinee = false;
        self.release_pending();
        // The value is a reference when every arm yields one and nothing consumes it: lowering
        // joins the arms without copying.
        let lent = !returning
            && d != Demand::Consume
            && self.class_of(e) != Class::Copy
            && self.arm_origins(arms).is_some();
        let lent_before = self.lent_return;
        let view_before = self.view_return;
        let entry = self.active.clone();
        let mut joined: Vec<Borrow> = Vec::new();
        for arm in arms {
            self.active = entry.clone();
            let mark = self.declared.len();
            for b in self.cx.m.arm(arm).bindings.iter().flatten() {
                if source.owned {
                    self.arm_payloads.push(b.uid);
                }
                self.payload(b, &source, Role::Arm, arm.pos);
                if arm.chain
                    && !source.owned
                    && let Some((info, _)) = self.place(scrutinee)
                {
                    self.chain_places.insert(b.uid, info);
                }
            }
            self.block(&arm.body);
            // `block` ended its own declarations; the arm bindings end here.
            if let Some(v) = &arm.value {
                if returning {
                    self.returned(v);
                } else {
                    self.expr(v, d);
                }
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
        // A returned match lends when its arms all did; a mix is reported by `mixed_returns`.
        let returned_lent = returning
            && self.owned_return.is_none()
            && self.lent_return != lent_before
            && self.view_return == view_before;
        if lent || returned_lent {
            self.facts.lent_matches.insert(e.id);
        }
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
                // Only a plain value is copied in. Anything else moves at its last use; when the
                // closure cannot take it over (it is borrowed or used again), `capture_move` asks
                // for an explicit `.clone()` rather than copying it silently.
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
                        through_ref: None,
                        text: b.name.as_str().to_string(),
                    };
                    self.mutate(e.pos, &info, "change");
                    facts.push((b.uid, CaptureMode::BorrowMut));
                } else if class == Class::Copy {
                    // A `Copy` value the closure only reads is borrowed like any other: the
                    // variable stays unchanged while the closure lives, so lowering may copy it.
                    self.check_read(e.pos, &resolved, b.name.as_str(), b.uid);
                    self.record(e.id, b, Access::Copy);
                    facts.push((b.uid, CaptureMode::Copy));
                } else {
                    self.check_read(e.pos, &resolved, b.name.as_str(), b.uid);
                    self.record(e.id, b, Access::Borrow);
                    facts.push((b.uid, CaptureMode::Borrow));
                }
                for p in self.with_held(resolved) {
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
        if matches!(perm, Perm::Borrowed | Perm::MutBorrowed | Perm::Captured) {
            if let Some(why) = no_clone(&b.ty) {
                self.error(
                    e.pos,
                    format!("this closure outlives the statement but captures `{name}`, which only borrows its value; {why}, so capture an owned value instead"),
                );
            } else {
                self.error_fix_opt(
                    e.pos,
                    format!("this closure outlives the statement but captures `{name}`, which only borrows its value; capture `{name}.{COPY}()` instead"),
                    copy_after(e),
                );
            }
        } else if !self.is_last(e.id, b) {
            let later = self
                .next_use(e.id, b)
                .map(|n| format!(" at {}", self.at(n)))
                .unwrap_or_default();
            if b.ty.kind == Kind::Function {
                self.error(
                    e.pos,
                    format!("this closure outlives the statement, so it takes `{name}` with it, but `{name}` is used again{later}; a function value cannot be cloned, so declare a named `fn` instead"),
                );
            } else if self.cx.classes.class(&b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("this closure outlives the statement, so it takes `{name}` with it, but `{name}` is used again{later}; a resource cannot be cloned, so use `{name}` only inside the closure, or capture it at its last use"),
                );
            } else {
                self.error_fix_opt(
                    e.pos,
                    format!("this closure outlives the statement, so it takes `{name}` with it, but `{name}` is used again{later}; capture `{name}.{COPY}()` to keep the original"),
                    copy_after(e),
                );
            }
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
    /// A parameter borrowed here that the match or loop would consume if a part moved out.
    deferred: Option<NodeId>,
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

/// Whether `part` is exactly one of the type arguments of `src`, at any depth.
fn ty_contains(src: &Ty, part: &Ty) -> bool {
    src.args
        .iter()
        .any(|a| crate::types::same(a, part) || ty_contains(a, part))
}

/// Whether `result` is an `Optional` or `Result` around a type `src` holds (or around another
/// such wrapper).
fn wraps_part(src: &Ty, result: &Ty) -> bool {
    (result.is_std("Optional") || result.is_std("Result"))
        && result
            .args
            .first()
            .is_some_and(|a| ty_holds(src, a) || wraps_part(src, a))
}

/// Whether `src` is `part` or has it among its type arguments, at any depth.
fn ty_holds(src: &Ty, part: &Ty) -> bool {
    src.id == part.id || src.args.iter().any(|a| ty_holds(a, part))
}

/// Whether `t` mentions a type parameter.
fn holds_variable(t: &Ty) -> bool {
    t.kind == Kind::Variable || t.args.iter().any(holds_variable)
}

/// Whether the binding is a parameter, whose caller loses it when a part of it moves.
fn meta_is_parameter(w: &Walker, uid: usize) -> bool {
    w.meta.get(&uid).is_some_and(|m| m.parameter.is_some())
}

/// The first type parameter in `t` not declared `Clonable`.
fn unbounded_parameter(t: &Ty) -> Option<Ty> {
    if t.kind == Kind::Variable {
        return (!t.bounds().iter().any(implies_clonable)).then(|| t.clone());
    }
    t.args.iter().find_map(unbounded_parameter)
}

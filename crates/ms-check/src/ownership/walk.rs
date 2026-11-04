//! The forward walk: classifies every use, tracks lexical borrows, and
//! reports the rules a program breaks.

use super::classify::{Class, Classifier, declares_close};
use super::live::Liveness;
use super::modes::{
    BORROWED_ERROR, BORROWED_OK, CallModes, ParamMode, ResultBorrow, Summaries, Summary,
    call_modes, receiver_mode, result_borrow,
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
const CLONE: &str = "clone";

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
    /// A function value a local holds, called: read in place while the arguments run.
    Callee(&'e Expr),
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
    /// Ownership is taken: a binding, return, stored element, moving argument.
    Move,
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
    ClosureOwned,
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

/// The module that declares `Promise`.
const PROMISE_MODULE: &str = "@std/concurrency/promise.ms";

/// The `why` of a borrow a promise holds on what its entry function captures. Unlike other borrows it
/// lasts until its holder's scope ends, because dropping the promise is what ends the work.
const PROMISE_WHY: &str = "promise capture";

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
struct BorrowSource {
    receiver: bool,
    params: Vec<Name>,
    /// The field chain from one source, when the expression is a plain chain of fields.
    path: Option<(Option<Name>, Vec<Name>)>,
    /// The value is an owned interface view of the sources (a view returner's result, or a local
    /// holding one): it is returned as an owned value, never as a plain reference.
    view: bool,
    /// The `Result` cases (`BORROWED_OK`, `BORROWED_ERROR`) the value borrows from the sources
    /// while its other cases are owned: a call of a function with a borrowing result.
    cases: u8,
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
        syms: ms_syntax::Names::global(),
        cx,
        facts: CallableOwnership::default(),
        diags: Vec::new(),
        meta: HashMap::new(),
        active: Vec::new(),
        pending: Vec::new(),
        carried: Vec::new(),
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
        borrow_receiver: false,
        borrow_params: Vec::new(),
        borrow_path: None,
        owned_return: None,
        borrowed_return: None,
        wrap_returns: Vec::new(),
        plain_borrowed: false,
        borrowed_cases: 0,
        owned_cases: 0,
        ret_ctors: Vec::new(),
        borrow_not_clonable: false,
        borrowed_mask: 0,
        view_return: false,
        view_locals: HashSet::new(),
        view_calls: HashSet::new(),
        view_move: None,
        self_assign: None,
        entry_lambda: None,
    };
    w.run();
    w.unclosed_resources();
    w.mixed_returns();
    w.consumed_param_resources();
    w.moved_payloads();
    let declared = Summary::declared(&cx.c.func);
    let summary = Summary {
        receiver: match (declared.receiver, w.receiver_consumed()) {
            (ParamMode::Borrow, true) => ParamMode::Move,
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
                    (ParamMode::Borrow, true) => (*name, ParamMode::Move),
                    (mode, _) => (*name, *mode),
                }
            })
            .collect(),
        result: ResultBorrow {
            // A view returner returns owned values on every path, so a new value beside a view
            // is no mix.
            returns_borrow: w.borrowed_return.is_some()
                && (w.owned_return.is_none() || w.view_return || w.borrowed_mask != 0),
            view: w.view_return || w.borrowed_mask != 0,
            borrowed_cases: w.borrowed_mask,
            receiver: w.borrow_receiver,
            params: w.borrow_params.clone(),
            path: if w.view_return {
                None
            } else {
                w.borrow_path.clone().flatten()
            },
        },
    };
    w.facts.returns_borrow = summary.result.returns_borrow;
    w.facts.view = summary.result.view;
    w.facts.borrowed_cases = summary.result.borrowed_cases;
    if summary.result.borrowed_cases != 0 {
        w.facts.ret_ctors = std::mem::take(&mut w.ret_ctors).into_iter().collect();
    }
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
    syms: ms_syntax::Names,
    cx: &'a Context<'a>,
    facts: CallableOwnership,
    diags: Vec<Diagnostic>,
    meta: HashMap<usize, Meta>,
    active: Vec<Borrow>,
    /// Holders whose last use ran in this statement: released at its end.
    pending: Vec<usize>,
    /// Promise borrows of a promise just moved on: its new holder (a binding, a local container)
    /// takes them over, so the borrow outlives the name that started the promise.
    carried: Vec<Borrow>,
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
    borrow_receiver: bool,
    borrow_params: Vec<Name>,
    borrow_path: Option<Option<(Option<Name>, Vec<Name>)>>,
    /// The first `return` of an owned value and of a reference, for the mixed-path error.
    owned_return: Option<Pos>,
    borrowed_return: Option<Pos>,
    /// Returned references that are wrappers (`x?`, `ok(x)`, the error of a `try`): beside an
    /// owned path they become new values again instead of an error.
    wrap_returns: Vec<NodeId>,
    /// Some returned reference is the part itself, not a wrapper of it.
    plain_borrowed: bool,
    /// `Result` cases (`BORROWED_OK`, `BORROWED_ERROR`, or 4 for another shape) the returned wrappers lend,
    /// and the cases the owned returns build (7 when unknown).
    borrowed_cases: u8,
    owned_cases: u8,
    ret_ctors: Vec<NodeId>,
    /// A borrowed part of a type that has one owner and no `clone`: the borrow is withdrawn
    /// beside an owned path, and the part moves out instead.
    borrow_not_clonable: bool,
    /// The wrappers stay references beside owned paths: the borrowed cases never overlap the owned ones.
    borrowed_mask: u8,
    /// Some returned value is an interface view of the arguments (a borrowed value converted to an
    /// interface, a view returner's result, a local holding one): the function is a view returner.
    view_return: bool,
    /// Locals that hold an interface view: they own the view's box and borrow its payload's
    /// origins, so they are returned as owned values, never borrowed as plain references.
    view_locals: HashSet<usize>,
    /// `ok(x)` / `error(x)` returned as views: their payload is read, not consumed.
    view_calls: HashSet<NodeId>,
    /// The name of a view local being returned: moving it out of the function is allowed even
    /// though it borrows, because the result holds the same origins.
    view_move: Option<NodeId>,
    /// The `var` parameter being reassigned (`exchange = wrap(exchange)`): moving it out on the
    /// right side is allowed, because the assignment refills it before the caller sees it.
    self_assign: Option<usize>,
    /// The lambda argument of a promise-starting call being walked: concurrent code.
    entry_lambda: Option<NodeId>,
}

/// A fix that inserts `text` at `pos`.
/// `.clone()` after the written expression `e`; none for a synthetic one.
/// Why a value of this type has no `.clone()`, for remedies that would otherwise suggest one.
fn no_clone(t: &Ty) -> Option<&'static str> {
    match t.kind {
        Kind::Function => Some("a function value cannot be cloned"),
        Kind::Contract if !t.is(Builtin::Closeable) => Some(
            "an interface value cannot be cloned (convert a clone of the concrete value instead)",
        ),
        _ => None,
    }
}

/// `no_clone`, and a record or alternative holding a function value, which `Classifier::clonable`
/// rejects.
fn clone_blocker(t: &Ty) -> Option<&'static str> {
    no_clone(t).or_else(|| {
        holds_function(t).then_some(
            "a value that holds a function cannot be cloned (a function value has one owner)",
        )
    })
}

fn copy_after(e: &Expr) -> Option<DiagnosticFix> {
    (e.end.offset > e.pos.offset).then(|| insert_at(e.end, &format!(".{CLONE}()")))
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
        match self.cx.classes.class(self.syms, ty) {
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
                        "`{name_t}` is a resource that is never closed: call `{name_t}.close()`, or return it so the caller owns it"
                    , name_t = self.syms.str(name)),
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
                && self.cx.classes.class(self.syms, &b.ty) == Class::Resource
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
            // A lambda never returns_borrow: an escaping closure owns its captures.
            self.expr(e, Demand::Move);
            return;
        }
        let reads = self.returned_promise_reads(e);
        if !reads.is_empty() {
            let names: Vec<&str> = reads.iter().map(|n| self.syms.str(n)).collect();
            self.error(
                e.pos,
                format!(
                    "this promise reads `{}`, which ends with this function; wait for the promise before returning, or start it from values that outlive the call",
                    names.join("`, `")
                ),
            );
        }
        // Each branch of a conditional or match expression is a returned value of its own.
        if let ExprKind::Match { scrutinee, arms } = &e.kind
            && arms.iter().all(|a| a.value.is_some())
        {
            self.match_expr(e, scrutinee, arms, Demand::Move, true);
            return;
        }
        // A borrowed value converted to an interface on the way out (`return cause` as `Error`,
        // `error(cause)` as `Int!`, a widened borrow-returning call), a view returner's result or a local
        // holding a view: the result is an owned view whose payload stays in the arguments.
        if !self.implements_contract() && self.view_return_source(e) {
            return;
        }
        // A resource is never borrowed: returning one hands it to the caller, which closes it.
        let wrapped = self.wrapped_borrow(e).is_some();
        if self.class_of(e) == Class::Move
            && (self.returns_as_declared(e) || wrapped)
            && !self.implements_contract()
            && !self.moves_withdrawn_borrow(e)
        {
            // A function that borrows some cases of its `Result` returned whole (`return
            // expect_ok(actual)`): this function borrows the same cases from the same sources and
            // owns the others.
            if let Some(src) = self.borrow_source(e).filter(|s| s.cases != 0)
                && self.result_is_result()
            {
                self.borrowed_return.get_or_insert(e.pos);
                self.borrowed_cases |= src.cases;
                self.owned_cases |= 3 & !src.cases;
                self.borrow_receiver |= src.receiver;
                for p in src.params {
                    if !self.borrow_params.contains(&p) {
                        self.borrow_params.push(p);
                    }
                }
                self.borrow_path = Some(None);
                self.expr(e, Demand::Read);
                return;
            }
            if let Some(src) = self.borrow_source(e).filter(|s| s.cases == 0) {
                // A part of an argument comes back as a reference into it: nothing moves. A
                // wrapper around it (`x?`, `ok(x)`) adds no storage and stays a reference too.
                self.borrowed_return.get_or_insert(e.pos);
                if wrapped {
                    self.facts.view_wraps.insert(e.id);
                    self.wrap_returns.push(e.id);
                    self.borrowed_cases |= self.wrap_case(e);
                    // A part that cannot be copied is moved out once the borrow is withdrawn
                    // (`moves_withdrawn_borrow`), which a caller's temporary source needs.
                    if let Some(inner) = self.wrapped_borrow(e)
                        && !self.cx.classes.clonable(self.syms, &self.cx.m.ty(inner))
                    {
                        self.borrow_not_clonable = true;
                    }
                    if self.result_case(e).is_some() {
                        self.ret_ctors.push(e.id);
                    }
                } else if !self.list_get(e) {
                    // `xs.get(i)` beside a new value is withdrawn like a wrapper, and the
                    // element is copied out; any other reference has no owned form.
                    self.plain_borrowed = true;
                }
                self.borrow_receiver |= src.receiver;
                for p in src.params {
                    if !self.borrow_params.contains(&p) {
                        self.borrow_params.push(p);
                    }
                }
                self.borrow_path = Some(match (self.borrow_path.take(), src.path) {
                    (None, path) => path,
                    (Some(Some(a)), Some(b)) if a == b => Some(a),
                    _ => None,
                });
                self.expr(e, Demand::Read);
                return;
            }
            // A bare `none` owns nothing, so a borrow-returning function can hand it back beside its references.
            if !matches!(&e.kind, ExprKind::Name(n) if self.syms.str(n) == "none") {
                self.owned_return.get_or_insert(e.pos);
                self.owned_cases |= self.owned_case(e);
                if self.result_case(e).is_some() {
                    self.ret_ctors.push(e.id);
                }
            }
        }
        // A reference converted on the way out (a borrow-returning call widened to another error type or
        // an interface) is read: the conversion builds the new value from it.
        let converted = self.cx.m.info(e).interface_source.is_some()
            && matches!(e.kind, ExprKind::Call { .. })
            && self.returns_borrow(e);
        self.expr(
            e,
            if converted {
                Demand::Read
            } else {
                Demand::Move
            },
        );
    }

    /// Whether a returned part is moved out instead of borrowed: an earlier round found this
    /// function returning a new value on another path and withdrew the borrow (`mixed_returns`), so
    /// the part would be copied out, and a value with one owner and no `clone` cannot be. Moving
    /// it moving_params the argument it came from, which the caller then hands over.
    fn moves_withdrawn_borrow(&self, e: &Expr) -> bool {
        let key = (self.cx.c.module.file, self.cx.c.id());
        self.cx
            .summaries
            .get(&key)
            .is_some_and(|s| !s.result.returns_borrow)
            && !self.cx.classes.clonable(self.syms, &self.cx.m.ty(e))
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
            Some(x) => self.borrow_source(x),
            None => self.borrow_source(e).filter(|s| s.view),
        };
        let Some(src) = src else {
            return false;
        };
        self.borrowed_return.get_or_insert(e.pos);
        self.view_return = true;
        self.borrow_receiver |= src.receiver;
        for p in src.params {
            if !self.borrow_params.contains(&p) {
                self.borrow_params.push(p);
            }
        }
        self.borrow_path = Some(None);
        // The payload of `ok(x)` / `error(x)` is read into the view, not consumed.
        if self.result_payload(e).is_some() {
            self.view_calls.insert(e.id);
        }
        // A local holding a view is moved out: the box it owns becomes the result. The same
        // when a returner hands the local back whole (`return relay(e)`): the box moves into the
        // call and comes back as the result instead of being copied.
        let moved = via.unwrap_or(e);
        let moved = self.result_payload(moved).unwrap_or(moved);
        if let Some(operand) = self.whole_borrowed_operand(moved) {
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
            self.expr(e, Demand::Move);
            self.view_move = None;
        } else {
            self.expr(e, Demand::Read);
        }
        true
    }

    /// The one operand a plain borrow-returning call `e` hands back whole (`relay(x)` for
    /// `relay(e: Error) Error: return e`), when it is a name of an interface view local at its
    /// last use: moving the local into the call lets the caller keep its box as the result.
    fn whole_borrowed_operand<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        if !matches!(e.kind, ExprKind::Call { .. }) {
            return None;
        }
        let ret_borrow = result_borrow(self.syms, self.cx.m, e, self.cx.summaries);
        if !ret_borrow.returns_borrow || ret_borrow.view {
            return None;
        }
        let operands = self.borrow_operands(e, &ret_borrow)?;
        let [operand] = operands.as_slice() else {
            return None;
        };
        let Some((_, fields)) = &ret_borrow.path else {
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
    /// value: `e` itself (`cause` as `Error`, a widened borrow-returning call, `cause` as `Error?`), or
    /// the payload of `ok(x)` / `error(x)`. `None` when nothing is converted or the source is a
    /// scalar, which the interface copies.
    fn view_source<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let converted = |x: &Expr| {
            // A conversion to an interface with a `var fn` copies: a call through the view
            // could change leaves the view only borrows.
            let target = self.cx.m.ty(x);
            let iface = if target.is(Builtin::Result) {
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
                .interface_source
                .as_ref()
                .is_some_and(|src| self.cx.classes.class(self.syms, src) == Class::Move)
        };
        if converted(e) {
            return Some(e);
        }
        let x = self.result_payload(e)?;
        converted(x).then_some(x)
    }

    /// Whether `e` is an interface view or holds one: a conversion of a borrowed value, a view
    /// returner's call, or a local holding a view.
    fn is_view(&self, e: &Expr) -> bool {
        self.view_source(e).is_some() || self.borrow_source(e).is_some_and(|s| s.view)
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
        // A type's own methods are checked as an implementation of a synthesized interface;
        // the desugaring marks that impl synthetic.
        i.contract.is_some() && !c.func.decl.0.decl.synthetic
    }

    /// Whether the declared result type is an interface.
    fn result_is_result(&self) -> bool {
        let c = self.cx.c;
        let result = match (c.func.method(), c.func.func()) {
            (Some(m), _) => m.func.result.id,
            (None, Some(f)) => f.result.id,
            (None, None) => return false,
        };
        self.cx
            .m
            .type_ref(result)
            .is_some_and(|t| t.is(Builtin::Result))
    }

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
        self.cx.m.info(e).interface_source.is_none() && same(&self.cx.m.ty(e), &declared)
    }

    /// Reports a function that returns a reference on one path and an owned value on another:
    /// the caller could not tell whether to hold or drop the result.
    fn mixed_returns(&mut self) {
        if self.view_return {
            // Every path of a view returner returns an owned value. A plain reference to an
            // interface value is handed on as a view that owns nothing; a wrapper of a part
            // becomes a new value of its own, as beside an owned path; any other plain
            // reference has no owned form.
            for n in std::mem::take(&mut self.wrap_returns) {
                self.facts.view_wraps.remove(&n);
            }
            if self.plain_borrowed && !self.result_is_interface() {
                let borrowed = self.borrowed_return.unwrap_or_default();
                self.error(
                    borrowed,
                    format!(
                        "this function returns an interface view of its arguments on another path but a reference here; return `.{CLONE}()` of the part, or convert it on every path"
                    ),
                );
            }
            return;
        }
        let (Some(owned), Some(borrowed)) = (self.owned_return, self.borrowed_return) else {
            return;
        };
        // A wrapper of a part is a reference only when every path returns a borrow; beside a new value it
        // is built as a new value of its own (its payload copied), as before.
        if !self.plain_borrowed {
            // The borrowed cases of a `Result` stay references when no owned path builds the same
            // case: the caller drops only the cases the function owns.
            if self.borrowed_cases & 4 == 0
                && !self.borrow_not_clonable
                // A resource closed at scope end can return its close error, an owned error.
                && self.facts.implicit_closes.is_empty()
                && self.borrowed_cases != 0
                && self.borrowed_cases & self.owned_cases == 0
                && self.result_is_result()
            {
                self.borrowed_mask = self.borrowed_cases;
                return;
            }
            self.borrowed_return = None;
            for n in std::mem::take(&mut self.wrap_returns) {
                self.facts.view_wraps.remove(&n);
            }
            return;
        }
        self.error(
            owned,
            format!(
                "this function returns a reference into its arguments at {}:{} but a new value here; return `.clone()` of the part there, or build a new value on every path",
                borrowed.line, borrowed.column
            ),
        );
    }

    /// The arguments a borrow-returning call returns a reference into: the receiver and the parameters
    /// `ret_borrow` names, as written. `None` when one of them is converted on the way in (wrapped
    /// into an `Optional`, widened to an interface or another error type): the callee then returns a borrow
    /// a temporary, and the result is a new value of the caller's.
    fn borrow_operands<'e>(&self, e: &'e Expr, ret_borrow: &ResultBorrow) -> Option<Vec<&'e Expr>> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return Some(Vec::new());
        };
        let mut out = Vec::new();
        if ret_borrow.receiver
            && let (ExprKind::Member { left, .. }, Resolution::Method(_)) =
                (&callee.kind, self.cx.m.resolution(e))
        {
            out.push(&**left);
        }
        let slots = self.cx.m.info(e).arguments.clone().unwrap_or_default();
        for (i, a) in args.iter().enumerate() {
            if slots
                .get(i)
                .is_some_and(|s| ret_borrow.params.contains(&s.name))
            {
                // A borrowed value converted to an interface on the way in is a view of it: what
                // the callee returns a borrow of the view is a reference into the value.
                if self.converted_argument(e, &a.value) && !self.converted_borrow(&a.value) {
                    return None;
                }
                out.push(&a.value);
            }
        }
        // A copied argument is never borrowed from, whatever an optimistic summary says.
        out.retain(|a| self.class_of(a) != Class::Copy);
        Some(out)
    }

    /// Whether `arg` is a `Move`-class reference converted to an interface on the way in
    /// (`relay(cause)` for `relay(e: Error)`): the converted temporary is a view of it.
    fn converted_borrow(&self, arg: &Expr) -> bool {
        self.view_source(arg).is_some_and(|x| std::ptr::eq(x, arg))
            && self.borrow_source(arg).is_some()
    }

    /// Whether a borrowed operand of call `e` is a converted view temporary: the caller owns what
    /// the callee returns a borrow of it (the temporary itself when handed back whole, else a copy) and
    /// still holds the value it views.
    fn returns_borrow_through_view(&self, e: &Expr, ret_borrow: &ResultBorrow) -> bool {
        self.borrow_operands(e, ret_borrow).is_some_and(|ops| {
            ops.iter()
                .any(|o| self.converted_borrow(o) || self.is_view(o))
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
        if a.wrap_optional.is_some() || self.cx.m.info(arg).interface_source.is_some() {
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
    fn wrapped_borrow<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let info = self.cx.m.info(e);
        if info.interface_source.is_some() {
            return None;
        }
        if info.wrap_some.is_some() {
            return Some(e);
        }
        let inner = self.result_payload(e)?;
        let inner_info = self.cx.m.info(inner);
        (inner_info.interface_source.is_none()
            && inner_info.wrap_some.is_none()
            && self.class_of(inner) != Class::Copy)
            .then_some(inner)
    }

    /// The case of a `Result` a returned wrapper lends: `ok(x)` or `error(x)`; 4 for any other
    /// wrapper (`x?`), which keeps the copy.
    fn wrap_case(&self, e: &Expr) -> u8 {
        self.result_case(e).unwrap_or(4)
    }

    /// The cases of a `Result` an owned returned expression can build.
    fn owned_case(&self, e: &Expr) -> u8 {
        self.result_case(e).unwrap_or(7)
    }

    /// The case an `ok(..)` or `error(..)` constructor call builds.
    fn result_case(&self, e: &Expr) -> Option<u8> {
        self.result_payload(e)?;
        let Resolution::Constructor { case: Some(c), .. } = self.cx.m.resolution(e) else {
            return None;
        };
        match self.syms.str(c) {
            "ok" => Some(BORROWED_OK),
            "error" => Some(BORROWED_ERROR),
            _ => None,
        }
    }

    /// The error path of `try operand` returns the operand's error: a reference when the operand
    /// returns a borrow of it from the arguments as it is, otherwise a new value, like any `return`.
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
        if self.cx.classes.class(self.syms, &declared) == Class::Copy {
            return;
        }
        if self.class_of(operand) == Class::Move
            && let Some(src) = self.borrow_source(operand)
            && (src.cases == 0 || src.cases & BORROWED_ERROR != 0)
        {
            self.borrowed_return.get_or_insert(e.pos);
            if src.view {
                // The error leaves as an interface view (converted on the way out, or a view
                // already): an owned value whose payload stays in the operand's sources.
                self.view_return = true;
            } else {
                self.facts.view_wraps.insert(e.id);
                self.wrap_returns.push(e.id);
                self.borrowed_cases |= BORROWED_ERROR;
                if let Some(err) = self.cx.m.ty(operand).args.get(1)
                    && !self.cx.classes.clonable(self.syms, err)
                {
                    self.borrow_not_clonable = true;
                }
            }
            self.borrow_receiver |= src.receiver;
            for p in src.params {
                if !self.borrow_params.contains(&p) {
                    self.borrow_params.push(p);
                }
            }
            // The error is one case of the result, never a field chain of a source.
            self.borrow_path = Some(None);
            return;
        }
        self.owned_return.get_or_insert(e.pos);
        self.owned_cases |= BORROWED_ERROR;
    }

    /// The payload expression of an `ok(x)` or `error(x)` constructor call.
    fn result_payload<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return None;
        };
        let Resolution::Constructor { ty, case: Some(_) } = self.cx.m.resolution(e) else {
            return None;
        };
        (ty.is(Builtin::Result) && args.len() == 1 && args[0].name.is_none())
            .then(|| &args[0].value)
    }

    /// The parameters and receiver a returned expression is a part of, when it is one: a place
    /// rooted in a parameter or the receiver, or a borrow-returning call whose sources all are. `None`
    /// for an owned value, including a part of a local, a temporary or a default argument.
    fn borrow_source(&self, e: &Expr) -> Option<BorrowSource> {
        // `ok(x)` and `error(x)` are references when `x` is: the wrapper adds no storage. A
        // payload converted on the way in (`error(cause)` as `Error`) or copied is a new value.
        if self.result_payload(e).is_some() {
            return self.borrow_source(self.wrapped_borrow(e)?);
        }
        // A field or element of what a borrow-returning call returns (`self.head().tags[0]`) is a part of
        // the same sources; a field chain extends the path, an element ends it.
        if let Some((call, fields)) = self.part_of_call(e) {
            let mut src = self.borrow_source(call)?;
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
                let mut out = BorrowSource {
                    receiver: false,
                    params: Vec::new(),
                    path: None,
                    view: self.view_locals.contains(&b.uid),
                    cases: 0,
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
                (Role::SelfValue, _) => Some(BorrowSource {
                    receiver: true,
                    params: Vec::new(),
                    path: path.map(|f| (None, f)),
                    view: false,
                    cases: 0,
                }),
                (Role::Parameter, Some(i)) => {
                    let label = self.parameter_label(i)?;
                    Some(BorrowSource {
                        receiver: false,
                        params: vec![label],
                        path: path.map(|f| (Some(label), f)),
                        view: false,
                        cases: 0,
                    })
                }
                _ => None,
            };
        }
        // `xs.get(i)` is the element itself, a part of the receiver's sources whose field
        // chain ends there. The other native borrows (`m.get(k)`, `xs.first()`) wrap the element
        // in an `Optional` the caller owns, so a function returning one owns its result.
        if let Some(recv) = self.native_borrow_receiver(e)
            && self.list_get(e)
        {
            let mut src = self.borrow_source(recv)?;
            if src.view {
                return None;
            }
            src.path = None;
            return Some(src);
        }
        if let ExprKind::Call { .. } = &e.kind {
            let ret_borrow = result_borrow(self.syms, self.cx.m, e, self.cx.summaries);
            if !ret_borrow.returns_borrow {
                return None;
            }
            let operands = self.borrow_operands(e, &ret_borrow)?;
            if operands.is_empty() {
                return None;
            }
            let mut out = BorrowSource {
                receiver: false,
                params: Vec::new(),
                path: None,
                view: ret_borrow.view && ret_borrow.borrowed_cases == 0,
                cases: ret_borrow.borrowed_cases,
            };
            let mut paths: Vec<Option<(Option<Name>, Vec<Name>)>> = Vec::new();
            for (k, operand) in operands.iter().enumerate() {
                let src = self.borrow_source(operand)?;
                out.view |= src.view || self.view_source(operand).is_some();
                out.receiver |= src.receiver;
                for p in src.params {
                    if !out.params.contains(&p) {
                        out.params.push(p);
                    }
                }
                // The callee's one field chain, continued from this operand's own chain.
                let through = match (&ret_borrow.path, k, &src.path) {
                    (Some((None, fields)), 0, Some((root, mine))) if ret_borrow.receiver => {
                        Some((*root, [mine.clone(), fields.clone()].concat()))
                    }
                    (Some((Some(label), fields)), _, Some((root, mine)))
                        if self.borrow_operand_label(e, operand) == Some(*label) =>
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

    /// The borrow-returning call a projection chain starts from, with the fields from it when the chain
    /// is fields only (`None` for an element).
    fn part_of_call<'e>(&self, e: &'e Expr) -> Option<(&'e Expr, Option<Vec<Name>>)> {
        match &e.kind {
            ExprKind::Member { left, name } => {
                if let ExprKind::Call { .. } = &left.kind {
                    return self
                        .returns_borrow(left)
                        .then_some((&**left, Some(vec![*name])));
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
                    return self.returns_borrow(left).then_some((&**left, None));
                }
                let (call, _) = self.part_of_call(left)?;
                Some((call, None))
            }
            _ => None,
        }
    }

    /// Whether a call hands back a reference into its operands.
    fn returns_borrow(&self, call: &Expr) -> bool {
        self.class_of(call) != Class::Copy
            && (self.native_borrow_receiver(call).is_some()
                || result_borrow(self.syms, self.cx.m, call, self.cx.summaries).returns_borrow)
    }

    /// The label of the parameter `operand` is written for in call `e`.
    fn borrow_operand_label(&self, e: &Expr, operand: &Expr) -> Option<Name> {
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

    /// Whether `e` is a native read that lowering borrows in place (`crates/ms-lower/src/borrow_shape.rs`):
    /// `m.get(key)` on a `Map`, `xs.first()` or `xs.last()` on a `List`, with the receiver written.
    fn native_borrow_receiver<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let ExprKind::Call { callee, args } = &e.kind else {
            return None;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return None;
        };
        let Resolution::Method(method) = self.cx.m.resolution(e) else {
            return None;
        };
        if self.syms.str(method.native).is_empty() {
            return None;
        }
        let recv = self.cx.m.ty(left);
        let returns_borrow = match (self.syms.str(name), args.len()) {
            ("get", 1) => recv.is(Builtin::Map) || recv.is(Builtin::List),
            ("first" | "last", 0) => recv.is(Builtin::List),
            ("view", 2) => recv.is(Builtin::Bytes),
            _ => false,
        };
        returns_borrow.then_some(&**left)
    }

    /// Whether `e` is `xs.get(i)` on a `List`, without a default: the element read in place.
    fn list_get(&self, e: &Expr) -> bool {
        let ExprKind::Call { callee, args } = &e.kind else {
            return false;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return false;
        };
        self.syms.str(name) == "get" && args.len() == 1 && self.cx.m.ty(left).is(Builtin::List)
    }

    /// Whether `e` is `map.get(key)` on a `Map`: an entry read in place.
    fn map_get(&self, e: &Expr) -> bool {
        let ExprKind::Call { callee, args } = &e.kind else {
            return false;
        };
        let ExprKind::Member { left, name } = &callee.kind else {
            return false;
        };
        self.syms.str(name) == "get"
            && args.len() == 1
            && self.cx.m.ty(left).is(Builtin::Map)
            && matches!(self.cx.m.resolution(e), Resolution::Method(m) if !self.syms.str(m.native).is_empty())
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
        let class = self.cx.classes.class(self.syms, &b.ty);
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
            opener_line: 0,
            file: Arc::from(self.syms.str(self.cx.m.data.file)),
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
        self.cx.classes.class(self.syms, &self.cx.m.ty(e))
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
        if last
            && self
                .active
                .iter()
                .any(|a| a.holder == b.uid && a.why != PROMISE_WHY)
        {
            self.pending.push(b.uid);
        }
        if last && access == Access::Move {
            // A promise handed on (`wait_all([p, q])`) ends where its new owner does: a binding or
            // local container that receives it takes the borrow over (`take_carried`).
            let (moved, kept): (Vec<_>, Vec<_>) = std::mem::take(&mut self.active)
                .into_iter()
                .partition(|a| a.holder == b.uid && a.why == PROMISE_WHY);
            self.active = kept;
            self.carried.extend(moved);
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
            let remedy = if self.syms.str(holder) == "for" {
                format!("iterate over a clone instead: `for ... in {shown}.{CLONE}()`")
            } else if why == PROMISE_WHY {
                String::new()
            } else if held_ty.as_ref().and_then(clone_blocker).is_some() {
                format!(
                    "or give `{holder_t}` its own value by converting a clone of the concrete value",
                    holder_t = self.syms.str(holder)
                )
            } else {
                format!(
                    "or give `{holder_t}` its own value by ending its initializer with `.{CLONE}()`",
                    holder_t = self.syms.str(holder)
                )
            };
            if why == PROMISE_WHY {
                self.error(
                    pos,
                    format!(
                        "cannot {what} `{shown}` while promise `{holder_t}` (started at {}:{}) reads it; a promise reads what it captures until it is dropped, so wait for it and move it into `wait_all` first, or {what} a copy",
                        bpos.line, bpos.column
                    , holder_t = self.syms.str(holder)),
                );
                return;
            }
            self.error(
                pos,
                format!(
                    "cannot {what} `{shown}` while `{holder_t}` borrows it ({why}, at {}:{}); finish using `{holder_t}` before this, {remedy}",
                    bpos.line, bpos.column
                , holder_t = self.syms.str(holder)),
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
                    "cannot use `{shown}` while `{holder_t}` (a mutable borrow at {}:{}) holds it; finish using `{holder_t}` first, or use the value through `{holder_t}`",
                    bpos.line,
                    bpos.column,
                    holder_t = self.syms.str(holder)
                )
            } else {
                format!(
                    "cannot use `{shown}` while closure `{holder_t}` (made at {}:{}) changes it; call or drop the closure first, or clone the value before creating it",
                    bpos.line,
                    bpos.column,
                    holder_t = self.syms.str(holder)
                )
            };
            self.error(pos, text);
        }
    }

    fn release_pending(&mut self) {
        let pending = std::mem::take(&mut self.pending);
        self.active
            .retain(|a| a.why == PROMISE_WHY || !pending.contains(&a.holder));
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
            } => self.cx.m.info(e).native_str(self.syms) == "index" && self.is_place(left),
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
        let literal = || {
            ms_syntax::number::canonical(self.syms.str(t))
                .parse::<u64>()
                .ok()
        };
        if self.cx.m.ty(left).is(Builtin::List)
            && !self.syms.str(t).contains(['.', 'e', 'E'])
            && !self.syms.str(t).ends_with('d')
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
                    text: self.syms.str(b.name).to_string(),
                };
                Some((info, p))
            }
            ExprKind::Member { left, name } => {
                let (mut info, p) = self.place(left)?;
                let p = p.then(Step::Field(*name));
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}.{}", info.text, self.syms.str(name));
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
        // Borrows the enclosing statement released at their last use stay held until that
        // statement ends: a closure body in an argument must not release them early.
        let outer = std::mem::take(&mut self.pending);
        for s in body {
            self.stmt(s);
            self.release_pending();
        }
        self.pending.extend(outer);
        let ended: Vec<usize> = self.declared.drain(mark..).collect();
        self.promises_outliving(&ended);
        self.active.retain(|a| !ended.contains(&a.holder));
    }

    /// A promise kept by a binding that outlives the block must not read a local that ends with it.
    fn promises_outliving(&mut self, ended: &[usize]) {
        let mut found: Vec<(Pos, String, String)> = Vec::new();
        for a in &self.active {
            if a.why != PROMISE_WHY || ended.contains(&a.holder) {
                continue;
            }
            for (place, _) in &a.origins {
                if ended.contains(&place.root) {
                    found.push((
                        a.pos,
                        self.syms.str(a.holder_name).to_string(),
                        self.syms.str(self.name_of(place.root)).to_string(),
                    ));
                }
            }
        }
        for (pos, holder, name) in found {
            self.error(
                pos,
                format!(
                    "this promise reads `{name}`, which ends before `{holder}` does; start the promise from a value that outlives `{holder}`, or wait for it before the block ends"
                ),
            );
        }
    }

    /// Hands the borrows of promises moved since the statement began to `holder`, keeping the
    /// places that are still in scope.
    fn take_carried(&mut self, holder: usize, holder_name: Name) {
        for mut a in std::mem::take(&mut self.carried) {
            a.origins.retain(|(p, _)| self.declared.contains(&p.root));
            if a.origins.is_empty() || a.holder == holder {
                continue;
            }
            a.holder = holder;
            a.holder_name = holder_name;
            self.active.push(a);
        }
    }

    fn stmt(&mut self, s: &Stmt) {
        self.carried.clear();
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
                let scrutinee = self.scrutinee(probed.unwrap_or(cond));
                if mutable {
                    self.mutable_payload(p, cond, &scrutinee);
                    self.payload_resource(s, p, &scrutinee);
                } else {
                    self.pattern_bindings(p, &scrutinee, Role::Pattern);
                    self.payload_resource(s, p, &scrutinee);
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
    fn payload_resource(&mut self, s: &Stmt, p: &Pattern, source: &Scrutinee) {
        if !source.owned || !matches!(p.kind, PatternKind::Name(_)) {
            return;
        }
        let Some(b) = self.cx.m.pattern_binding(p) else {
            return;
        };
        if self.may_close(&b.ty) {
            let closable = self.closable(s, &b.ty);
            self.resources.push((b.uid, b.name, p.pos, closable));
        }
    }

    fn for_stmt(&mut self, s: &Stmt, iter: &Expr, body: &[Stmt]) {
        let mark = self.declared.len();
        let source = self.scrutinee(iter);
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
            let class = self.cx.classes.class(self.syms, &b.ty);
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
            let scrutinee = self.scrutinee(value);
            let role = if mutable { Role::Var } else { Role::Pattern };
            self.pattern_bindings(pattern, &scrutinee, role);
            if scrutinee.owned {
                // The pattern owns the parts it names: a resource among them closes at the
                // scope end unless the scope moves it on, like any other owned binding.
                self.pattern_resources(pattern, s);
            }
            return;
        };
        let Some(b) = self.cx.m.pattern_binding(pattern) else {
            self.expr(value, Demand::Move);
            return;
        };
        let role = if mutable { Role::Var } else { Role::Let };
        if !mutable {
            self.let_pos.insert(b.uid, s.pos);
        }
        let class = self.cx.classes.class(self.syms, &b.ty);
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
                            "`var {}` cannot borrow `{text}` mutably: it is a read-only result; clone it with `{text}.{CLONE}()` to own it",
                            self.syms.str(b.name)
                        ),
                    );
                    self.declare(&b, role, Perm::Mutable, None, false);
                }
            } else {
                // A part wrapped on the way in (`let o: String? = r.name`) stays a reference.
                if self.wrapped_borrow(value).is_some() {
                    self.facts.view_wraps.insert(value.id);
                }
                // A part converted to an interface (`let e: Error = r.cause`) or a view
                // returner's result: the binding owns the view's box and borrows the sources.
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
            && let Some(inner) = self.wrapped_borrow(value)
            && let ExprKind::Name(_) = &inner.kind
            && let Resolution::Local(src) = self.cx.m.resolution(inner)
            && let Some(src_meta) = self.meta.get(&src.uid)
            && self.cx.classes.class(self.syms, &src.ty) != Class::Copy
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
            self.method_value_binding(value, recv, &b, role, mutable, true);
            return;
        }
        if let Some(recv) = self.method_value(value) {
            self.method_value_binding(value, recv, &b, role, mutable, false);
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
                    self.expr(value, Demand::Move);
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
        self.expr(value, Demand::Move);
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
        // The binding owns the value (a call result among them: a resource a method on another
        // resource returns, `client.request(..)`, is the caller's to close), so a resource it holds
        // closes at the scope end unless the scope moves it on.
        if self.may_close(&b.ty) {
            let closable = self.closable(s, &b.ty);
            self.resources.push((b.uid, b.name, pattern.pos, closable));
        }
        if ty_holds_promise(self.syms, &b.ty) {
            self.take_carried(b.uid, b.name);
        }
        if self.entry_call(value) || self.holds_lambda_promises(value) {
            // The promise reads what its entry captures until it is dropped with its scope.
            let origins = self.entry_places(value);
            if !origins.is_empty() {
                self.active.push(Borrow {
                    holder: b.uid,
                    holder_name: b.name,
                    origins: origins.into_iter().map(|p| (p, false)).collect(),
                    pos: value.pos,
                    why: PROMISE_WHY.to_string(),
                });
            }
        }
    }

    /// `var x = f(b)` where `f` returns one chain of fields of one argument: an exclusive borrow of
    /// that place, which lowering names instead of calling `f` (`getter_borrows`). Any other
    /// reference result cannot be bound with `var`.
    fn bind_getter(&mut self, s: &Stmt, b: &BindingRef, role: Role, value: &Expr) {
        let pos = s.pos;
        let text = self.expr_text(value);
        let ret_borrow = result_borrow(self.syms, self.cx.m, value, self.cx.summaries);
        let operands = self.borrow_operands(value, &ret_borrow).unwrap_or_default();
        let target = match (&ret_borrow.path, operands.as_slice()) {
            (Some((None, fields)), [recv]) if ret_borrow.receiver => Some((*recv, fields.clone())),
            (Some((Some(label), fields)), [arg])
                if self.borrow_operand_label(value, arg) == Some(*label) =>
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
                    self.syms.str(b.name)
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

    /// A method used as a value (`xs.append`, `re.find`, or specialized, `log.error[Unit]`):
    /// the method and its receiver expression.
    fn method_value_parts<'e>(&self, e: &'e Expr) -> Option<(MethodRef, &'e Expr)> {
        let member = match &e.kind {
            ExprKind::Apply { left, .. } if self.cx.m.info(e).native_str(self.syms) != "index" => {
                left
            }
            _ => e,
        };
        let ExprKind::Member { left, .. } = &member.kind else {
            return None;
        };
        if self.cx.m.ty(e).kind != Kind::Function
            || self.callees.contains(&e.id)
            || self.callees.contains(&member.id)
        {
            return None;
        }
        let resolution = match self.cx.m.resolution(member) {
            Resolution::Value => self.cx.m.resolution(e),
            r => r,
        };
        let Resolution::Method(m) = resolution else {
            return None;
        };
        Some((m, &**left))
    }

    /// The receiver of a method value that changes it (`xs.append`).
    fn changing_method_value<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let (m, left) = self.method_value_parts(e)?;
        (receiver_mode(self.syms, self.cx.summaries, &m) == Some(ParamMode::Mutate)).then_some(left)
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
                format!("this method value changes `{0}`, so it cannot be returned, stored or passed to a moving parameter; keep it local, or call the method instead", self.syms.str(info.root.name)),
            );
            return Vec::new();
        }
        self.mutate(e.pos, &info, "change");
        self.facts.bound_borrows.insert(e.id);
        info.resolved.into_iter().map(|p| (p, true)).collect()
    }

    /// The receiver of a method value that only reads it (`re.find`).
    fn method_value<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        let (m, left) = self.method_value_parts(e)?;
        (receiver_mode(self.syms, self.cx.summaries, &m) != Some(ParamMode::Mutate)).then_some(left)
    }

    /// Walks the receiver of a method value that only reads it. The value is a closure over the
    /// receiver, which has one owner: a value that stays local borrows the receiver's place while
    /// it lives (`bound_borrows`), and one that escapes takes the receiver over, moving it at its
    /// last use. A `Copy` receiver is copied, and a temporary one is owned by the value. Returns
    /// the places a borrowing value holds.
    fn method_value_use(&mut self, e: &Expr, recv: &Expr, escaping: bool) -> Vec<(Place, bool)> {
        if self.class_of(recv) == Class::Copy || !self.is_place(recv) {
            self.expr(recv, Demand::Read);
            return Vec::new();
        }
        if escaping {
            self.expr(recv, Demand::Move);
            return Vec::new();
        }
        self.expr(recv, Demand::Read);
        self.facts.bound_borrows.insert(e.id);
        self.pure_places(recv)
            .unwrap_or_default()
            .into_iter()
            .map(|p| (p, false))
            .collect()
    }

    fn method_value_binding(
        &mut self,
        value: &Expr,
        recv: &Expr,
        b: &BindingRef,
        role: Role,
        mutable: bool,
        changing: bool,
    ) {
        let escaping = self.escaped.contains(&value.id);
        let origins = if changing {
            self.changing_method_use(value, recv, escaping)
        } else {
            self.method_value_use(value, recv, escaping)
        };
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
        let refilled = match target {
            AssignTarget::Name(_) => self.cx.m.assigned(value).filter(|b| {
                self.meta
                    .get(&b.uid)
                    .is_some_and(|m| m.parameter.is_some() && m.perm == Perm::Mutable)
            }),
            AssignTarget::Member(_) => None,
        };
        let saved = self.self_assign;
        self.self_assign = refilled.map(|b| b.uid);
        self.expr(value, Demand::Move);
        self.self_assign = saved;
        match target {
            AssignTarget::Name(name) => {
                let Some(b) = self.cx.m.assigned(value) else {
                    return;
                };
                self.check_store(s.pos, &b, *name);
                let places = vec![Place::local(b.uid)];
                self.check_change(s.pos, &places, "reassign", self.syms.str(b.name), None);
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
            Perm::Mutable | Perm::ClosureOwned => {}
            // A scalar borrow is a name for its place: assigning writes through.
            Perm::MutBorrowed if m.class == Class::Copy => {}
            Perm::Immutable if m.parameter.is_some() => self.error(
                pos,
                format!("cannot assign to parameter `{name_t}`: it is not declared var; write `var {name_t}: <Type>` in the signature and `var` at every call", name_t = self.syms.str(name)),
            ),
            Perm::MutBorrowed => self.error(
                pos,
                format!("cannot reassign `{name_t}`: it is a mutable borrow of another value; assign to its fields, or clone with `{name_t}.{CLONE}()`", name_t = self.syms.str(name)),
            ),
            Perm::Immutable | Perm::Borrowed => self.error(
                pos,
                format!("cannot assign to `{name_t}`: it is not a var; declare it `var {name_t} = ...`", name_t = self.syms.str(name)),
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
        if self.syms.str(root.name).starts_with('?') && perm != Perm::MutBorrowed {
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
                format!("cannot {what} `{text}`: `{field_t}` is a `ref` field, a read-only view of another value", field_t = self.syms.str(field)),
            );
            return;
        }
        match perm {
            Perm::Mutable | Perm::ClosureOwned | Perm::MutBorrowed => {}
            Perm::Borrowed => {
                let from = self
                    .meta
                    .get(&root.uid)
                    .and_then(|m| m.origins.first())
                    .map(|o| self.syms.str(self.name_of(o.root)).to_string())
                    .unwrap_or_else(|| "another value".to_string());
                self.error(
                    pos,
                    format!(
                        "cannot {what} `{text}`: `{}` only borrows from `{from}`; clone it first with `var {} = {}.{CLONE}()`",
                        self.syms.str(root.name), self.syms.str(root.name), self.syms.str(root.name)
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
                    self.syms.str(root.name),
                    self.syms.str(root.name)
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
                    self.syms.str(root.name),
                    self.syms.str(root.name)
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
    fn scrutinee(&mut self, e: &Expr) -> Scrutinee {
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
                    self.expr(e, Demand::Move);
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
        self.expr(e, Demand::Move);
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
                    "`if var` borrows an entry written as `place[key]?` or `map.get(key)`, but `{}` is not one; bind a clone with `if let`, then `var x = x.clone()`, or write the changed value back",
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

    /// Registers the resources an owning pattern binds for the scope-end close.
    fn pattern_resources(&mut self, p: &Pattern, s: &Stmt) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.cx.m.pattern_binding(p)
                    && self.may_close(&b.ty)
                {
                    let closable = self.closable(s, &b.ty);
                    self.resources.push((b.uid, b.name, p.pos, closable));
                }
            }
            PatternKind::List(items) => items.iter().for_each(|i| self.pattern_resources(i, s)),
            PatternKind::Record(fields) => fields
                .iter()
                .for_each(|f| self.pattern_resources(&f.pattern, s)),
        }
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
        let class = self.cx.classes.class(self.syms, &b.ty);
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
    /// arguments a borrow-returning callee returns a part of, or the container of a native read that is
    /// borrowed in place. `None` when the result owns, including when a source is a temporary.
    fn pure_origins(&self, e: &Expr) -> Option<Vec<Place>> {
        if self.class_of(e) == Class::Copy {
            return None;
        }
        if let ExprKind::Match { arms, .. } = &e.kind {
            return self.arm_origins(arms);
        }
        // `try f(a)` yields the payload of what `f` returns_borrow: a reference into the same places.
        if let ExprKind::Unary {
            op: UnaryOp::Try,
            operand,
        } = &e.kind
        {
            // A function that borrows only its error leaves the `ok` payload an owned value.
            if matches!(operand.kind, ExprKind::Call { .. }) {
                let cases =
                    result_borrow(self.syms, self.cx.m, operand, self.cx.summaries).borrowed_cases;
                if cases != 0 && cases & BORROWED_OK == 0 {
                    return None;
                }
            }
            return if self.is_place(operand) {
                self.pure_places(operand)
            } else {
                self.pure_origins(operand)
            };
        }
        let ExprKind::Call { .. } = &e.kind else {
            return None;
        };
        let operands = match self.native_borrow_receiver(e) {
            Some(recv) => vec![recv],
            None => {
                let ret_borrow = result_borrow(self.syms, self.cx.m, e, self.cx.summaries);
                if !ret_borrow.returns_borrow {
                    return None;
                }
                self.borrow_operands(e, &ret_borrow)?
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

    /// Whether `e` starts a promise whose entry function is written here: a call of a source function
    /// or method that returns a `Promise` and is given a lambda. The promise reads the lambda's
    /// captures in place until it is dropped, so they must outlive it and stay unchanged (the
    /// declaration is the result type, not the callee's name).
    fn entry_call(&self, e: &Expr) -> bool {
        let ExprKind::Call { args, .. } = &e.kind else {
            return false;
        };
        if !args
            .iter()
            .any(|a| matches!(a.value.kind, ExprKind::Lambda(_)))
        {
            return false;
        }
        if !self
            .cx
            .m
            .ty(e)
            .is_source_type(self.syms, PROMISE_MODULE, "Promise")
        {
            return false;
        }
        match self.cx.m.resolution(e) {
            Resolution::Function(s) => self.syms.str(s.native).is_empty(),
            Resolution::Method(m) => self.syms.str(m.native).is_empty(),
            _ => false,
        }
    }

    /// The promise-starting calls a lambda argument of `e` returns, when `e` itself yields promises
    /// (`xs.map(fn x: promise(fn: f(x)))`): the result holds them, so it keeps their borrows.
    fn lambda_promises<'e>(&self, e: &'e Expr) -> Vec<&'e Expr> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return Vec::new();
        };
        if !ty_holds_promise(self.syms, &self.cx.m.ty(e)) {
            return Vec::new();
        }
        args.iter()
            .filter_map(|a| match &a.value.kind {
                ExprKind::Lambda(l) => Some(l),
                _ => None,
            })
            .flat_map(|l| l.body.iter())
            .filter_map(|s| match &s.kind {
                StmtKind::Return(Some(r)) if self.entry_call(r) => Some(r),
                _ => None,
            })
            .collect()
    }

    fn holds_lambda_promises(&self, e: &Expr) -> bool {
        !self.lambda_promises(e).is_empty()
    }

    /// The captured bindings of the lambda arguments of promise-starting call `e`, or of the
    /// promises its lambda arguments start.
    fn entry_captures(&self, e: &Expr) -> Vec<BindingRef> {
        let ExprKind::Call { args, .. } = &e.kind else {
            return Vec::new();
        };
        if !self.entry_call(e) {
            // Bindings made inside the outer lambda (its parameters) are not the caller's to hold.
            return self
                .lambda_promises(e)
                .into_iter()
                .flat_map(|p| self.entry_captures(p))
                .filter(|b| {
                    args.iter()
                        .any(|a| self.cx.m.captures(&a.value).iter().any(|o| o.uid == b.uid))
                })
                .collect();
        }
        args.iter()
            .filter(|a| matches!(a.value.kind, ExprKind::Lambda(_)))
            .flat_map(|a| self.cx.m.captures(&a.value))
            .collect()
    }

    /// The places a promise-starting call `e` reads through its entry function.
    fn entry_places(&self, e: &Expr) -> Vec<Place> {
        let mut out = Vec::new();
        for b in self.entry_captures(e) {
            // A resource is moved into the promise, which owns and closes it.
            if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                continue;
            }
            for p in self.with_held(self.resolve(&Place::local(b.uid))) {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        }
        out
    }

    /// The names a returned promise would still read after the function ends: the captures of a
    /// promise started in the `return`, or the borrows of a local promise returned by name.
    fn returned_promise_reads(&self, e: &Expr) -> Vec<Name> {
        // A promise returned inside a larger value (`Server(running: p)`, `[promise(..)]`) still
        // reads what it captured, so look at every part of the returned expression.
        let mut parts = Vec::new();
        collect_parts(
            e,
            &|c| matches!(self.cx.m.resolution(c), Resolution::Constructor { .. }),
            &mut parts,
        );
        let mut out: Vec<Name> = Vec::new();
        for part in parts {
            if self.entry_call(part) {
                out.extend(
                    self.entry_captures(part)
                        .into_iter()
                        .filter(|b| self.cx.classes.class(self.syms, &b.ty) == Class::Move)
                        .map(|b| b.name),
                );
            } else if let Resolution::Local(b) = self.cx.m.resolution(part) {
                out.extend(
                    self.active
                        .iter()
                        .filter(|a| a.holder == b.uid && a.why == PROMISE_WHY)
                        .flat_map(|a| a.origins.iter().map(|(p, _)| p.root))
                        // A `Copy` capture is taken by value, so nothing is read after the call.
                        .filter(|uid| self.meta.get(uid).is_none_or(|m| m.class == Class::Move))
                        .map(|uid| self.name_of(uid)),
                );
            }
        }
        out.dedup();
        out
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
            ExprKind::Name(n) => self.syms.str(n).to_string(),
            ExprKind::Member { left, name } => {
                format!("{}.{}", self.expr_text(left), self.syms.str(name))
            }
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
        if d == Demand::Move
            && let Some(src) = &self.cx.m.info(e).interface_source
            && self.cx.classes.class(self.syms, src) == Class::Resource
            && !declares_close(self.syms, &self.cx.m.ty(e))
        {
            // An interface value is never closed for its owner, so owning a resource through one
            // drops its close, unless the interface hands the duty on with a `close` operation.
            let text = self.expr_text(e);
            let target = self.cx.m.ty(e);
            self.error(
                e.pos,
                format!("`{text}` is the resource `{src_t}`, and the `{target_t}` it would become never closes it; keep it as a `{src_t}` so its owner closes it, or pass it where `{target_t}` is only read", src_t = src.display(self.syms), target_t = target.display(self.syms)),
            );
        }
        if let Some(src) = self.cx.m.info(e).interface_source.clone() {
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
                items.iter().for_each(|i| self.expr(i, Demand::Move))
            }
            ExprKind::Map(entries) => {
                let parts: Vec<&Expr> = entries.iter().flat_map(|en| [&en.key, &en.value]).collect();
                self.parts_overlap(e.pos, "this map", &parts);
                for entry in entries {
                    self.expr(&entry.key, Demand::Move);
                    self.expr(&entry.value, Demand::Move);
                }
            }
            ExprKind::Unary { op, operand } => {
                if *op == UnaryOp::Try {
                    self.try_return(e, operand);
                }
                // `try` hands its payload on with the position's demand; a copied payload only
                // reads the result it comes out of.
                // A function that borrows only its error leaves the payload an owned value the
                // `try` takes out of the temporary result; the borrowed error is relayed.
                let owns_ok = matches!(operand.kind, ExprKind::Call { .. }) && {
                    let cases = result_borrow(self.syms, self.cx.m, operand, self.cx.summaries)
                        .borrowed_cases;
                    cases != 0 && cases & BORROWED_OK == 0
                };
                let inner = if *op == UnaryOp::Try && self.class_of(e) != Class::Copy && !owns_ok {
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
                let escaping = d == Demand::Move || self.escaped.contains(&e.id);
                self.lambda(e, l, escaping);
            }
            ExprKind::Call { callee, args } => self.call(e, callee, args, d),
            ExprKind::Match { scrutinee, arms } => self.match_expr(e, scrutinee, arms, d, false),
        }
        self.temporary(e, d);
    }

    /// An owned value nobody consumed is dropped at the end of the statement.
    fn temporary(&mut self, e: &Expr, d: Demand) {
        if d == Demand::Move || self.is_place(e) || matches!(e.kind, ExprKind::Name(_)) {
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
        if d != Demand::Move || class == Class::Copy {
            self.check_read(e.pos, &resolved, self.syms.str(b.name), b.uid);
            let access = if d == Demand::Move {
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
        // A `var` parameter is the caller's value; it may move only into the right side of an
        // assignment to itself, which refills it (`exchange = wrap(exchange)`).
        let var_param =
            parameter.is_some() && perm == Perm::Mutable && self.self_assign != Some(b.uid);
        if role == Role::LambdaParameter
            && self.cx.classes.class(self.syms, &b.ty) == Class::Resource
        {
            // A function value is called with its arguments borrowed, so taking one would copy it,
            // and the caller still closes the original.
            self.error(
                e.pos,
                format!("cannot move `{name_t}` out: a function value only borrows its arguments, and the resource `{}` stays with its caller, which closes it; use `{name_t}` in place here", b.ty.display(self.syms), name_t = self.syms.str(name)),
            );
            self.record(e.id, b, Access::Move);
            return;
        }
        if role == Role::LambdaParameter {
            // The borrowed argument is copied: in generic code its type must be `Clonable`.
            let t = b.ty.clone();
            self.require_clonable(
                e,
                &t,
                &format!(
                    "this function value keeps `{name_t}`, which it only borrows, so it",
                    name_t = self.syms.str(name)
                ),
            );
        }
        if self.captured.iter().any(|c| c.contains(&b.uid)) && perm != Perm::ClosureOwned {
            if b.ty.kind == Kind::Function {
                self.error(
                    e.pos,
                    format!("this closure would move the function `{name_t}` out of the variable it captured, but a closure can run more than once; functions cannot be cloned, so call `{name_t}` here or take it as a parameter of the closure", name_t = self.syms.str(name)),
                );
            } else if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("this closure would move `{name_t}` out of the variable it captured, but a closure can run more than once, and a resource cannot be cloned; use `{name_t}` in place inside the closure", name_t = self.syms.str(name)),
                );
            } else {
                self.error_fix_opt(
                    e.pos,
                    format!("this closure would move `{name_t}` out of the variable it captured, but a closure can run more than once; return `{name_t}.{CLONE}()` instead", name_t = self.syms.str(name)),
                    copy_after(e),
                );
            }
            self.record(e.id, b, Access::Move);
            return;
        }
        if matches!(
            perm,
            Perm::Borrowed | Perm::MutBorrowed | Perm::ClosureOwned
        ) && self.view_move != Some(e.id)
        {
            // Moving a part out of a parameter's match or loop makes that scrutinee consume it;
            // the next pass of the fixpoint sees the parts as owned.
            if let Some(scrutinee) = self.meta[&b.uid].deferred {
                self.escaped.insert(scrutinee);
            }
            if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("cannot move `{name_t}` out: it is borrowed, not owned ({}), and its owner closes it; a resource cannot be cloned, so use `{name_t}` in place", role_text(role, perm), name_t = self.syms.str(name)),
                );
            } else if let Some(why) = clone_blocker(&b.ty) {
                self.error(
                    e.pos,
                    format!("cannot move `{name_t}` out: it is borrowed, not owned ({}); {why}, so use `{name_t}` in place", role_text(role, perm), name_t = self.syms.str(name)),
                );
            } else {
                self.error_fix(
                    e.pos,
                    format!("cannot move `{name_t}` out: it is borrowed, not owned ({}); use `{name_t}.{CLONE}()` to get a clone", role_text(role, perm), name_t = self.syms.str(name)),
                    insert_at(forward(e.pos, self.syms.str(name).len()), &format!(".{CLONE}()")),
                );
            }
            self.record(e.id, b, Access::Move);
            return;
        } else if (var_param || (receiver && perm == Perm::Mutable))
            && self.cx.classes.class(self.syms, &b.ty) == Class::Resource
        {
            self.error(
                e.pos,
                format!("cannot move `{name_t}` out of the function: the caller keeps ownership of a var parameter and closes it; a resource cannot be cloned, so change it in place", name_t = self.syms.str(name)),
            );
        } else if var_param || (receiver && perm == Perm::Mutable) {
            self.error_fix_opt(
                e.pos,
                format!("cannot move `{name_t}` out of the function: the caller keeps ownership of a var parameter; return `{name_t}.{CLONE}()` or change the value in place", name_t = self.syms.str(name)),
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
                    format!("`{name_t}` is moved here but used again{later}; a function value has one owner and cannot be cloned, so move it only at its last use or declare a named `fn`, which can be passed as often as needed", name_t = self.syms.str(name)),
                );
            } else if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read", name_t = self.syms.str(name)),
                );
            } else if let Some(why) = clone_blocker(&b.ty) {
                self.error(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; {why}, so move it only at its last use", name_t = self.syms.str(name)),
                );
            } else {
                self.error_fix(
                    e.pos,
                    format!("`{name_t}` is moved here but used again{later}; a value has one owner, so pass `{name_t}.{CLONE}()` to keep the original, or move it only at its last use", name_t = self.syms.str(name)),
                    insert_at(forward(e.pos, self.syms.str(name).len()), &format!(".{CLONE}()")),
                );
            }
        }
        self.check_change(e.pos, resolved, "move", self.syms.str(name), Some(b.uid));
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
        let escaping = d == Demand::Move || self.escaped.contains(&e.id);
        if let Some(recv) = self.changing_method_value(e) {
            self.changing_method_use(e, recv, escaping);
            return;
        }
        if let Some(recv) = self.method_value(e) {
            self.method_value_use(e, recv, escaping);
            return;
        }
        if !self.is_place(e) {
            // A part of a computed value. Copying a `Copy` part leaves the whole where it is.
            let take = d == Demand::Move
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
                    self.expr(left, if take { Demand::Move } else { Demand::Read })
                }
                ExprKind::Index { left, index } => {
                    self.parts_overlap(e.pos, "this index", &[left, index]);
                    self.expr(left, if take { Demand::Move } else { Demand::Read });
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
        if d == Demand::Move && class != Class::Copy && self.partial_move(e, &info, class) {
            return;
        }
        if d == Demand::Move && class == Class::Resource {
            self.error(
                e.pos,
                format!(
                    "cannot move the resource `{0}` out of `{1}`: a resource cannot be cloned, and it leaves `{1}` only when `{1}` is a `let` or a parameter and no type on the path has a `close` of its own; use `{0}` in place, or move the whole `{1}`",
                    info.text, self.syms.str(info.root.name)
                ),
            );
        } else if d == Demand::Move && class != Class::Copy {
            let message = if self.syms.str(info.root.name).starts_with('?') {
                // The payload of an optional chain `a?.b`, which has no written name.
                format!(
                    "an optional chain `?.` cannot move a field out of the optional; take a clone by ending the access with `.{CLONE}()`"
                )
            } else {
                format!(
                    "cannot move `{0}` out of `{1}`: only a whole variable can move; take a clone with `{0}.{CLONE}()`",
                    info.text,
                    self.syms.str(info.root.name)
                )
            };
            // A member's position is its name, so the copy goes right after it.
            match &e.kind {
                ExprKind::Member { name, .. } => self.error_fix(
                    e.pos,
                    message,
                    insert_at(
                        forward(e.pos, self.syms.str(name).len()),
                        &format!(".{CLONE}()"),
                    ),
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
                format!("`{0}` is moved here but used again{later}; a value has one owner, so use `{0}.{CLONE}()` to keep the original, or move it only at its last use", info.text),
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
                        info.text, self.syms.str(root.name)
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
                format!("{what} clones values of `{v_t}`, which may be a resource; declare `{v_t}: Clonable`", v_t = v.display(self.syms)),
            );
            return;
        }
        if !self.cx.classes.clonable(self.syms, t) {
            // A concrete type with one owner: an interface value, or a native without a `clone`.
            self.error(
                e.pos,
                format!(
                    "{what} clones `{t_t}`, which has one owner and cannot be cloned; use it in place"
                , t_t = t.display(self.syms)),
            );
        }
    }

    /// A conversion of `src` to the interface `e` has: an implementation that keeps a parameter
    /// the operation only borrows is called through the interface with a copy of its argument. A
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
            let borrowed: Vec<Name> = ops
                .iter()
                .filter(|o| o.name == op)
                .filter_map(|o| o.decl.as_ref().and_then(|d| d.func()))
                .flat_map(|f| f.params.iter().filter(|p| !p.mutable).map(|p| p.name))
                .collect();
            for (name, mode) in &summary.params {
                if *mode != ParamMode::Move || !borrowed.contains(name) {
                    continue;
                }
                let Some(p) = m.ty.params.iter().find(|p| p.name == *name) else {
                    continue;
                };
                let t = sub(&p.ty, &bound);
                if self.cx.classes.class(self.syms, &t) == Class::Resource {
                    let text = self.expr_text(e);
                    self.error(
                        e.pos,
                        format!("`{text}` becomes a `{target_t}` whose `{op_t}` keeps its `{name_t}`, which the interface only borrows, so every call through it hands over a clone; the resource `{t_t}` cannot be cloned: pass something that is not a resource, or call `{src_t}`'s `{op_t}` directly", target_t = target.display(self.syms), op_t = self.syms.str(op), t_t = t.display(self.syms), name_t = self.syms.str(name), src_t = src.display(self.syms)),
                    );
                } else {
                    let what = format!(
                        "`{text}` becomes a `{target_t}` whose `{op_t}` keeps its `{name_t}`, which the interface only borrows, so it",
                        text = self.expr_text(e),
                        target_t = target.display(self.syms),
                        op_t = self.syms.str(op),
                        name_t = self.syms.str(name)
                    );
                    self.require_clonable(e, &t, &what);
                }
            }
        }
    }

    /// A named function used as a value is called with its arguments borrowed, so a parameter it
    /// keeps is a copy: rejected for a resource, a copy of the type parameter in generic code.
    fn function_value_copies(&mut self, e: &Expr, module: Name, func: &crate::syntax::FuncRef) {
        let Some(summary) = self.cx.summaries.get(&(module, func.id())) else {
            return;
        };
        let fty = self.cx.m.ty(e);
        for (i, (name, mode)) in summary.params.iter().enumerate() {
            if *mode != ParamMode::Move {
                continue;
            }
            let Some(p) = fty.params.get(i) else { continue };
            if self.cx.classes.class(self.syms, &p.ty) == Class::Resource {
                let text = self.expr_text(e);
                self.error(
                    e.pos,
                    format!("`{text}` keeps its parameter `{name_t}`, but a function value only borrows its arguments, so every call would hand it a clone; the resource `{}` cannot be cloned: call `{text}` directly, or wrap it in a closure that uses `{name_t}` in place", p.ty.display(self.syms), name_t = self.syms.str(name)),
                );
            } else {
                let t = p.ty.clone();
                let what = format!(
                    "`{}` keeps its parameter `{name_t}`, but a function value only borrows its arguments, so it",
                    self.expr_text(e),
                    name_t = self.syms.str(name)
                );
                self.require_clonable(e, &t, &what);
            }
        }
    }

    fn call(&mut self, e: &Expr, callee: &Expr, args: &[Argument], d: Demand) {
        let cx = self.cx;
        let mut modes = call_modes(self.syms, cx.m, e, args, cx.summaries);
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
            && self.syms.str(name) == "close"
            && let Resolution::Local(b) = cx.m.resolution(r)
        {
            self.closed.insert(b.uid);
        }
        // Argument markers: `var` exactly where the callee changes the argument.
        let param_names: Vec<Name> =
            cx.m.info(e)
                .arguments
                .clone()
                .unwrap_or_default()
                .iter()
                .map(|s| s.name)
                .collect();
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            let param = param_names.get(i).copied().unwrap_or_else(|| n("?"));
            // A function type names its parameters by position (`_0`): say which argument.
            let positional =
                self.syms.str(param).strip_prefix('_').is_some_and(|rest| {
                    !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit())
                });
            let which = if positional {
                format!("argument {} of `{name}`", i + 1)
            } else {
                format!(
                    "parameter `{param_t}` of `{name}`",
                    param_t = self.syms.str(param)
                )
            };
            match (mode, a.mutable) {
                (ParamMode::Mutate, false) if positional => self.error_fix(
                    a.value.pos,
                    format!("{which} is var in its type `{}`, so the call must say so; write `var {}`", self.cx.m.ty(callee).display(self.syms), self.expr_text(&a.value)),
                    insert_at(a.value.pos, "var "),
                ),
                (ParamMode::Mutate, false) => self.error_fix(
                    a.value.pos,
                    format!("{which} is declared var, so the call must say so; write `var {}`", self.expr_text(&a.value)),
                    insert_at(a.value.pos, "var "),
                ),
                (ParamMode::Borrow | ParamMode::Move, true) if positional => self.error_fix(
                    a.value.pos,
                    format!("`{name}` does not change {}: its type is `{}`; remove `var` from the argument", which.trim_end_matches(&format!(" of `{name}`")), self.cx.m.ty(callee).display(self.syms)),
                    DiagnosticFix {
                        pos: back(a.value.pos, 4),
                        end: a.value.pos,
                        replacement: String::new(),
                    },
                ),
                (ParamMode::Borrow | ParamMode::Move, true) => self.error_fix(
                    a.value.pos,
                    format!("`{name}` does not change its parameter `{param_t}`; remove `var` from the argument", param_t = self.syms.str(param)),
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
            if self.cx.m.info(e).native_str(self.syms) == "clone"
                && self.class_of(r) == Class::Resource
            {
                let text = self.expr_text(r);
                self.error(
                    e.pos,
                    format!("`{text}` holds a resource, which has one owner and cannot be cloned: a clone would be closed a second time; move it instead"),
                );
            } else if self.cx.m.info(e).native_str(self.syms) == "clone"
                && holds_function(&self.cx.m.ty(r))
            {
                let text = self.expr_text(r);
                self.error(
                    e.pos,
                    format!("`{text}` holds a function value, which owns its captures and has one owner, so it cannot be cloned; move it, or build the value again"),
                );
            }
            let mut mode = modes.receiver.unwrap_or(ParamMode::Borrow);
            // A value with one owner taken out of a receiver that holds it (`o.get(default)` of
            // a resource, or of a native without a `clone`) is the receiver's one owner handing
            // it over, not a copy. A read in place (`xs.first()`) stays a borrow, and a type
            // parameter copies as its bound allows.
            let result_ty = self.cx.m.ty(e);
            if mode == ParamMode::Borrow
                && self.class_of(e) != Class::Copy
                && !self.cx.classes.clonable(self.syms, &result_ty)
                && unbounded_parameter(&result_ty).is_none()
                && ty_contains(&self.cx.m.ty(r), &result_ty)
                && self.native_borrow_receiver(e).is_none()
            {
                mode = ParamMode::Move;
                if !args.is_empty()
                    && let Some(source) = self.native_borrow_receiver(r)
                {
                    // The receiver is itself a native lend (`m.get(k)`, `xs.first()`): the
                    // element stays in its collection, so `get(default)` taking it out would
                    // copy it (`get()` without a default lends the payload in place).
                    let (from, text) = (self.expr_text(source), self.expr_text(r));
                    let why =
                        clone_blocker(&result_ty).unwrap_or("it has one owner and no `clone`");
                    self.error(
                        e.pos,
                        format!("`{name}` would take `{result_ty_t}` out of `{text}`, which only borrows an element of `{from}`; {why}, so read it in place (`if let`)", result_ty_t = result_ty.display(self.syms)),
                    );
                }
            }
            let held = self.held(r, mode);
            self.receiver(r, mode);
            operands.push((Operand::Receiver(r), held, Vec::new()));
        } else {
            self.callees.insert(callee.id);
            self.expr(callee, Demand::Read);
            if let Resolution::Local(_) = cx.m.resolution(callee) {
                // The call reads the function value where the local holds it, so an argument
                // that changes or moves that local would leave the call a dangling callee.
                let held = self.held(callee, ParamMode::Borrow);
                operands.push((Operand::Callee(callee), held, Vec::new()));
            }
        }
        let starts_promise = self.entry_call(e);
        for (i, a) in args.iter().enumerate() {
            let mode = modes.arguments.get(i).copied().unwrap_or(ParamMode::Borrow);
            let mut held = self.held(&a.value, mode);
            if starts_promise && let ExprKind::Lambda(l) = &a.value.kind {
                // The entry of a promise reads what it captures, in place, while the promise lives.
                self.entry_lambda = Some(a.value.id);
                held.extend(self.lambda(&a.value, l, false));
            } else {
                held.extend(self.argument(a, mode, &modes, i));
            }
            operands.push((Operand::Argument(&a.value), held, Vec::new()));
        }
        // A promise handed to a local container (`tasks.append(promise(fn: ...))`) is kept by that
        // local: it reads its captures until the container's scope ends.
        if let Some(r) = receiver_expr
            && let ExprKind::Name(_) = &r.kind
            && let Resolution::Local(holder) = self.cx.m.resolution(r)
        {
            self.take_carried(holder.uid, holder.name);
            for a in args {
                if !self.entry_call(&a.value) {
                    continue;
                }
                let origins = self.entry_places(&a.value);
                if !origins.is_empty() {
                    self.active.push(Borrow {
                        holder: holder.uid,
                        holder_name: holder.name,
                        origins: origins.into_iter().map(|p| (p, false)).collect(),
                        pos: a.value.pos,
                        why: PROMISE_WHY.to_string(),
                    });
                }
            }
        }
        // An operand that already failed its own check is not reported twice. Only a held
        // place can clash, so the operands' inner changes are collected only when one is held.
        if self.diags.len() == reported && operands.iter().any(|(_, held, _)| !held.is_empty()) {
            for (operand, _, passing) in &mut operands {
                let x = match operand {
                    Operand::Receiver(x)
                    | Operand::Callee(x)
                    | Operand::Argument(x)
                    | Operand::Part(x) => *x,
                };
                *passing = self.nested_writes(x);
                for p in self.arm_writes(x) {
                    if !passing.contains(&p) {
                        passing.push(p);
                    }
                }
            }
            self.check_overlap(e.pos, &format!("`{name}`"), &operands);
        }
        // Results. A borrow-returning callee returns a reference into its arguments: holding it is a
        // borrow of them, storing or returning it needs a copy, and when a source is a
        // temporary the caller owns the result (lowering copies it out before the temporary
        // is dropped).
        let ret_borrow = result_borrow(self.syms, cx.m, e, cx.summaries);
        if ret_borrow.returns_borrow && self.class_of(e) != Class::Copy {
            match self.pure_origins(e) {
                Some(origins) if d == Demand::Move => {
                    let mut roots: Vec<String> = origins
                        .iter()
                        .map(|p| self.syms.str(self.name_of(p.root)).to_string())
                        .collect();
                    roots.sort();
                    roots.dedup();
                    let ty = self.cx.m.ty(e);
                    if let Some(why) = clone_blocker(&ty) {
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
                                "`{name}` returns a reference into `{}`, which this position would keep; store `.{CLONE}()` of it, or use it in place",
                                roots.join("`, `")
                            ),
                            copy_after(e),
                        );
                    }
                }
                Some(_) if self.returns_borrow_through_view(e, &ret_borrow) => {
                    // The callee returns a borrow of a view temporary of a held value: the caller owns
                    // the result (the view itself when it comes back whole) and holds the value.
                    let how = self.owned_borrow(e, &ret_borrow, true);
                    self.cloned_borrow(e, &name, how);
                    self.facts.owned_borrows.insert(e.id, how);
                }
                Some(_) => {}
                None => {
                    let how = self.owned_borrow(e, &ret_borrow, false);
                    self.cloned_borrow(e, &name, how);
                    self.facts.owned_borrows.insert(e.id, how);
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

    /// A borrow-returning call over a temporary whose result is a part of it: the caller copies the part
    /// out before the temporary is dropped, which a value with one owner and no `clone` cannot be.
    fn cloned_borrow(&mut self, e: &Expr, name: &str, how: OwnedBorrow) {
        if how != OwnedBorrow::Clone {
            return;
        }
        let t = self.cx.m.ty(e);
        if self.cx.classes.clonable(self.syms, &t) {
            return;
        }
        self.error(
            e.pos,
            format!("`{name}` returns a part of a temporary argument, which would be cloned out as the argument is dropped; `{t_t}` has one owner and no `clone`, so bind the argument first and use the result while that binding lives", t_t = t.display(self.syms)),
        );
    }

    /// How the caller owns the result of a borrow-returning call over a temporary: the whole of one
    /// temporary operand comes back (`id(make())`, `choose(first, second)` over function values
    /// made from named functions, or `relay(cause)` through a view temporary when
    /// `through_view`), so the caller keeps that temporary as the result instead of copying it;
    /// otherwise a copy is taken before the temporary is dropped.
    fn owned_borrow(&self, e: &Expr, lend: &ResultBorrow, through_view: bool) -> OwnedBorrow {
        let whole = match (&lend.path, self.borrow_operands(e, lend)) {
            (Some((source, fields)), Some(operands))
                if fields.is_empty()
                    && operands.len() == 1
                    && (through_view || !self.is_place(operands[0])) =>
            {
                Some(*source)
            }
            _ => None,
        };
        match whole {
            Some(source) => OwnedBorrow::Whole(source),
            None => OwnedBorrow::Clone,
        }
    }

    fn call_name(&self, callee: &Expr) -> String {
        match &callee.kind {
            ExprKind::Name(n) => self.syms.str(n).to_string(),
            ExprKind::Member { name, .. } => self.syms.str(name).to_string(),
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

    /// The places the statements of the `match` arms inside `e` assign, change or move. They run
    /// while a call's receiver, callee and borrowed arguments are held in place, so a call
    /// counts them with [`Self::nested_writes`]; a literal's parts are finished before the next
    /// part runs, so a literal does not.
    fn arm_writes(&mut self, e: &Expr) -> Vec<Place> {
        let mut out: Vec<Place> = Vec::new();
        let mut stack = vec![e];
        while let Some(e) = stack.pop() {
            match &e.kind {
                ExprKind::Number(_)
                | ExprKind::Bool(_)
                | ExprKind::Unit
                | ExprKind::Name(_)
                | ExprKind::Lambda(_) => {}
                ExprKind::Text(parts) => {
                    for p in parts {
                        if let TextPart::Interp(x) = p {
                            stack.push(x);
                        }
                    }
                }
                ExprKind::Member { left, .. } | ExprKind::Probe(left) => stack.push(left),
                ExprKind::Unary { operand, .. } => stack.push(operand),
                ExprKind::Apply { left, value, .. } => {
                    stack.push(left);
                    stack.extend(value.as_deref());
                }
                ExprKind::Index { left, index }
                | ExprKind::Binary {
                    left, right: index, ..
                } => stack.extend([&**left, &**index]),
                ExprKind::List(items) => stack.extend(items.iter()),
                ExprKind::Map(entries) => {
                    stack.extend(entries.iter().flat_map(|en| [&en.key, &en.value]))
                }
                ExprKind::Call { callee, args } => {
                    stack.push(callee);
                    stack.extend(args.iter().map(|a| &a.value));
                }
                ExprKind::Match { scrutinee, arms } => {
                    stack.push(scrutinee);
                    for arm in arms {
                        stack.extend(arm.value.as_ref());
                        for p in self.block_writes(&arm.body) {
                            if !out.contains(&p) {
                                out.push(p);
                            }
                        }
                    }
                }
            }
        }
        out
    }

    /// The places the statements of a block assign, change or move.
    fn block_writes(&mut self, body: &[Stmt]) -> Vec<Place> {
        let mut out: Vec<Place> = Vec::new();
        let add = |out: &mut Vec<Place>, places: Vec<Place>| {
            for p in places {
                if !out.contains(&p) {
                    out.push(p);
                }
            }
        };
        for s in body {
            match &s.kind {
                StmtKind::Assign { target, value, .. } => {
                    let written = match target {
                        AssignTarget::Name(_) => self
                            .cx
                            .m
                            .assigned(value)
                            .map(|b| vec![Place::local(b.uid)])
                            .unwrap_or_default(),
                        AssignTarget::Member(t) => self.pure_places(t).unwrap_or_default(),
                    };
                    add(&mut out, written);
                    add(&mut out, self.nested_writes(value));
                }
                StmtKind::Bind { value, .. } | StmtKind::Call(value) => {
                    add(&mut out, self.nested_writes(value));
                }
                StmtKind::Return(value) => {
                    if let Some(v) = value {
                        add(&mut out, self.nested_writes(v));
                    }
                }
                StmtKind::If {
                    cond,
                    body,
                    else_body,
                    ..
                } => {
                    add(&mut out, self.nested_writes(cond));
                    add(&mut out, self.block_writes(body));
                    add(&mut out, self.block_writes(else_body));
                }
                StmtKind::While { cond, body } => {
                    add(&mut out, self.nested_writes(cond));
                    add(&mut out, self.block_writes(body));
                }
                StmtKind::For { iter, body, .. } => {
                    add(&mut out, self.nested_writes(iter));
                    add(&mut out, self.block_writes(body));
                }
                StmtKind::Break | StmtKind::Continue => {}
            }
        }
        out
    }

    /// The places one call changes or moves through its `var` and consumed operands.
    fn own_writes(&self, call: &Expr) -> Vec<Place> {
        let ExprKind::Call { callee, args } = &call.kind else {
            return Vec::new();
        };
        let modes = call_modes(self.syms, self.cx.m, call, args, self.cx.summaries);
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
                || (mode == ParamMode::Move && self.class_of(operand) == Class::Copy)
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
    /// and one that borrows or reads a place is held while the next runs; a change or move of
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
            ParamMode::Move => self.expr(r, Demand::Move),
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
            ParamMode::Move => self.expr(&a.value, Demand::Move),
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
            Operand::Callee(e) => format!("the called value `{}`", self.expr_text(e)),
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
                        format!("{label} of {context} is changed in place but overlaps {other}; a changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first"),
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
        let source = self.scrutinee(scrutinee);
        self.keep_scrutinee = false;
        self.release_pending();
        // The value is a reference when every arm yields one and nothing moving_params it: lowering
        // joins the arms without copying.
        let borrowed = !returning
            && d != Demand::Move
            && self.class_of(e) != Class::Copy
            && self.arm_origins(arms).is_some();
        let borrowed_before = self.borrowed_return;
        let view_before = self.view_return;
        let entry = self.active.clone();
        let mut joined: Vec<Borrow> = Vec::new();
        for arm in arms {
            self.active = entry.clone();
            let mark = self.declared.len();
            for b in self.cx.m.arm(arm).bindings.iter().flatten() {
                if source.owned {
                    self.arm_payloads.push(b.uid);
                    // The arm owns the part it names: the scope closes a resource among them
                    // on the paths that do not move it on, like any other owned binding.
                    if self.may_close(&b.ty) {
                        self.resources.push((b.uid, b.name, arm.pos, true));
                    }
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
        // A returned match returns a borrow when its arms all did; a mix is reported by `mixed_returns`.
        let returned_borrowed = returning
            && self.owned_return.is_none()
            && self.borrowed_return != borrowed_before
            && self.view_return == view_before;
        if borrowed || returned_borrowed {
            self.facts.borrowed_matches.insert(e.id);
        }
    }

    // --------------------------------------------------------- lambda

    /// Walks a lambda: returns the places it holds while it lives (empty when
    /// it escapes, because it then owns its captures).
    fn lambda(&mut self, e: &Expr, l: &Lambda, escaping: bool) -> Vec<(Place, bool)> {
        let m = self.cx.m;
        let captures = m.captures(e);
        let concurrent = self.entry_lambda.take() == Some(e.id);
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
        // The entry of a promise takes over the resources it captures: they are the promise's own,
        // closed when it ends. It runs once, so inside it they behave like locals it owns: it may
        // move one on (`produce(w)` for a writer `w`) and change one declared `var`.
        if escaping && !concurrent {
            for (uid, _) in &saved_meta {
                if let Some(m) = self.meta.get_mut(uid) {
                    m.perm = Perm::ClosureOwned;
                }
            }
        } else if concurrent {
            for (uid, _) in &saved_meta {
                if let Some(m) = self.meta.get_mut(uid) {
                    if m.class == Class::Resource {
                        m.perm = if m.perm == Perm::Mutable {
                            Perm::Mutable
                        } else {
                            Perm::Immutable
                        };
                    } else if escaping {
                        m.perm = Perm::ClosureOwned;
                    }
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
        for &(uid, perm) in &saved_meta {
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
                        format!("this closure changes captured `{0}`, so it cannot be returned, stored or passed to a moving parameter; keep the closure local, or have it return a new value instead of changing `{0}`", self.syms.str(b.name)),
                    );
                }
                // Only a plain value is copied in. Anything else moves at its last use; when the
                // closure cannot take it over (it is borrowed or used again), `capture_move` asks
                // for an explicit `.clone()` rather than copying it silently.
                if class == Class::Copy {
                    // A `var` used again would diverge from the closure's copy: the closure
                    // cannot borrow it (it outlives the statement), so refuse the silent snapshot.
                    let stored = self.cx.live.assigned_after.get(&(e.id, b.uid)).copied();
                    if saved_perm(&saved_meta, b.uid) == Some(Perm::Mutable)
                        && (!self.is_last(e.id, b) || stored.is_some())
                    {
                        let name = b.name;
                        let later = self
                            .next_use(e.id, b)
                            .or(stored)
                            .map(|n| format!(" at {}", self.at(n)))
                            .unwrap_or_default();
                        self.error(
                            e.pos,
                            format!("this closure outlives the statement but captures the `var` `{name_t}`, which is used again{later}; the closure would keep a stale value, so bind a `let` clone before the closure and capture that", name_t = self.syms.str(name)),
                        );
                    }
                    self.record(e.id, b, Access::Copy);
                    facts.push((b.uid, CaptureMode::Copy));
                } else {
                    let resolved = self.resolve(&Place::local(b.uid));
                    self.capture_move(e, b, &resolved);
                    facts.push((b.uid, CaptureMode::Move));
                }
            } else if concurrent && class == Class::Resource {
                let resolved = self.resolve(&Place::local(b.uid));
                self.capture_move(e, b, &resolved);
                facts.push((b.uid, CaptureMode::Move));
            } else {
                let place = Place::local(b.uid);
                let resolved = self.resolve(&place);
                if changed && concurrent {
                    self.error(
                        e.pos,
                        format!(
                            "concurrent code never changes a shared value, and this promise changes `{0}`; return a new value from the promise instead, or give `{0}` one owner and send it values over a `pipe`",
                            self.syms.str(b.name)
                        ),
                    );
                    self.check_read(e.pos, &resolved, self.syms.str(b.name), b.uid);
                    facts.push((b.uid, CaptureMode::Borrow));
                } else if changed {
                    let info = PlaceInfo {
                        root: b.clone(),
                        root_node: e.id,
                        resolved: resolved.clone(),
                        projection: false,
                        through_ref: None,
                        text: self.syms.str(b.name).to_string(),
                    };
                    self.mutate(e.pos, &info, "change");
                    facts.push((b.uid, CaptureMode::BorrowMut));
                } else if class == Class::Copy {
                    // A `Copy` value the closure only reads is borrowed like any other: the
                    // variable stays unchanged while the closure lives, so lowering may copy it.
                    self.check_read(e.pos, &resolved, self.syms.str(b.name), b.uid);
                    self.record(e.id, b, Access::Copy);
                    facts.push((b.uid, CaptureMode::Copy));
                } else {
                    self.check_read(e.pos, &resolved, self.syms.str(b.name), b.uid);
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
        if matches!(
            perm,
            Perm::Borrowed | Perm::MutBorrowed | Perm::ClosureOwned
        ) {
            if let Some(why) = clone_blocker(&b.ty) {
                self.error(
                    e.pos,
                    format!("this closure outlives the statement but captures `{name_t}`, which is borrowed, not owned; {why}, so capture an owned value instead", name_t = self.syms.str(name)),
                );
            } else {
                self.error_fix_opt(
                    e.pos,
                    format!("this closure outlives the statement but captures `{name_t}`, which is borrowed, not owned; capture `{name_t}.{CLONE}()` instead", name_t = self.syms.str(name)),
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
                    format!("this closure outlives the statement, so it takes `{name_t}` with it, but `{name_t}` is used again{later}; a function value cannot be cloned, so declare a named `fn` instead", name_t = self.syms.str(name)),
                );
            } else if self.cx.classes.class(self.syms, &b.ty) == Class::Resource {
                self.error(
                    e.pos,
                    format!("this closure outlives the statement, so it takes `{name_t}` with it, but `{name_t}` is used again{later}; a resource cannot be cloned, so use `{name_t}` only inside the closure, or capture it at its last use", name_t = self.syms.str(name)),
                );
            } else {
                self.error_fix_opt(
                    e.pos,
                    format!("this closure outlives the statement, so it takes `{name_t}` with it, but `{name_t}` is used again{later}; capture `{name_t}.{CLONE}()` to keep the original", name_t = self.syms.str(name)),
                    copy_after(e),
                );
            }
        }
        self.check_change(e.pos, resolved, "move", self.syms.str(name), Some(b.uid));
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

fn saved_perm(saved: &[(usize, Perm)], uid: usize) -> Option<Perm> {
    saved.iter().find(|(u, _)| *u == uid).map(|(_, p)| *p)
}

/// The expression and the value parts it builds (constructor arguments, list and map elements),
/// not the arguments of other calls (`wait_all([a, b])` moving_params its promises), the bodies of
/// lambdas or the arms of a match.
fn collect_parts<'e>(e: &'e Expr, builds: &dyn Fn(&Expr) -> bool, out: &mut Vec<&'e Expr>) {
    out.push(e);
    match &e.kind {
        ExprKind::Call { args, .. } if builds(e) => {
            args.iter()
                .for_each(|a| collect_parts(&a.value, builds, out));
        }
        ExprKind::List(items) => items.iter().for_each(|x| collect_parts(x, builds, out)),
        ExprKind::Map(entries) => entries.iter().for_each(|en| {
            collect_parts(&en.key, builds, out);
            collect_parts(&en.value, builds, out);
        }),
        _ => {}
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
    if perm == Perm::ClosureOwned {
        return "a variable captured by the closure";
    }
    match role {
        Role::Arm => "a match payload",
        Role::Loop => "a loop variable",
        Role::Pattern => "a pattern variable",
        _ => "a borrow",
    }
}

/// Whether `t` is, or holds as a type argument, a `Promise`.
fn ty_holds_promise(syms: ms_syntax::Names, t: &Ty) -> bool {
    t.is_source_type(syms, PROMISE_MODULE, "Promise")
        || t.args.iter().any(|a| ty_holds_promise(syms, a))
}

/// Whether `part` is exactly one of the type arguments of `src`, at any depth.
fn ty_contains(src: &Ty, part: &Ty) -> bool {
    src.args
        .iter()
        .any(|a| crate::types::same(a, part) || ty_contains(a, part))
}

/// Whether `t` mentions a type parameter.
fn holds_variable(t: &Ty) -> bool {
    type_any::<false>(t, |t| t.kind == Kind::Variable)
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

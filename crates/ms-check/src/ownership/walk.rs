//! The forward walk: classifies every use, tracks lexical borrows, and
//! reports the rules a program breaks.

use super::classify::{Class, Classifier, declares_close};
use super::live::Liveness;
use super::modes::{
    BORROWED_ERROR, BORROWED_OK, CallModes, ParamMode, ResultBorrow, Summaries, Summary,
    call_modes, element_handed_out, method_callee, receiver_mode, result_borrow,
    takes_element_mutator, wrapper_passthrough,
};
use super::places::{Place, Step};
use super::*;
use ms_syntax::ast::*;
use ms_syntax::{DiagnosticFix, Phase, Pos, visit};
use std::sync::Arc;

mod active;
mod calls;
mod exprs;
mod patterns;
mod returns;
mod state;
mod stmts;

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

/// Every method of the program that implements a contract, found by contract and receiver so a
/// conversion does not scan all implementations of a widely implemented interface.
pub struct ContractMethods<'a> {
    by_receiver: HashMap<(Name, Name), Vec<&'a MethodRef>>,
    /// Receivers that are type variables match any source type.
    by_variable: HashMap<Name, Vec<&'a MethodRef>>,
    /// Receiver methods match a contract by shape: they are candidates for every contract.
    inherent: HashMap<Name, Vec<&'a MethodRef>>,
    inherent_variable: Vec<&'a MethodRef>,
}

impl<'a> ContractMethods<'a> {
    pub fn new(syms: ms_syntax::Names, methods: &'a [MethodRef]) -> Self {
        let mut index = ContractMethods {
            by_receiver: HashMap::default(),
            by_variable: HashMap::default(),
            inherent: HashMap::default(),
            inherent_variable: Vec::new(),
        };
        for m in methods {
            let Some(contract) = &m.contract else {
                continue;
            };
            if m.is_inherent(syms) {
                if m.decl.is_none() {
                    continue;
                }
                if m.variables.iter().any(|v| v.id == m.receiver.id) {
                    index.inherent_variable.push(m);
                } else {
                    index.inherent.entry(m.receiver.id).or_default().push(m);
                }
                continue;
            }
            if m.variables.iter().any(|v| v.id == m.receiver.id) {
                index.by_variable.entry(contract.id).or_default().push(m);
            } else {
                index
                    .by_receiver
                    .entry((contract.id, m.receiver.id))
                    .or_default()
                    .push(m);
            }
        }
        index
    }

    /// The methods implementing `contract` whose receiver can match `receiver`.
    pub fn of(&self, contract: Name, receiver: Name) -> impl Iterator<Item = &'a MethodRef> + '_ {
        let exact = self.by_receiver.get(&(contract, receiver));
        let variable = self.by_variable.get(&contract);
        let own = self.inherent.get(&receiver);
        exact
            .into_iter()
            .chain(variable)
            .chain(own)
            .flatten()
            .chain(&self.inherent_variable)
            .copied()
    }
}

pub struct Context<'a> {
    pub m: &'a ModuleHir,
    pub c: &'a Callable,
    pub classes: &'a Classifier,
    pub summaries: &'a Summaries,
    /// The implementations an interface conversion uses.
    pub methods: &'a ContractMethods<'a>,
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
    /// This binding belongs to a nested lambda, whose closes do not return from the callable.
    in_lambda: bool,
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
        meta: HashMap::default(),
        active: Default::default(),
        pending: Vec::new(),
        carried: Vec::new(),
        declared: Vec::new(),
        consumed: HashSet::default(),
        consumed_at: HashMap::default(),
        move_note: None,
        callees: HashSet::default(),
        escaped: cx.escaped.clone(),
        positions: HashMap::default(),
        mutated: Vec::new(),
        captured: Vec::new(),
        hidden: 0,
        var_fixes: HashMap::default(),
        used: cx.live.uses.keys().map(|(_, uid)| *uid).collect(),
        nested_cache: HashMap::default(),
        resources: Vec::new(),
        arm_payloads: Vec::new(),
        chain_places: HashMap::default(),
        keep_scrutinee: false,
        closed: HashSet::default(),
        close_completions: HashSet::default(),
        borrow_receiver: false,
        borrow_params: Vec::new(),
        borrow_path: None,
        owned_return: None,
        borrowed_return: None,
        wrap_returns: Vec::new(),
        plain_borrowed: false,
        plain_result_borrowed: false,
        close_error_return: false,
        borrowed_cases: 0,
        owned_cases: 0,
        ret_ctors: Vec::new(),
        borrow_not_clonable: false,
        borrowed_mask: 0,
        view_return: false,
        view_locals: HashSet::default(),
        view_calls: HashSet::default(),
        view_move: None,
        self_assign: None,
        entry_lambda: None,
    };
    w.run();
    w.unclosed_resources();
    w.consumed_param_resources();
    w.implicit_close_return();
    w.mixed_returns();
    w.moved_payloads();
    let declared = Summary::declared(&cx.c.func);
    let summary = Summary {
        receiver: match (declared.receiver, w.receiver_consumed()) {
            (ParamMode::Borrow, true) => ParamMode::Move,
            (mode, _) => mode,
        },
        consumed_at: cx
            .c
            .parameters
            .iter()
            .take(declared.params.len())
            .map(|b| w.consumed_at.get(&b.uid).copied())
            .collect(),
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
                && ((w.owned_return.is_none() && w.owned_cases == 0)
                    || w.view_return
                    || w.borrowed_mask != 0),
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
    active: active::ActiveBorrows,
    /// Holders whose last use ran in this statement: released at its end.
    pending: Vec<usize>,
    /// Promise borrows of a promise just moved on: its new holder (a binding, a local container)
    /// takes them over, so the borrow outlives the name that started the promise.
    carried: Vec<Borrow>,
    /// Bindings in scope, innermost last.
    declared: Vec<usize>,
    /// Parameters and the receiver that were moved from.
    consumed: HashSet<usize>,
    /// Where each of those was first moved from.
    consumed_at: HashMap<usize, Pos>,
    /// The callee consumption behind the argument being walked, named in a move diagnostic.
    move_note: Option<super::modes::Consumed>,
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
    /// The fix that makes each immutable `name := value` binding a `var`.
    var_fixes: HashMap<usize, DiagnosticFix>,
    /// Bindings that are read, changed or moved somewhere after their declaration.
    used: HashSet<usize>,
    /// `nested_writes` by expression, so a long chain is walked once.
    nested_cache: HashMap<NodeId, Vec<Place>>,
    /// Owned immutable and `var` resources: binding, name and declaration position.
    resources: Vec<(usize, Name, Pos, bool)>,
    /// Payload bindings of match arms over a consumed scrutinee.
    arm_payloads: Vec<usize>,
    /// The optional place each `?.` payload binding was read from.
    chain_places: HashMap<usize, PlaceInfo>,
    /// The scrutinee being walked stays borrowed, never consumed at its last use.
    keep_scrutinee: bool,
    /// Bindings that had `close()` called on them.
    closed: HashSet<usize>,
    /// Completed explicit closes or whole-binding replacements, by expression and binding.
    close_completions: HashSet<(NodeId, usize)>,
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
    wrap_returns: Vec<(NodeId, u8)>,
    /// Some returned reference is the part itself, not a wrapper of it.
    plain_borrowed: bool,
    /// A whole Result returned as a reference, rather than a source-level wrapper.
    plain_result_borrowed: bool,
    /// Cleanup contributes an owned Error outcome not written as a source return.
    close_error_return: bool,
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

/// `no_clone`, and a type or alternative holding a function value, which `Classifier::clonable`
/// rejects.
fn clone_blocker(t: &Ty) -> Option<&'static str> {
    no_clone(t).or_else(|| {
        holds_function(t).then_some(
            "a value that holds a function cannot be cloned (a function value has one owner)",
        )
    })
}

fn insert_at(pos: Pos, text: &str) -> DiagnosticFix {
    DiagnosticFix {
        pos,
        end: pos,
        replacement: text.to_string(),
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
        let mut positions = Positions(HashMap::default());
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
    /// is a type, alternative or collection that closes the resources it holds.
    fn closable(&self, s: &Stmt, ty: &Ty) -> bool {
        self.cx.m.stmt(s).cleanup.is_some()
            || matches!(
                ty.kind,
                Kind::Type | Kind::Alternative | Kind::Native | Kind::Variable
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
                && matches!(b.ty.kind, Kind::Type | Kind::Alternative | Kind::Native);
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
        // Arms that do not all yield references produce an owned value, so a place among them
        // is moved or must be cloned, even when the match itself is only read. An optional chain
        // keeps its own rule for the part it reaches.
        let arm_demand =
            if !borrowed && !returning && d == Demand::Read && !arms.iter().any(|a| a.chain) {
                Demand::Move
            } else {
                d
            };
        let borrowed_before = self.borrowed_return;
        let view_before = self.view_return;
        let entry = self.active.clone();
        let mut joined = active::ActiveBorrows::default();
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
                    self.expr(v, arm_demand);
                }
                self.release_pending();
            }
            let ended: Vec<usize> = self.declared.drain(mark..).collect();
            let end: active::ActiveBorrows = std::mem::take(&mut self.active)
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
        self.mutated.push(HashSet::default());
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
                // A promise's entry runs once and owns a resource it captures, so it may change it.
                if changed && !(concurrent && class == Class::Resource) {
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
                            format!("this closure outlives the statement but captures the `var` `{name_t}`, which is used again{later}; the closure would keep a stale value, so bind an immutable snapshot with `snapshot := {name_t}` before the closure and capture `snapshot`", name_t = self.syms.str(name)),
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
                self.error(
                    e.pos,
                    format!("this closure outlives the statement but captures `{name_t}`, which is borrowed, not owned; capture `{name_t}.{CLONE}()` instead", name_t = self.syms.str(name)),
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
                self.error(
                    e.pos,
                    format!("this closure outlives the statement, so it takes `{name_t}` with it, but `{name_t}` is used again{later}; capture `{name_t}.{CLONE}()` to keep the original", name_t = self.syms.str(name)),
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
        || t.args
            .iter()
            .any(|a| type_any::<false>(a, |t| t.is_source_type(syms, PROMISE_MODULE, "Promise")))
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

#[cfg(test)]
mod type_query_tests {
    use super::*;
    use crate::types::Param;
    use std::{cell::RefCell, rc::Rc};

    fn pair(syms: ms_syntax::Names, left: Ty, right: Ty) -> Ty {
        let mut t = Type::new(syms, n("Pair"), n("test/Pair"), Kind::Type);
        t.args = vec![left, right];
        Rc::new(t)
    }

    fn shared(syms: ms_syntax::Names, mut t: Ty, depth: usize) -> Ty {
        for _ in 0..depth {
            t = pair(syms, t.clone(), t);
        }
        t
    }

    fn promise(syms: ms_syntax::Names, module: &str) -> (Ty, SymRef) {
        let sym = Rc::new(Sym {
            name: n("Promise"),
            id: n(&format!("{module}/Promise")),
            kind: SymKind::Type,
            module: n(module),
            native: Native::Source,
            export: true,
            ty: RefCell::new(None),
            variables: RefCell::new(vec![]),
            decl: None,
        });
        let mut t = Type::new(syms, sym.name, sym.id, Kind::Type);
        t.def = Some(Definition::new(&sym, Kind::Type));
        (Rc::new(t), sym)
    }

    #[test]
    fn promise_search_bounds_shared_arguments_and_keeps_source_identity() {
        let syms = ms_syntax::Names::global();
        let negative = shared(syms, int(), 30);
        assert!(!ty_holds_promise(syms, &negative));
        let (foreign, _foreign_symbol) = promise(syms, "application.ms");
        assert!(!ty_holds_promise(syms, &foreign));
        let (promise, _promise_symbol) = promise(syms, PROMISE_MODULE);
        assert!(ty_holds_promise(syms, &promise));
        assert!(ty_holds_promise(syms, &pair(syms, negative, promise)));
    }

    #[test]
    fn promise_search_keeps_argument_only_edges() {
        let syms = ms_syntax::Names::global();
        let (promise, _symbol) = promise(syms, PROMISE_MODULE);
        let mut function = Type::new(syms, n("fn"), n("fn"), Kind::Function);
        function
            .params
            .push(Param::new(n("value"), promise.clone()));
        function.result = Some(promise.clone());
        assert!(!ty_holds_promise(syms, &Rc::new(function.clone())));
        function.args.push(promise);
        assert!(ty_holds_promise(syms, &Rc::new(function)));
    }
}

//! Ownership and exclusivity for value semantics. See `OWNERSHIP.md`.
//!
//! Every value has one owner. Plain values copy implicitly; the rest move at
//! their last use into a moving position, and `.clone()`
//! duplicates explicitly. Mutation needs `var`, marked at the declaration and
//! at every call. Borrows are lexical: while a binding borrows from a place,
//! that place may not change. The pass rejects programs that break these
//! rules and records, for lowering, how every use treats its value.

mod classify;
mod facts;
pub use facts::{BindingFact, BindingFlags, Fact, NodeFacts};
mod live;
mod modes;
mod native_borrow;
pub use native_borrow::{NativeBorrow, native_borrow};
mod moved;
pub(crate) mod places;
mod walk;

pub use classify::{Class, Classifier};
pub use modes::{CallModes, ParamMode, native_method_argument_modes};
pub use places::Place;

/// How the caller comes to own the result of a borrow-returning call over a temporary.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OwnedBorrow {
    /// The result is a part of the temporary: cloned out before the temporary is dropped.
    Clone,
    /// The result is the whole temporary passed as the receiver (`None`) or as the parameter
    /// with this label: the caller keeps the temporary instead of dropping it, no clone.
    Whole(Option<Name>),
}

use crate::fxmap::{HashMap, HashSet};
use crate::hir::*;
use crate::types::*;
use modes::{Key, Summaries};
use ms_syntax::Diagnostic;
use ms_syntax::ast::NodeId;

/// How a use treats the value it names.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Access {
    /// A duplicate of a `Copy`-class value.
    Copy,
    /// A read in place; ownership stays.
    Borrow,
    /// A change in place (`var`).
    Mutate,
    /// Ownership leaves the binding; it is dead until reassigned.
    Move,
    /// The binding is reassigned; the old value is dropped.
    Write,
}

/// One use of a local binding.
#[derive(Clone, Debug)]
pub struct Use {
    /// The name expression; the lambda for a capture; the statement for a write.
    pub node: NodeId,
    /// The binding's identity.
    pub binding: usize,
    /// How the value is used.
    pub access: Access,
    /// No later use of the value can run on any path.
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
    /// A match arm payload variable.
    Arm,
    /// A lambda parameter.
    LambdaParameter,
}

/// Facts about one binding.
#[derive(Clone)]
pub struct BindingFacts {
    /// The binding.
    pub binding: BindingRef,
    /// How it was introduced.
    pub role: Role,
    /// How its values move.
    pub class: Class,
    /// It holds its own value and drops it at scope end unless moved. A
    /// parameter is owned only when its callable moving_params it.
    pub owned: bool,
    /// Where a non-owning binding borrows from (empty for owned bindings).
    pub borrows: Vec<Place>,
    /// The binding is a `var` borrow: changes through it change the origin.
    pub exclusive: bool,
}

/// How a binding borrows the place it names.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum BorrowKind {
    /// `let`: reads while the origin stays unchanged.
    Shared,
    /// `var`: changes through it change the origin.
    Exclusive,
}

/// How a lambda holds what it captures.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CaptureMode {
    /// A snapshot of a `Copy`-class value.
    Copy,
    /// Ownership moves into the closure.
    Move,
    /// Reads the variable in place while the closure lives.
    Borrow,
    /// Changes the variable in place; the closure holds exclusive access.
    BorrowMut,
}

/// Facts about one lambda.
#[derive(Clone, Debug)]
pub struct LambdaFacts {
    /// The closure outlives the statement that made it: it is returned,
    /// stored, or passed to a moving parameter.
    pub escaping: bool,
    /// Captured bindings and how each is held.
    pub captures: Vec<(usize, CaptureMode)>,
}

/// Ownership facts of one callable, nested lambdas included.
#[derive(Default)]
pub struct CallableOwnership {
    /// Uses by (node, binding identity).
    pub uses: HashMap<(NodeId, usize), Use>,
    /// Bindings by identity.
    pub bindings: HashMap<usize, BindingFacts>,
    /// Modes of each call expression.
    pub calls: HashMap<NodeId, CallModes>,
    /// Lambdas by expression.
    pub lambdas: HashMap<NodeId, LambdaFacts>,
    /// Owned values created and not consumed by their expression: dropped at
    /// the end of the enclosing statement.
    pub temporaries: HashSet<NodeId>,
    /// Assignments that store over a binding: the old value is dropped unless
    /// an earlier `Access::Move` of it cleared the binding's drop flag.
    pub drops_old: HashSet<NodeId>,
    /// Field paths that move out of an owned binding at their last use (`return b.items`), by the
    /// member expression. The value is still copied where it is consumed; the rest of the binding
    /// is cleaned up as before.
    pub partial_moves: HashMap<NodeId, Place>,
    /// The part of `partial_moves` that are resources, by root binding: lowering moves these
    /// without copying and closes the rest of the binding around the hole.
    pub resource_moves: HashMap<usize, HashMap<NodeId, Vec<Name>>>,
    /// Resource bindings that nothing takes: lowering closes them when their scope ends.
    pub implicit_closes: HashSet<usize>,
    /// Closed resource bindings the program also closes by an explicit `.close()` call: the
    /// scope end still releases them, but a result the program handled is not returned again.
    pub explicit_closes: HashSet<usize>,
    /// Every lifetime transfers or has its scope-close result handled before scope exit.
    pub handled_scope_closes: HashSet<usize>,
    /// For a closed resource binding that is also moved on some paths: the name expressions
    /// that move it. The close at scope end runs only on the paths with no move.
    pub close_moves: HashMap<usize, HashSet<NodeId>>,
    /// Payload bindings of a consumed match scrutinee that some path moves out.
    pub moved_payloads: HashSet<usize>,
    /// Parameter modes in declaration order.
    pub parameters: Vec<ParamMode>,
    /// The receiver's mode, for a method.
    pub receiver: Option<ParamMode>,
    /// The result is a reference into the receiver or a parameter on every path: lowering
    /// returns it without copying, and the caller holds it without dropping.
    pub returns_borrow: bool,
    /// With `returns_borrow`: the result is an owned interface view of the arguments (a converted borrowed
    /// value, `iface.borrow`): the caller drops it and holds the arguments while it lives.
    pub view: bool,
    /// With `view`: the cases of a `Result` result that lend (`modes::BORROWED_OK`, `BORROWED_ERROR`).
    pub borrowed_cases: u8,
    /// With `borrowed_cases`: the `ok(..)` / `error(..)` constructors in return position.
    pub ret_ctors: HashSet<NodeId>,
    /// Wrappers of a borrowed value (`x` as `x?`, `ok(x)`, `error(x)`) that stay references:
    /// lowering builds them with `opt.view` / `alt.view` instead of copying the payload.
    pub view_wraps: HashSet<NodeId>,
    /// Method values (`re.find`) that stay local and borrow their receiver's place while they
    /// live: lowering captures the receiver's address instead of copying the receiver.
    pub bound_borrows: HashSet<NodeId>,
    /// Name expressions that move an interface view out of the local holding it, into a result
    /// that holds the same origins: lowering takes the value and leaves a view that owns nothing.
    pub view_moves: HashSet<NodeId>,
    /// Calls of borrow-returning callables whose sources are temporaries: the caller owns the result,
    /// by taking the temporary over or by a copy made before it is dropped.
    pub owned_borrows: HashMap<NodeId, OwnedBorrow>,
    /// Calls bound with `var` as an exclusive borrow of the field chain the callee returns, by
    /// call node: lowering names that place instead of calling.
    pub getter_borrows: HashMap<NodeId, Vec<Name>>,
    /// Conditional and match expressions whose value is a reference on every arm: lowering
    /// joins the arms without copying.
    pub borrowed_matches: HashSet<NodeId>,
    /// Native reads used in place from origins that remain held.
    pub borrowed_reads: HashSet<NodeId>,
}

/// The ownership facts lowering and tooling read, in one value: the tables the ownership walk
/// derives for a whole program, none of them recomputed by a later stage.
#[derive(Default)]
pub struct OwnershipFacts {
    /// Name expressions that move a closed resource binding, by binding.
    pub close_moves: HashMap<usize, HashSet<NodeId>>,
    /// Resource fields moved out of an owned binding, by binding and member node.
    pub resource_moves: HashMap<usize, HashMap<NodeId, Vec<Name>>>,
    /// Every move of a whole binding, by binding: the name expressions (or lambdas) that take
    /// its value. Lowering moves the value out there instead of copying it, and drops the
    /// binding at scope end only on the paths that kept it.
    pub moves: HashMap<usize, HashSet<NodeId>>,
    /// Captures a non-escaping lambda only reads in place, by module file, lambda node and
    /// binding identity: the closure may point at the variable instead of copying it.
    pub borrowed_captures: HashSet<(Name, NodeId, usize)>,
    /// For each callable with a `Consume` parameter or receiver, which parameters (declaration
    /// order, the receiver first for a method) the body moves, stores or returns.
    pub moving_params: HashMap<Key, Vec<bool>>,
    /// Boolean per-node facts (returners, view wraps, bound borrows, view moves, borrowed matches).
    pub node_facts: NodeFacts,
    /// Boolean per-binding facts (borrows, closes, moved payloads, conditional moves).
    pub binding_facts: BindingFlags,
    /// Borrow-returning calls whose result the caller owns (a source was a temporary), by module file and
    /// call node.
    pub owned_borrows: HashMap<(Name, NodeId), OwnedBorrow>,
    /// `var` bindings of a borrow-returning call, by module file and call node: the field chain of the
    /// argument the binding borrows exclusively.
    pub getter_borrows: HashMap<(Name, NodeId), Vec<Name>>,
}

/// Ownership of a whole program: the facts, per-callable detail, and the rejections found.
pub struct Ownership {
    facts: HashMap<Key, CallableOwnership>,
    /// Rejected programs, in callable order.
    pub diagnostics: Vec<Diagnostic>,
    /// The facts lowering and tooling read.
    pub tables: OwnershipFacts,
}

impl Ownership {
    /// Facts of one callable.
    pub fn of(&self, c: &Callable) -> Option<&CallableOwnership> {
        self.facts.get(&(c.module.file, c.id()))
    }
}

impl Hir<'_> {
    /// Checks ownership rules and computes move, borrow and drop facts for
    /// every callable of the user's modules.
    pub fn ownership(&self) -> Ownership {
        let classes = Classifier::new(self.program());
        let modules: HashMap<Name, ModuleHir> = self.modules().map(|m| (m.data.file, m)).collect();
        let callables: Vec<Callable> = self
            .callables()
            .into_iter()
            .filter(|c| modules.contains_key(&c.module.file))
            .collect();
        let liveness: Vec<live::Liveness> = callables
            .iter()
            .map(|c| live::liveness(&modules[&c.module.file], c))
            .collect();
        let mut summaries = Summaries::default();
        let mut escaped: HashMap<Key, HashSet<NodeId>> = HashMap::default();
        let mut outcomes: Vec<Option<walk::Outcome>> = callables.iter().map(|_| None).collect();
        // The summaries each callable read in its last analysis. A later round re-analyzes it only
        // when one of them changed, or its own escaped lambdas did; its outcome is a function of
        // those inputs alone, so the kept one equals a fresh one.
        let mut reads: Vec<HashSet<Key>> = vec![HashSet::default(); callables.len()];
        let mut changed_before: HashSet<Key> = HashSet::default();
        let mut escaped_before: HashSet<usize> = HashSet::default();
        // Parameter modes, closure escapes and result slots feed each other, and each step
        // carries a fact one call further, so a chain needs about one round per callable.
        let rounds = callables.len() + 16;
        let contract_methods =
            walk::ContractMethods::new(ms_syntax::Names::global(), &self.program().methods);
        for round in 0..=rounds {
            let mut changed_now: HashSet<Key> = HashSet::default();
            let mut escaped_now: HashSet<usize> = HashSet::default();
            for (i, (c, l)) in callables.iter().zip(&liveness).enumerate() {
                if round > 0
                    && !escaped_before.contains(&i)
                    && !reads[i].iter().any(|k| changed_before.contains(k))
                {
                    continue;
                }
                let key = (c.module.file, c.id());
                let known = escaped.entry(key).or_default().clone();
                let out = walk::analyze(&walk::Context {
                    m: &modules[&c.module.file],
                    c,
                    classes: &classes,
                    summaries: &summaries,
                    methods: &contract_methods,
                    live: l,
                    escaped: &known,
                });
                reads[i] = summaries.take_reads();
                // The last pass keeps the over-approximated summaries for every callee.
                if round < rounds && summaries.decls.get(&key) != Some(&out.summary) {
                    summaries.decls.insert(key, out.summary.clone());
                    changed_now.insert(key);
                }
                if out.escaped != known {
                    escaped.insert(key, out.escaped.clone());
                    escaped_now.insert(i);
                }
                outcomes[i] = Some(out);
            }
            if changed_now.is_empty() && escaped_now.is_empty() {
                break;
            }
            changed_before = changed_now;
            escaped_before = escaped_now;
        }
        let outcomes = outcomes
            .into_iter()
            .map(|o| o.expect("round 0 analyzes every callable"));
        let mut facts = HashMap::default();
        let mut diagnostics = Vec::new();
        let mut binding_facts = BindingFlags::default();
        let mut close_moves = HashMap::default();
        let mut moves: HashMap<usize, HashSet<NodeId>> = HashMap::default();
        let mut resource_moves = HashMap::default();
        let mut borrowed_captures = HashSet::default();
        let mut moving_params = HashMap::default();
        let mut owned_borrows = HashMap::default();
        let mut getter_borrows = HashMap::default();
        let mut node_facts = NodeFacts::default();
        for (c, out) in callables.iter().zip(outcomes) {
            let file = c.module.file;
            for n in &out.facts.borrowed_matches {
                node_facts.set(file, *n, Fact::BorrowedMatch);
            }
            for n in &out.facts.borrowed_reads {
                node_facts.set(file, *n, Fact::BorrowedRead);
            }
            if out.facts.returns_borrow && out.facts.view {
                node_facts.set(c.module.file, c.id(), Fact::ReturnsView);
            } else if out.facts.returns_borrow {
                node_facts.set(c.module.file, c.id(), Fact::ReturnsBorrow);
            }
            if out.facts.borrowed_cases & modes::BORROWED_OK != 0 {
                node_facts.set(c.module.file, c.id(), Fact::BorrowedOk);
            }
            if out.facts.borrowed_cases & modes::BORROWED_ERROR != 0 {
                node_facts.set(c.module.file, c.id(), Fact::BorrowedError);
            }
            for n in out.facts.partial_moves.keys() {
                node_facts.set(file, *n, Fact::PartialMove);
            }
            for n in &out.facts.ret_ctors {
                node_facts.set(file, *n, Fact::RetCtor);
            }
            for n in &out.facts.view_wraps {
                node_facts.set(file, *n, Fact::ViewWrap);
            }
            for n in &out.facts.bound_borrows {
                node_facts.set(file, *n, Fact::BoundBorrow);
            }
            for n in &out.facts.view_moves {
                node_facts.set(file, *n, Fact::ViewMove);
            }
            owned_borrows.extend(
                out.facts
                    .owned_borrows
                    .iter()
                    .map(|(n, how)| ((c.module.file, *n), *how)),
            );
            getter_borrows.extend(
                out.facts
                    .getter_borrows
                    .iter()
                    .map(|(n, f)| ((c.module.file, *n), f.clone())),
            );
            for (node, lambda) in &out.facts.lambdas {
                for (uid, mode) in &lambda.captures {
                    if !lambda.escaping && *mode == CaptureMode::Borrow {
                        borrowed_captures.insert((c.module.file, *node, *uid));
                    }
                }
            }
            for f in out.facts.bindings.values() {
                let fact = if f.exclusive {
                    BindingFact::ExclusiveBorrow
                } else if !f.owned && !f.borrows.is_empty() && f.class != Class::Copy {
                    BindingFact::SharedBorrow
                } else {
                    continue;
                };
                binding_facts.set(f.binding.uid, fact);
            }
            for u in &out.facts.implicit_closes {
                binding_facts.set(*u, BindingFact::ImplicitClose);
            }
            for u in &out.facts.explicit_closes {
                binding_facts.set(*u, BindingFact::ExplicitClose);
            }
            for u in &out.facts.handled_scope_closes {
                binding_facts.set(*u, BindingFact::CloseHandled);
            }
            close_moves.extend(out.facts.close_moves.iter().map(|(k, v)| (*k, v.clone())));
            for u in &out.facts.moved_payloads {
                binding_facts.set(*u, BindingFact::MovedPayload);
            }
            let mut moved: HashSet<(NodeId, usize)> = HashSet::default();
            for u in out.facts.uses.values() {
                if u.access == Access::Move {
                    moves.entry(u.binding).or_default().insert(u.node);
                    moved.insert((u.node, u.binding));
                }
            }
            if !moved.is_empty() {
                for u in moved::conditional(&modules[&c.module.file], c, &moved) {
                    binding_facts.set(u, BindingFact::ConditionalMove);
                }
            }
            resource_moves.extend(
                out.facts
                    .resource_moves
                    .iter()
                    .map(|(k, v)| (*k, v.clone())),
            );
            let modes: Vec<bool> = out
                .facts
                .receiver
                .iter()
                .chain(&out.facts.parameters)
                .map(|m| *m == ParamMode::Move)
                .collect();
            if modes.contains(&true) {
                moving_params.insert((c.module.file, c.id()), modes);
            }
            diagnostics.extend(out.diagnostics);
            facts.insert((c.module.file, c.id()), out.facts);
        }
        Ownership {
            facts,
            diagnostics,
            tables: OwnershipFacts {
                close_moves,
                resource_moves,
                moves,
                borrowed_captures,
                moving_params,
                node_facts,
                binding_facts,
                owned_borrows,
                getter_borrows,
            },
        }
    }
}

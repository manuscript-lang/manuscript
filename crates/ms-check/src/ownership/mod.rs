//! Ownership and exclusivity for value semantics. See `OWNERSHIP.md`.
//!
//! Every value has one owner. Plain values copy implicitly; the rest move at
//! their last use into a consuming position, and `.clone()` (later `.copy()`)
//! duplicates explicitly. Mutation needs `var`, marked at the declaration and
//! at every call. Borrows are lexical: while a binding borrows from a place,
//! that place may not change. The pass rejects programs that break these
//! rules and records, for lowering, how every use treats its value.

mod classify;
mod live;
mod modes;
mod places;
mod walk;

pub use classify::{Class, Classifier};
pub use modes::{CallModes, ParamMode};
pub use places::{Place, Step};

/// How the caller comes to own the result of a lending call over a temporary.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OwnedLend {
    /// The result is a part of the temporary: copied out before the temporary is dropped.
    Copy,
    /// The result is the whole temporary passed as the receiver (`None`) or as the parameter
    /// with this label: the caller keeps the temporary instead of dropping it, no copy.
    Whole(Option<Name>),
}

use crate::hir::*;
use crate::types::*;
use modes::{Key, Summaries};
use ms_syntax::Diagnostic;
use ms_syntax::ast::NodeId;
use std::collections::{HashMap, HashSet};

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
    /// parameter is owned only when its callable consumes it.
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
    /// stored, or passed to a consuming parameter.
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
    /// Matches (and `if let`, by statement) whose scrutinee is consumed:
    /// payload bindings own their parts.
    pub consumed_scrutinees: HashSet<NodeId>,
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
    pub lends: bool,
    /// Calls of lending callables whose sources are temporaries: the caller owns the result,
    /// by taking the temporary over or by a copy made before it is dropped.
    pub owned_lends: HashMap<NodeId, OwnedLend>,
    /// Calls bound with `var` as an exclusive borrow of the field chain the callee returns, by
    /// call node: lowering names that place instead of calling.
    pub getter_borrows: HashMap<NodeId, Vec<Name>>,
    /// Conditional and match expressions whose value is a reference on every arm: lowering
    /// joins the arms without copying.
    pub lent_matches: HashSet<NodeId>,
}

impl CallableOwnership {
    /// The use of `binding` at `node`.
    pub fn use_at(&self, node: NodeId, binding: &BindingRef) -> Option<&Use> {
        self.uses.get(&(node, binding.uid))
    }
}

/// Ownership facts of a whole program, with the rejections found.
pub struct Ownership {
    facts: HashMap<Key, CallableOwnership>,
    /// Rejected programs, in callable order.
    pub diagnostics: Vec<Diagnostic>,
    /// Bindings that borrow a place another binding owns, by identity. A binding of a
    /// temporary owns its value and is absent.
    pub borrows: HashMap<usize, BorrowKind>,
    /// Resource bindings closed implicitly when their scope ends.
    pub closes: HashSet<usize>,
    /// Closed resource bindings with an explicit `.close()` call.
    pub explicit_closes: HashSet<usize>,
    /// Name expressions that move a closed resource binding, by binding.
    pub close_moves: HashMap<usize, HashSet<NodeId>>,
    /// Resource fields moved out of an owned binding, by binding and member node.
    pub resource_moves: HashMap<usize, HashMap<NodeId, Vec<Name>>>,
    /// Payload bindings of a consumed match scrutinee that some path moves out.
    pub moved_payloads: HashSet<usize>,
    /// Calls bound with `var` as a mutable borrow, by module file and node: the fields from the
    /// argument to the part they borrow.
    /// Captures a non-escaping lambda only reads in place, by module file, lambda node and
    /// binding identity: the closure may point at the variable instead of copying it.
    pub borrowed_captures: HashSet<(Name, NodeId, usize)>,
    /// For each callable with a `Consume` parameter or receiver, which parameters (declaration
    /// order, the receiver first for a method) the body moves, stores or returns.
    pub consumes: HashMap<Key, Vec<bool>>,
    /// Callables whose result is a reference into their arguments.
    pub lenders: HashSet<Key>,
    /// Lending calls whose result the caller owns (a source was a temporary), by module file and
    /// call node.
    pub owned_lends: HashMap<(Name, NodeId), OwnedLend>,
    /// `var` bindings of a lending call, by module file and call node: the field chain of the
    /// argument the binding borrows exclusively.
    pub getter_borrows: HashMap<(Name, NodeId), Vec<Name>>,
    /// Conditional and match expressions whose value is a reference, by module file and node.
    pub lent_matches: HashSet<(Name, NodeId)>,
}

impl Ownership {
    /// Facts of one callable.
    pub fn of(&self, c: &Callable) -> Option<&CallableOwnership> {
        self.facts.get(&(c.module.file, c.id()))
    }
}

/// Standard-library source modules not yet ownership clean. Every other module, user or
/// standard library, is checked and lowered under the same rules. Fix a module, then delete
/// its entry.
const UNVETTED: &[&str] = &[];

/// Whether the ownership checker vets this module.
pub fn is_vetted(file: Name) -> bool {
    !UNVETTED.contains(&file.as_str())
}

impl Hir<'_> {
    /// Checks ownership rules and computes move, borrow and drop facts for
    /// every callable of the user's modules.
    pub fn ownership(&self) -> Ownership {
        let classes = Classifier::new(self.program());
        let modules: HashMap<Name, ModuleHir> = self
            .modules()
            .filter(|m| is_vetted(m.data.file))
            .map(|m| (m.data.file, m))
            .collect();
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
        let mut escaped: HashMap<Key, HashSet<NodeId>> = HashMap::new();
        let mut outcomes: Vec<walk::Outcome> = Vec::new();
        // Parameter modes, closure escapes and result slots feed each other, and each step
        // carries a fact one call further, so a chain needs about one round per callable.
        let rounds = callables.len() + 16;
        for round in 0..=rounds {
            outcomes.clear();
            let mut changed = false;
            for (c, l) in callables.iter().zip(&liveness) {
                let key = (c.module.file, c.id());
                let known = escaped.entry(key).or_default().clone();
                let out = walk::analyze(&walk::Context {
                    m: &modules[&c.module.file],
                    c,
                    classes: &classes,
                    summaries: &summaries,
                    methods: &self.program().methods,
                    live: l,
                    escaped: &known,
                });
                // The last pass keeps the over-approximated summaries for every callee.
                if round < rounds && summaries.get(&key) != Some(&out.summary) {
                    summaries.decls.insert(key, out.summary.clone());
                    changed = true;
                }
                if out.escaped != known {
                    escaped.insert(key, out.escaped.clone());
                    changed = true;
                }
                outcomes.push(out);
            }
            if !changed {
                break;
            }
        }
        let mut facts = HashMap::new();
        let mut diagnostics = Vec::new();
        let mut borrows = HashMap::new();
        let mut closes = HashSet::new();
        let mut explicit_closes = HashSet::new();
        let mut close_moves = HashMap::new();
        let mut moved_payloads = HashSet::new();
        let mut resource_moves = HashMap::new();
        let mut borrowed_captures = HashSet::new();
        let mut consumes = HashMap::new();
        let mut lenders = HashSet::new();
        let mut owned_lends = HashMap::new();
        let mut getter_borrows = HashMap::new();
        let mut lent_matches = HashSet::new();
        for (c, out) in callables.iter().zip(outcomes) {
            lent_matches.extend(out.facts.lent_matches.iter().map(|n| (c.module.file, *n)));
            if out.facts.lends {
                lenders.insert((c.module.file, c.id()));
            }
            owned_lends.extend(
                out.facts
                    .owned_lends
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
                let kind = if f.exclusive {
                    BorrowKind::Exclusive
                } else if !f.owned && !f.borrows.is_empty() && f.class != Class::Copy {
                    BorrowKind::Shared
                } else {
                    continue;
                };
                borrows.insert(f.binding.uid, kind);
            }
            closes.extend(out.facts.implicit_closes.iter().copied());
            explicit_closes.extend(out.facts.explicit_closes.iter().copied());
            close_moves.extend(out.facts.close_moves.iter().map(|(k, v)| (*k, v.clone())));
            moved_payloads.extend(out.facts.moved_payloads.iter().copied());
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
                .map(|m| *m == ParamMode::Consume)
                .collect();
            if modes.contains(&true) {
                consumes.insert((c.module.file, c.id()), modes);
            }
            diagnostics.extend(out.diagnostics);
            facts.insert((c.module.file, c.id()), out.facts);
        }
        Ownership {
            facts,
            diagnostics,
            borrows,
            closes,
            explicit_closes,
            close_moves,
            resource_moves,
            moved_payloads,
            borrowed_captures,
            consumes,
            lenders,
            owned_lends,
            getter_borrows,
            lent_matches,
        }
    }
}

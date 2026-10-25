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

pub use classify::Class;
pub use modes::{CallModes, ParamMode, ResultOrigin, Slot};
pub use places::{Place, Step};

use crate::hir::*;
use crate::types::*;
use classify::Classifier;
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
    /// A `with` resource.
    With,
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
    /// Parameter modes in declaration order.
    pub parameters: Vec<ParamMode>,
    /// The receiver's mode, for a method.
    pub receiver: Option<ParamMode>,
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
    /// Identities of the exclusive borrow bindings.
    pub exclusive: HashSet<usize>,
    /// Pattern and arm bindings that read-borrow a part of a non-`Copy` scrutinee.
    pub read_borrows: HashSet<usize>,
    /// Calls bound with `var` as a mutable borrow, by module file and node: the fields from the
    /// argument to the part they borrow.
    pub getters: HashMap<(Name, NodeId), Vec<Name>>,
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
    /// Records, for each interface operation, what its implementations may hand back.
    /// Returns whether anything changed.
    fn join_contracts(&self, summaries: &mut Summaries) -> bool {
        let mut joined: HashMap<(Name, Name), modes::ResultOrigin> = HashMap::new();
        for m in &self.program().methods {
            let (Some(c), Some(f)) = (&m.contract, &m.decl) else {
                continue;
            };
            let Some(s) = summaries.get(&(m.module, f.id())) else {
                continue;
            };
            let entry = joined.entry((c.id, f.name())).or_default();
            for slot in &s.result.slots {
                if !entry.slots.contains(slot) {
                    entry.slots.push(*slot);
                }
            }
        }
        if joined == summaries.contracts {
            return false;
        }
        summaries.contracts = joined;
        true
    }

    /// Checks the `ref` written in result types: a `ref` result must lend from a parameter or the
    /// receiver, and an implementation agrees with the interface operation it implements.
    fn ref_results(
        &self,
        modules: &HashMap<Name, ModuleHir>,
        callables: &[Callable],
        summaries: &Summaries,
    ) -> Vec<Diagnostic> {
        let diag = |file: Name, pos: ms_syntax::Pos, message: String| Diagnostic {
            file: std::sync::Arc::from(file.as_str()),
            pos,
            phase: ms_syntax::Phase::Type,
            message,
            end: None,
            fix: None,
        };
        let insert_ref = |mut d: Diagnostic, at: ms_syntax::Pos| {
            d.fix = Some(ms_syntax::DiagnosticFix {
                pos: at,
                end: at,
                replacement: "ref ".to_string(),
            });
            d
        };
        let mut out = Vec::new();
        for c in callables {
            let Some(f) = c.func.func() else { continue };
            if f.body.is_empty() {
                continue;
            }
            let lends = summaries
                .get(&(c.module.file, c.id()))
                .is_some_and(|s| !s.result.slots.is_empty());
            if lends && !f.result_ref {
                out.push(insert_ref(
                    diag(
                        c.module.file,
                        f.result.pos,
                        format!(
                            "`{}` returns part of a parameter or the receiver: write `ref` before its result type to lend it, or return an owned copy with `.clone()`",
                            f.name
                        ),
                    ),
                    f.result.pos,
                ));
            }
            if f.result_ref && !lends {
                out.push(diag(
                    c.module.file,
                    f.result.pos,
                    format!(
                        "`{}` returns `ref`, but no `return` gives back part of a parameter or the receiver; drop `ref` to return an owned value",
                        f.name
                    ),
                ));
            }
        }
        for m in &self.program().methods {
            let (Some(contract), Some(decl)) = (&m.contract, &m.decl) else {
                continue;
            };
            let (Some(f), Some(def)) = (decl.func(), &contract.def) else {
                continue;
            };
            if !modules.contains_key(&m.module) {
                continue;
            }
            let declared = def
                .operations
                .borrow()
                .iter()
                .find(|o| o.name == f.name)
                .and_then(|o| o.decl.as_ref().and_then(|d| d.func().map(|f| f.result_ref)));
            let Some(declared) = declared else { continue };
            // A `ref` operation lets an implementation lend or own; an owning operation must not
            // be implemented by a lender, since callers of the contract treat its result as owned.
            if f.result_ref && !declared {
                out.push(diag(
                    m.module,
                    f.result.pos,
                    format!(
                        "`{}` implements an operation that returns an owned result, but this method returns `ref`; declare `ref` on the interface operation or return an owned copy",
                        f.name
                    ),
                ));
            }
        }
        out
    }

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
        // Parameter modes and closure escapes feed each other, and both only
        // grow, so the iteration ends.
        for _ in 0..16 {
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
                    live: l,
                    escaped: &known,
                });
                if summaries.get(&key) != Some(&out.summary) {
                    summaries.decls.insert(key, out.summary.clone());
                    changed = true;
                }
                if out.escaped != known {
                    escaped.insert(key, out.escaped.clone());
                    changed = true;
                }
                outcomes.push(out);
            }
            if self.join_contracts(&mut summaries) {
                changed = true;
            }
            if !changed {
                break;
            }
        }
        let mut facts = HashMap::new();
        let mut diagnostics = self.ref_results(&modules, &callables, &summaries);
        let mut exclusive = HashSet::new();
        let mut read_borrows = HashSet::new();
        let mut getters = HashMap::new();
        for (c, out) in callables.iter().zip(outcomes) {
            let held: Vec<usize> = out
                .facts
                .bindings
                .values()
                .filter(|f| f.exclusive)
                .map(|f| f.binding.uid)
                .collect();
            exclusive.extend(held);
            read_borrows.extend(
                out.facts
                    .bindings
                    .values()
                    .filter(|f| {
                        matches!(f.role, Role::Pattern | Role::Arm)
                            && !f.owned
                            && !f.exclusive
                            && f.class != Class::Copy
                    })
                    .map(|f| f.binding.uid),
            );
            for (node, fields) in out.getters {
                getters.insert((c.module.file, node), fields);
            }
            diagnostics.extend(out.diagnostics);
            facts.insert((c.module.file, c.id()), out.facts);
        }
        Ownership {
            facts,
            diagnostics,
            exclusive,
            read_borrows,
            getters,
        }
    }
}

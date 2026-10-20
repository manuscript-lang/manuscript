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
pub use modes::{CallModes, ParamMode};
pub use places::{Place, Step};

use crate::hir::*;
use crate::types::*;
use classify::Classifier;
use modes::{Key, Summary};
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
    /// The rejections inside callables that hold a mutable borrow.
    pub borrow_diagnostics: Vec<Diagnostic>,
    /// Identities of the exclusive borrow bindings.
    pub exclusive: HashSet<usize>,
}

impl Ownership {
    /// Facts of one callable.
    pub fn of(&self, c: &Callable) -> Option<&CallableOwnership> {
        self.facts.get(&(c.module.file, c.id()))
    }
}

/// Modules the user wrote: not the embedded standard library.
pub(crate) fn is_user_module(file: Name) -> bool {
    !file.as_str().starts_with("@std/")
}

/// Whether a user callable contains `if var` or a `var` binding of a part of another value.
pub(crate) fn uses_mutable_borrow(program: &crate::checker::Program) -> bool {
    use ms_syntax::ast::*;
    struct Scan(bool);
    impl ms_syntax::visit::Visitor for Scan {
        fn stmt(&mut self, s: &Stmt) {
            match &s.kind {
                StmtKind::If {
                    binding: Some(_),
                    mutable: true,
                    ..
                } => self.0 = true,
                StmtKind::Bind {
                    mutable: true,
                    value,
                    ..
                } if matches!(
                    value.kind,
                    ExprKind::Member { .. }
                        | ExprKind::Index { .. }
                        | ExprKind::Apply { value: Some(_), .. }
                ) =>
                {
                    self.0 = true
                }
                _ => {}
            }
        }
    }
    let hir = program.hir();
    hir.callables().iter().any(|c| {
        if !is_user_module(c.module.file) {
            return false;
        }
        let mut scan = Scan(false);
        match c.body() {
            Body::Block(b) => ms_syntax::visit::walk_block(&mut scan, b),
            Body::Expr(e) => ms_syntax::visit::walk_expr(&mut scan, e),
        }
        scan.0
    })
}

impl Hir<'_> {
    /// Checks ownership rules and computes move, borrow and drop facts for
    /// every callable of the user's modules.
    pub fn ownership(&self) -> Ownership {
        let classes = Classifier::new(self.program());
        let modules: HashMap<Name, ModuleHir> = self
            .modules()
            .filter(|m| is_user_module(m.data.file))
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
        let mut summaries: HashMap<Key, Summary> = HashMap::new();
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
                    summaries.insert(key, out.summary.clone());
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
        let mut borrow_diagnostics = Vec::new();
        let mut exclusive = HashSet::new();
        for (c, out) in callables.iter().zip(outcomes) {
            let held: Vec<usize> = out
                .facts
                .bindings
                .values()
                .filter(|f| f.exclusive)
                .map(|f| f.binding.uid)
                .collect();
            if !held.is_empty() {
                borrow_diagnostics.extend(out.diagnostics.iter().cloned());
                exclusive.extend(held);
            }
            diagnostics.extend(out.diagnostics);
            facts.insert((c.module.file, c.id()), out.facts);
        }
        Ownership {
            facts,
            diagnostics,
            borrow_diagnostics,
            exclusive,
        }
    }
}

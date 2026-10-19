//! Typed HIR: the checked program as a query API.
//!
//! The syntax tree plus the per-module fact tables already form a typed,
//! resolved tree, so HIR is a *view* over them instead of a second tree: a
//! lowering pass walks [`Callable`] bodies with [`ms_syntax::visit`] or by
//! hand and asks [`ModuleHir`] what each node means. See `HIR.md`.

use crate::checker::Program;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;

impl Program {
    /// Queries over the checked program.
    pub fn hir(&self) -> Hir<'_> {
        Hir { program: self }
    }
}

/// Query entry point; see [`Program::hir`].
pub struct Hir<'p> {
    program: &'p Program,
}

/// What a callable is.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CallableKind {
    /// A top-level `fn`.
    Function,
    /// A method of an `impl` (inherent methods are desugared to these).
    Method,
    /// A `test` block.
    Test,
    /// A module constant: evaluating it runs the initializer.
    Constant,
}

/// The executable body of a callable.
pub enum Body<'a> {
    /// Statements.
    Block(&'a [Stmt]),
    /// A constant's initializer.
    Expr(&'a Expr),
}

/// A function, method, test or constant with its parameter bindings.
pub struct Callable {
    /// Owning module.
    pub module: ModRef,
    /// Kind.
    pub kind: CallableKind,
    /// Source name (empty for tests).
    pub name: Name,
    /// The declaration or method.
    pub func: FuncRef,
    /// Parameter bindings in declaration order.
    pub parameters: Vec<BindingRef>,
    /// Receiver of a method.
    pub self_binding: Option<BindingRef>,
    /// Injected test fixture.
    pub fixture: Option<BindingRef>,
}

impl Callable {
    /// The executable body.
    pub fn body(&self) -> Body<'_> {
        if let Some(c) = self
            .func
            .decl
            .constant()
            .filter(|_| self.func.index.is_none())
        {
            return Body::Expr(&c.value);
        }
        match (self.func.func(), &self.func.decl.decl().kind) {
            (Some(f), _) => Body::Block(&f.body),
            (None, DeclKind::Test(t)) => Body::Block(&t.body),
            _ => Body::Block(&[]),
        }
    }

    /// Node id of the declaration or method; unique per callable in a module.
    pub fn id(&self) -> NodeId {
        self.func.id()
    }
}

impl Hir<'_> {
    /// Modules in dependency order.
    pub fn modules(&self) -> impl Iterator<Item = ModuleHir> + '_ {
        self.program
            .modules
            .iter()
            .map(|m| ModuleHir { data: m.clone() })
    }

    /// The module checked from this file.
    pub fn module(&self, file: &str) -> Option<ModuleHir> {
        self.modules().find(|m| m.data.file.as_str() == file)
    }

    /// Every callable of every module.
    pub fn callables(&self) -> Vec<Callable> {
        self.modules().flat_map(|m| m.callables()).collect()
    }
}

/// Queries over one checked module.
pub struct ModuleHir {
    /// The module and its fact tables.
    pub data: ModRef,
}

/// What a name or call stands for.
#[derive(Clone)]
pub enum Resolution {
    /// A local variable, parameter, pattern or loop binding.
    Local(BindingRef),
    /// A module constant; each use runs its initializer.
    Constant(SymRef),
    /// A function (source or native).
    Function(SymRef),
    /// A type used as a value.
    Type(SymRef),
    /// A record or alternative-case constructor.
    Constructor {
        /// The constructed type.
        ty: Ty,
        /// The alternative case, for a case constructor.
        case: Option<Name>,
    },
    /// A resolved method (source, contract operation or native view).
    Method(MethodRef),
    /// A compiler-known operation without a symbol: `index`, `view`, ...
    Native(Name),
    /// Nothing resolved: literals, operators and compound expressions.
    Value,
}

/// A supplied call argument.
pub struct CallArgument<'a> {
    /// The written argument.
    pub expr: &'a Expr,
    /// Resolved label and written position.
    pub slot: ArgSlot,
    /// Wrap the value once into this Optional before the call.
    pub wrap_optional: Option<Ty>,
}

/// A resolved call.
pub struct CallView<'a> {
    /// What is called.
    pub target: Resolution,
    /// Arguments in written order.
    pub arguments: Vec<CallArgument<'a>>,
    /// Instantiated type arguments of a generic callee (None: not inferred).
    pub type_args: Vec<Option<Ty>>,
    /// The call is a use of a constant, not a written call.
    pub constant_use: bool,
}

impl ModuleHir {
    /// All callables declared in the module.
    pub fn callables(&self) -> Vec<Callable> {
        let mut out = Vec::new();
        for d in &self.data.decls {
            match &d.decl().kind {
                DeclKind::Fn(f) => out.push(self.callable(
                    CallableKind::Function,
                    f.name,
                    FuncRef::of_decl(d.clone()),
                )),
                DeclKind::Const(c) => out.push(self.callable(
                    CallableKind::Constant,
                    c.name,
                    FuncRef::of_decl(d.clone()),
                )),
                DeclKind::Test(_) => {
                    out.push(self.callable(CallableKind::Test, n(""), FuncRef::of_decl(d.clone())))
                }
                DeclKind::Impl(i) => {
                    for (index, m) in i.methods.iter().enumerate() {
                        let func = FuncRef {
                            decl: d.clone(),
                            index: Some(index),
                        };
                        out.push(self.callable(CallableKind::Method, m.func.name, func));
                    }
                }
                DeclKind::Record(_) | DeclKind::Alternative(_) | DeclKind::Interface(_) => {}
            }
        }
        out
    }

    fn callable(&self, kind: CallableKind, name: Name, func: FuncRef) -> Callable {
        let facts = self.data.facts();
        let decl = facts.decls.get(&func.id());
        Callable {
            module: self.data.clone(),
            kind,
            name,
            parameters: decl.map(|d| d.parameters.clone()).unwrap_or_default(),
            self_binding: decl.and_then(|d| d.self_binding.clone()),
            fixture: decl.and_then(|d| d.fixture.clone()),
            func,
        }
    }

    /// Checked facts of an expression.
    pub fn info(&self, e: &Expr) -> Info {
        self.data.facts().info(e.id).cloned().unwrap_or_default()
    }

    /// Type of an expression (`<invalid>` when unchecked).
    pub fn ty(&self, e: &Expr) -> Ty {
        self.info(e).t()
    }

    /// What a name or call expression resolves to.
    pub fn resolution(&self, e: &Expr) -> Resolution {
        let info = self.info(e);
        if let Some(b) = info.binding {
            return Resolution::Local(b);
        }
        if let Some(ty) = info.constructor {
            return Resolution::Constructor {
                ty,
                case: info.case,
            };
        }
        if let Some(s) = info.symbol {
            return match s.kind {
                SymKind::Type => Resolution::Type(s),
                SymKind::Fn if s.decl.as_ref().is_some_and(|d| d.is_constant()) => {
                    Resolution::Constant(s)
                }
                SymKind::Fn => Resolution::Function(s),
            };
        }
        if let Some(m) = info.method {
            return Resolution::Method(m);
        }
        match info.native {
            Some(native) => Resolution::Native(native),
            None => Resolution::Value,
        }
    }

    /// The resolved call of a `Call` expression, or of a name standing for a
    /// constant's initializer call.
    pub fn call<'a>(&self, e: &'a Expr) -> Option<CallView<'a>> {
        let constant_use = self.data.facts().const_use.contains(&e.id);
        let args: &[Argument] = match &e.kind {
            ExprKind::Call { args, .. } => args,
            _ if constant_use => &[],
            _ => return None,
        };
        let info = self.info(e);
        let slots = info.arguments.clone().unwrap_or_default();
        let facts = self.data.facts();
        let arguments = args
            .iter()
            .enumerate()
            .map(|(i, a)| CallArgument {
                expr: &a.value,
                slot: slots.get(i).copied().unwrap_or(ArgSlot {
                    pos: a.pos,
                    name: a.name.unwrap_or_else(|| n("")),
                    index: i,
                }),
                wrap_optional: facts
                    .info(a.value.id)
                    .and_then(|i| i.optional_argument.clone()),
            })
            .collect();
        drop(facts);
        Some(CallView {
            target: self.resolution(e),
            arguments,
            type_args: info.type_args,
            constant_use,
        })
    }

    /// Variables a lambda captures (snapshotted at creation).
    pub fn captures(&self, lambda: &Expr) -> Vec<BindingRef> {
        self.info(lambda).captures
    }

    /// Parameter bindings of a lambda.
    pub fn lambda_parameters(&self, lambda: &Expr) -> Vec<BindingRef> {
        self.data
            .facts()
            .lambda_params
            .get(&lambda.id)
            .cloned()
            .unwrap_or_default()
    }

    /// The binding a `let`/`var`/`if let` pattern name introduces.
    pub fn pattern_binding(&self, p: &Pattern) -> Option<BindingRef> {
        self.data.facts().patterns.get(&p.id).cloned()
    }

    /// Facts of a statement (loop or `with` variable, cleanup, flow).
    pub fn stmt(&self, s: &Stmt) -> StmtFacts {
        self.data
            .facts()
            .stmts
            .get(&s.id)
            .cloned()
            .unwrap_or_default()
    }

    /// Payload bindings and contract pattern of a match arm.
    pub fn arm(&self, a: &Arm) -> ArmFacts {
        self.data
            .facts()
            .arms
            .get(&a.id)
            .cloned()
            .unwrap_or_default()
    }

    /// The variable written by an assignment, keyed by its value expression.
    pub fn assigned(&self, value: &Expr) -> Option<BindingRef> {
        self.data.facts().assigned.get(&value.id).cloned()
    }

    /// The resolved type of a written type reference.
    pub fn type_ref(&self, id: NodeId) -> Option<Ty> {
        self.data.facts().type_refs.get(&id).cloned()
    }
}

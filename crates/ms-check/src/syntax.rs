//! Checker-side wrappers around the syntax tree: shared declarations, modules
//! with their fact tables, and per-node facts.

use crate::types::*;
use ms_syntax::ast::*;
use ms_syntax::ast::{Case, Method, Param};
use ms_syntax::{Pos, Span};
use std::cell::{Ref, RefCell, RefMut};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;
use std::sync::Arc;

/// A declaration plus the methods folded into it (bundled standard types write
/// their own methods in `impl Type:` blocks that are folded into the type).
pub struct DeclNode {
    /// The declaration.
    pub decl: Decl,
    /// Methods folded from `impl Type:` blocks of a bundled module.
    pub folded: Vec<Method>,
}

/// A shared declaration.
#[derive(Clone)]
pub struct DeclRef(pub Rc<DeclNode>);

impl DeclRef {
    /// Wraps a declaration.
    pub fn new(decl: Decl) -> DeclRef {
        DeclRef(Rc::new(DeclNode {
            decl,
            folded: Vec::new(),
        }))
    }

    /// The declaration.
    pub fn decl(&self) -> &Decl {
        &self.0.decl
    }

    /// Pointer identity.
    pub fn same(&self, other: &DeclRef) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }

    /// Keyword (or constant-name) position.
    pub fn pos(&self) -> Pos {
        self.0.decl.pos
    }

    /// Node id.
    pub fn id(&self) -> NodeId {
        self.0.decl.id
    }

    /// Whether this is a module-level constant.
    pub fn is_constant(&self) -> bool {
        matches!(self.0.decl.kind, DeclKind::Const(_))
    }

    /// Declared name; empty for `impl` and `test`.
    pub fn name(&self) -> Name {
        match &self.0.decl.kind {
            DeclKind::Fn(f) => f.name,
            DeclKind::Const(c) => c.name,
            DeclKind::Record(r) => r.name,
            DeclKind::Alternative(a) => a.name,
            DeclKind::Interface(i) => i.name,
            DeclKind::Impl(_) | DeclKind::Test(_) => n(""),
        }
    }

    /// Type parameters.
    pub fn type_params(&self) -> &[TypeParam] {
        match &self.0.decl.kind {
            DeclKind::Fn(f) => &f.type_params,
            DeclKind::Record(r) => &r.type_params,
            DeclKind::Alternative(a) => &a.type_params,
            DeclKind::Interface(i) => &i.type_params,
            _ => &[],
        }
    }

    /// Record fields.
    pub fn record_fields(&self) -> &[Param] {
        match &self.0.decl.kind {
            DeclKind::Record(r) => &r.fields,
            _ => &[],
        }
    }

    /// Alternative cases.
    pub fn cases(&self) -> &[Case] {
        match &self.0.decl.kind {
            DeclKind::Alternative(a) => &a.cases,
            _ => &[],
        }
    }

    /// Methods: interface operations, impl methods, or folded type methods.
    pub fn methods(&self) -> &[Method] {
        match &self.0.decl.kind {
            DeclKind::Interface(i) => &i.methods,
            DeclKind::Impl(i) => &i.methods,
            _ => &self.0.folded,
        }
    }

    /// Function parameters.
    pub fn fn_params(&self) -> &[Param] {
        match &self.0.decl.kind {
            DeclKind::Fn(f) => &f.params,
            _ => &[],
        }
    }

    /// The function, if this is a `fn` declaration.
    pub fn func(&self) -> Option<&Func> {
        match &self.0.decl.kind {
            DeclKind::Fn(f) => Some(f),
            _ => None,
        }
    }

    /// The constant, if any.
    pub fn constant(&self) -> Option<&ConstDecl> {
        match &self.0.decl.kind {
            DeclKind::Const(c) => Some(c),
            _ => None,
        }
    }

    /// Finds a method by name.
    pub fn method_named(&self, name: Name) -> Option<FuncRef> {
        self.methods()
            .iter()
            .position(|m| m.func.name == name)
            .map(|i| FuncRef {
                decl: self.clone(),
                index: Some(i),
            })
    }
}

/// A function-like declaration: a `fn`, a constant, a test, or a method.
#[derive(Clone)]
pub struct FuncRef {
    /// Owning declaration.
    pub decl: DeclRef,
    /// Method index within the owner, or `None` for the declaration itself.
    pub index: Option<usize>,
}

impl FuncRef {
    /// The declaration itself.
    pub fn of_decl(decl: DeclRef) -> FuncRef {
        FuncRef { decl, index: None }
    }

    /// The method, if this is one.
    pub fn method(&self) -> Option<&Method> {
        self.index.map(|i| &self.decl.methods()[i])
    }

    /// The `Func`, if this is a function or a method.
    pub fn func(&self) -> Option<&Func> {
        match self.index {
            Some(i) => Some(&self.decl.methods()[i].func),
            None => self.decl.func(),
        }
    }

    /// Name of the function (test and constants: their declared name or empty).
    pub fn name(&self) -> Name {
        match self.func() {
            Some(f) => f.name,
            None => self.decl.name(),
        }
    }

    /// Declaration position (method name position for methods).
    pub fn pos(&self) -> Pos {
        match self.method() {
            Some(m) => m.pos,
            None => self.decl.pos(),
        }
    }

    /// Node id used for declaration facts.
    pub fn id(&self) -> NodeId {
        match self.method() {
            Some(m) => m.id,
            None => self.decl.id(),
        }
    }

    /// Pointer identity.
    pub fn same(&self, other: &FuncRef) -> bool {
        self.decl.same(&other.decl) && self.index == other.index
    }
}

/// Visible environment at a captured editor scope marker.
#[derive(Clone, Default)]
pub struct ScopeState {
    /// Visible local bindings.
    pub bindings: HashMap<Name, BindingRef>,
    /// Visible type variables.
    pub types: HashMap<Name, Ty>,
    /// Visible module symbols.
    pub symbols: HashMap<Name, SymRef>,
}

/// A call argument with its label resolved. `index` refers to the written
/// argument list of the call expression.
#[derive(Clone, Copy, Debug)]
pub struct ArgSlot {
    /// Position of the written argument.
    pub pos: Pos,
    /// Resolved parameter label.
    pub name: Name,
    /// Written position among the call's arguments.
    pub index: usize,
}

/// Checked facts of one expression.
#[derive(Clone, Default)]
pub struct Info {
    /// Type.
    pub ty: Option<Ty>,
    /// Resolved module symbol.
    pub symbol: Option<SymRef>,
    /// Resolved local binding.
    pub binding: Option<BindingRef>,
    /// Constructed type (record, alternative case, contract view).
    pub constructor: Option<Ty>,
    /// Constructed case name.
    pub case: Option<Name>,
    /// Resolved method.
    pub method: Option<MethodRef>,
    /// Native identity ("index", "view", "to_string", ...).
    pub native: Option<Name>,
    /// The expression cannot complete normally.
    pub no_return: bool,
    /// The expression contains a `break`.
    pub breaks: bool,
    /// The expression is an assignment target.
    pub write: bool,
    /// Captured variables of a lambda.
    pub captures: Vec<BindingRef>,
    /// Type arguments of a generic function application.
    pub type_args: Vec<Option<Ty>>,
    /// Concrete type when an Error boundary accepts it.
    pub error_source: Option<Ty>,
    /// Arguments in written order with labels resolved.
    pub arguments: Option<Vec<ArgSlot>>,
    /// Wraps this supplied argument once into this Optional.
    pub optional_argument: Option<Ty>,
    /// Wraps this value once into this Optional where a binding, return, field or element expects it.
    pub wrap_some: Option<Ty>,
    /// A compile-time Bool constant.
    pub folded: bool,
    /// Its value.
    pub constant: bool,
    /// Fold pass bookkeeping.
    pub fold_done: bool,
    /// Body checks need a later callback result context.
    pub inference_deferred: bool,
}

impl Info {
    /// A fresh info with a type.
    pub fn of(ty: Ty) -> Info {
        Info {
            ty: Some(ty),
            ..Info::default()
        }
    }

    /// The type, or `<invalid>` if unset.
    pub fn t(&self) -> Ty {
        self.ty.clone().unwrap_or_else(invalid)
    }

    /// Native identity text.
    pub fn native_str(&self) -> &str {
        self.native.map(|n| n.as_str()).unwrap_or("")
    }
}

/// Statement facts.
#[derive(Clone, Default)]
pub struct StmtFacts {
    /// Loop variable.
    pub loop_binding: Option<BindingRef>,
    /// Cleanup method the binding's scope runs.
    pub cleanup: Option<MethodRef>,
    /// Whether control can fall through.
    pub falls_through: Option<bool>,
    /// A statement whose whole value is a plain `try`.
    pub plain_try: bool,
    /// The statements a `for` over an `Iterator` stands for: every later pass reads these
    /// instead of the loop.
    pub expansion: Option<Rc<Vec<Stmt>>>,
}

/// Match arm facts.
#[derive(Clone, Default)]
pub struct ArmFacts {
    /// Payload variables (None for `_`).
    pub bindings: Vec<Option<BindingRef>>,
    /// Whether bindings were recorded.
    pub has_bindings: bool,
    /// Contract type pattern.
    pub contract: Option<Ty>,
    /// Types or cases the payload names shadow.
    pub conflicts: Vec<Option<Info>>,
}

/// Declaration facts.
#[derive(Clone, Default)]
pub struct DeclFacts {
    /// Parameter variables.
    pub parameters: Vec<BindingRef>,
    /// Receiver variable.
    pub self_binding: Option<BindingRef>,
    /// Implicit test fixture variable.
    pub fixture: Option<BindingRef>,
}

/// All facts of one module, indexed by node id.
#[derive(Default)]
pub struct Facts {
    /// Expression facts.
    pub exprs: Vec<Option<Info>>,
    /// Lambda parameter variables.
    pub lambda_params: HashMap<NodeId, Vec<BindingRef>>,
    /// Variable written when the expression is an assigned value.
    pub assigned: HashMap<NodeId, BindingRef>,
    /// Captured scopes.
    pub scopes: HashMap<NodeId, ScopeState>,
    /// Statement facts.
    pub stmts: HashMap<NodeId, StmtFacts>,
    /// Arm facts.
    pub arms: HashMap<NodeId, ArmFacts>,
    /// Declaration (and method) facts.
    pub decls: HashMap<NodeId, DeclFacts>,
    /// Binding pattern variables.
    pub patterns: HashMap<NodeId, BindingRef>,
    /// The close operation of a parameter or loop variable (by binding), chosen in this module.
    pub cleanups: HashMap<usize, MethodRef>,
    /// Resolved written types.
    pub type_refs: HashMap<NodeId, Ty>,
    /// Name expressions that stand for a constant's initializer call.
    pub const_use: HashSet<NodeId>,
}

impl Facts {
    /// Fact of an expression.
    pub fn info(&self, id: NodeId) -> Option<&Info> {
        self.exprs.get(id.index()).and_then(|i| i.as_ref())
    }
    /// A node id past every parsed or synthetic one, for a node the checker builds.
    pub fn fresh_id(&mut self) -> NodeId {
        self.exprs.push(None);
        NodeId((self.exprs.len() - 1) as u32)
    }
    /// Sets the fact of an expression.
    pub fn set_info(&mut self, id: NodeId, info: Info) {
        let i = id.index();
        if i >= 0x4000_0000 {
            return;
        }
        if i >= self.exprs.len() {
            self.exprs.resize_with(i + 1, || None);
        }
        self.exprs[i] = Some(info);
    }
}

/// A parsed, desugared module with its checker facts.
pub struct ModuleData {
    /// File name.
    pub file: Name,
    /// Original source.
    pub source: Arc<str>,
    /// Import bindings.
    pub imports: Vec<Import>,
    /// Declarations (inherent `impl`s are desugared into synthetic pairs).
    pub decls: Vec<DeclRef>,
    /// Names dropped by editor recovery.
    pub omitted: Vec<String>,
    /// Recovered source ranges.
    pub recovered: Vec<Span>,
    /// Node ids allocated.
    pub node_count: u32,
    /// Misused inherent `impl` blocks found while desugaring.
    pub inherent: Vec<ms_syntax::Diagnostic>,
    facts: RefCell<Facts>,
}

impl ModuleData {
    /// Builds module data from decls.
    pub fn new(m: &Module, decls: Vec<DeclRef>, node_count: u32) -> ModuleData {
        let mut facts = Facts::default();
        facts.exprs.resize_with(node_count as usize, || None);
        ModuleData {
            file: n(&m.file),
            source: m.source.clone(),
            imports: m.imports.clone(),
            decls,
            omitted: m.omitted.clone(),
            recovered: m.recovered.clone(),
            node_count,
            inherent: Vec::new(),
            facts: RefCell::new(facts),
        }
    }

    /// A module with no declarations, standing in for the asking module in
    /// visibility queries.
    pub fn empty(file: Name) -> ModuleData {
        ModuleData {
            file,
            source: Arc::from(""),
            imports: Vec::new(),
            decls: Vec::new(),
            omitted: Vec::new(),
            recovered: Vec::new(),
            node_count: 0,
            inherent: Vec::new(),
            facts: RefCell::new(Facts::default()),
        }
    }

    /// Shared fact access.
    pub fn facts(&self) -> Ref<'_, Facts> {
        self.facts.borrow()
    }

    /// Mutable fact access.
    pub fn facts_mut(&self) -> RefMut<'_, Facts> {
        self.facts.borrow_mut()
    }

    /// Whether a name is in an `@std/` module.
    pub fn is_standard(&self) -> bool {
        self.file.as_str().starts_with("@std/")
    }
}

/// Shared module.
pub type ModRef = Rc<ModuleData>;

/// Span containment helper.
pub fn in_span(offset: u32, s: &Span) -> bool {
    offset >= s.start && offset < s.end
}

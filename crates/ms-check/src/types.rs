//! Checked types, definitions, symbols, bindings and methods.
//!
//! A [`Ty`] is a reference-counted,
//! immutable type value with two exceptions: a type variable's bounds and
//! default are filled in after the variable is created. Those two fields are
//! `RefCell`s; cloning a [`Type`] snapshots them, while cloning the `Rc`
//! shares them.

use crate::syntax::{DeclRef, FuncRef};
pub use ms_syntax::Symbol as Name;
use ms_syntax::ast::DeclKind;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fmt::{self, Write as _};
use std::rc::{Rc, Weak};

/// Interns a string.
pub fn n(text: &str) -> Name {
    ms_syntax::Names::global().intern(text)
}

/// A shared, immutable checked type.
pub type Ty = Rc<Type>;

/// The kind of a type .
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    /// `Int`, `Bool`, ...
    Primitive,
    /// The `<invalid>` marker of an unresolved or erroneous type.
    Invalid,
    /// The `<inferred>` placeholder of a result not yet known.
    Inferred,
    /// A type parameter.
    Variable,
    /// A type (`type T:` with fields).
    Type,
    /// An enum (`enum T:` with cases).
    Alternative,
    /// An interface (contract).
    Contract,
    /// A function type.
    Function,
    /// An opaque runtime-implemented type.
    Native,
}

impl Kind {
    /// The source spelling.
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Primitive => "primitive",
            Kind::Invalid => "invalid",
            Kind::Inferred => "inferred",
            Kind::Variable => "variable",
            Kind::Type => "type",
            Kind::Alternative => "alternative",
            Kind::Contract => "contract",
            Kind::Function => "function",
            Kind::Native => "native",
        }
    }
}

/// A named parameter, field or payload slot.
#[derive(Clone, Debug)]
pub struct Param {
    /// Label.
    pub name: Name,
    /// Type.
    pub ty: Ty,
    /// A `var` parameter: the callee changes the caller's variable in place, so a call marks the
    /// argument `var`. Part of a function type's identity (`fn(var List[Int]) Unit`); never set
    /// on a field.
    pub mutable: bool,
    /// The parameter of a written function type (`fn(Int) Int`), which has no source label: calls
    /// pass it positionally and the parser's `_0`, `_1` names are internal.
    pub positional: bool,
}

impl Param {
    /// A parameter or field passed by value.
    pub fn new(name: Name, ty: Ty) -> Param {
        Param {
            name,
            ty,
            mutable: false,
            positional: false,
        }
    }
}

/// Omission permissions and the native default that needs an invocation position.
#[derive(Clone, Debug)]
pub struct ParameterDefaults {
    names: HashSet<Name>,
    missing_value_at_call: Option<Name>,
}

impl ParameterDefaults {
    /// Ordinary declaration defaults, without a native invocation default.
    pub fn new(names: HashSet<Name>) -> Self {
        Self {
            names,
            missing_value_at_call: None,
        }
    }

    /// Whether this parameter may be omitted.
    pub fn contains(&self, name: &Name) -> bool {
        self.names.contains(name)
    }

    /// Omittable parameter names.
    pub fn iter(&self) -> impl Iterator<Item = &Name> {
        self.names.iter()
    }

    /// The number of omittable parameters.
    pub fn len(&self) -> usize {
        self.names.len()
    }

    /// Whether every parameter is required.
    pub fn is_empty(&self) -> bool {
        self.names.is_empty()
    }

    /// The already-omittable native parameter whose missing-value `Error` is made at the call.
    pub fn missing_value_at_call(&self) -> Option<Name> {
        self.missing_value_at_call
    }

    pub(crate) fn with_missing_value_at_call(&self, name: Name) -> Self {
        let mut defaults = self.clone();
        if defaults.contains(&name) {
            defaults.missing_value_at_call = Some(name);
        }
        defaults
    }
}

/// Parameters flagged as omittable on a known callable; erasure removes all default metadata.
pub type Defaults = Option<Rc<ParameterDefaults>>;

/// Field of an extern error case that receives the native status detail (`int64_t *code_out`).
/// The checker and lowering both read the native error shape from these two names.
pub const EXTERN_ERROR_CODE: &str = "code";
/// Field of an extern error case that receives the native message (`ms_str *message_out`).
pub const EXTERN_ERROR_MESSAGE: &str = "message";

/// Identity of a built-in standard type, fixed when the type is built so checks compare a tag
/// instead of the id text.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Builtin {
    /// `Optional`.
    Optional,
    /// `Result`.
    Result,
    /// `List`.
    List,
    /// `Map`.
    Map,
    /// `Set`.
    Set,
    /// `Bytes`.
    Bytes,
    /// `BigInt`.
    BigInt,
    /// `Decimal`.
    Decimal,
    /// `Error`.
    Error,
    /// `Closeable`.
    Closeable,
    /// `Hashable`.
    Hashable,
    /// `Comparable`.
    Comparable,
    /// `Equal`.
    Equal,
    /// `Data`.
    Data,
    /// `Clonable`.
    Clonable,
    /// `Iterator`.
    Iterator,
    /// `Iterable`.
    Iterable,
    /// `BytesBuilder`.
    BytesBuilder,
    /// `Regex`.
    Regex,
    /// A closed set of types, `type Name = A | B`; its members are the type arguments. Only a
    /// bound can name one.
    TypeSet,
    /// The implicit `Self` variable of an interface.
    SelfType,
    /// `Int`.
    Int,
    /// `Int8`.
    Int8,
    /// `Int16`.
    Int16,
    /// `Int32`.
    Int32,
    /// `Int64`.
    Int64,
    /// `UInt8`.
    UInt8,
    /// `UInt16`.
    UInt16,
    /// `UInt32`.
    UInt32,
    /// `UInt64`.
    UInt64,
    /// `Float`.
    Float,
    /// `Float32`.
    Float32,
    /// `Float64`.
    Float64,
    /// `Bool`.
    Bool,
    /// `String`.
    String,
    /// `Unit`.
    Unit,
    /// `Never`.
    Never,
    /// `Timestamp`.
    Timestamp,
    /// `Instant`.
    Instant,
    /// `Duration`.
    Duration,
}

impl Builtin {
    /// The primitive type spelled `name`, if any.
    pub fn primitive(name: &str) -> Option<Builtin> {
        match name {
            "Int" => Some(Builtin::Int),
            "Int8" => Some(Builtin::Int8),
            "Int16" => Some(Builtin::Int16),
            "Int32" => Some(Builtin::Int32),
            "Int64" => Some(Builtin::Int64),
            "UInt8" => Some(Builtin::UInt8),
            "UInt16" => Some(Builtin::UInt16),
            "UInt32" => Some(Builtin::UInt32),
            "UInt64" => Some(Builtin::UInt64),
            "Float" => Some(Builtin::Float),
            "Float32" => Some(Builtin::Float32),
            "Float64" => Some(Builtin::Float64),
            "Bool" => Some(Builtin::Bool),
            "String" => Some(Builtin::String),
            "Unit" => Some(Builtin::Unit),
            "Never" => Some(Builtin::Never),
            _ => None,
        }
    }

    /// A type declared by a bundled source module that the compiler gives a native layout.
    pub fn source(module: &str, name: &str) -> Option<Builtin> {
        match (module, name) {
            ("@std/time.ms", "Timestamp") => Some(Builtin::Timestamp),
            ("@std/time.ms", "Instant") => Some(Builtin::Instant),
            ("@std/time.ms", "Duration") => Some(Builtin::Duration),
            _ => None,
        }
    }

    /// Whether this is a primitive integer type.
    pub fn is_int(self) -> bool {
        matches!(
            self,
            Builtin::Int
                | Builtin::Int8
                | Builtin::Int16
                | Builtin::Int32
                | Builtin::Int64
                | Builtin::UInt8
                | Builtin::UInt16
                | Builtin::UInt32
                | Builtin::UInt64
        )
    }

    /// Whether this is a primitive float type.
    pub fn is_float(self) -> bool {
        matches!(self, Builtin::Float | Builtin::Float32 | Builtin::Float64)
    }

    /// The built-in named by a type id (`@std/<name>`), if any.
    pub fn from_id(id: &str) -> Option<Builtin> {
        match id.strip_prefix("@std/")? {
            "Optional" => Some(Builtin::Optional),
            "Result" => Some(Builtin::Result),
            "List" => Some(Builtin::List),
            "Map" => Some(Builtin::Map),
            "Set" => Some(Builtin::Set),
            "Bytes" => Some(Builtin::Bytes),
            "BigInt" => Some(Builtin::BigInt),
            "Decimal" => Some(Builtin::Decimal),
            "Error" => Some(Builtin::Error),
            "Closeable" => Some(Builtin::Closeable),
            "Hashable" => Some(Builtin::Hashable),
            "Comparable" => Some(Builtin::Comparable),
            "Equal" => Some(Builtin::Equal),
            "Data" => Some(Builtin::Data),
            "Clonable" => Some(Builtin::Clonable),
            "Iterator" => Some(Builtin::Iterator),
            "Iterable" => Some(Builtin::Iterable),
            "BytesBuilder" => Some(Builtin::BytesBuilder),
            "Regex" => Some(Builtin::Regex),
            _ => None,
        }
    }
}

/// A checked type.
pub struct Type {
    /// Display name.
    pub name: Name,
    /// Identity: two types are the same only if their ids match structurally.
    pub id: Name,
    /// Kind.
    pub kind: Kind,
    /// Type arguments (a declaration's own type has its variables here).
    pub args: Vec<Ty>,
    /// Function parameters.
    pub params: Vec<Param>,
    /// Function result.
    pub result: Option<Ty>,
    /// Nominal definition.
    pub def: Option<Rc<Definition>>,
    /// Bounds of a type variable (shared by pointer, snapshotted by clone).
    pub bounds: RefCell<Vec<Ty>>,
    /// Default argument of a type variable.
    pub default: RefCell<Option<Ty>>,
    /// Omittable parameters of a known source callable.
    pub defaults: Defaults,
    /// The built-in standard type this is, if any.
    pub builtin: Option<Builtin>,
}

impl Clone for Type {
    fn clone(&self) -> Type {
        Type {
            name: self.name,
            id: self.id,
            kind: self.kind,
            args: self.args.clone(),
            params: self.params.clone(),
            result: self.result.clone(),
            def: self.def.clone(),
            bounds: RefCell::new(self.bounds.borrow().clone()),
            default: RefCell::new(self.default.borrow().clone()),
            defaults: self.defaults.clone(),
            builtin: self.builtin,
        }
    }
}

impl fmt::Debug for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Type({:?}, {} args)", self.id, self.args.len())
    }
}

/// A type paired with the handle that reads its names, so it can be formatted.
pub struct TypeDisplay<'a> {
    ty: &'a Type,
    syms: ms_syntax::Names,
}

impl Type {
    /// A value that formats this type with `syms`.
    pub fn display(&self, syms: ms_syntax::Names) -> TypeDisplay<'_> {
        TypeDisplay { ty: self, syms }
    }
}

/// The most type nodes one rendered type shows. A shared type graph can expand to an
/// exponentially larger tree, so a deeper or wider remainder prints as `…`.
const DISPLAY_NODE_BUDGET: usize = 64;

impl fmt::Display for TypeDisplay<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.ty.write_to(self.syms, f, &mut { DISPLAY_NODE_BUDGET })
    }
}

impl Type {
    fn write_to(
        &self,
        syms: ms_syntax::Names,
        f: &mut fmt::Formatter<'_>,
        budget: &mut usize,
    ) -> fmt::Result {
        if *budget == 0 {
            return f.write_char('…');
        }
        *budget -= 1;
        if self.kind == Kind::Function {
            f.write_str("fn(")?;
            for (i, a) in self.params.iter().enumerate() {
                if i > 0 {
                    f.write_str(", ")?;
                }
                if a.mutable {
                    f.write_str("var ")?;
                }
                a.ty.write_to(syms, f, budget)?;
            }
            f.write_str(") ")?;
            return match &self.result {
                Some(r) => r.write_to(syms, f, budget),
                None => f.write_str("<unknown>"),
            };
        }
        if self.is(Builtin::Optional) && self.args.len() == 1 {
            let inner = &self.args[0];
            return if inner.kind == Kind::Function {
                f.write_char('(')?;
                inner.write_to(syms, f, budget)?;
                f.write_str(")?")
            } else {
                inner.write_to(syms, f, budget)?;
                f.write_char('?')
            };
        }
        f.write_str(syms.str(self.name))?;
        if !self.args.is_empty() {
            f.write_char('[')?;
            for (i, a) in self.args.iter().enumerate() {
                if i > 0 {
                    f.write_str(", ")?;
                }
                a.write_to(syms, f, budget)?;
            }
            f.write_char(']')?;
        }
        Ok(())
    }
}

/// Formats an optional type; `None` prints as `<unknown>`.
pub fn show(syms: ms_syntax::Names, t: &Option<Ty>) -> String {
    match t {
        Some(t) => t.display(syms).to_string(),
        None => "<unknown>".to_string(),
    }
}

impl Type {
    /// A bare type of one kind.
    pub fn new(syms: ms_syntax::Names, name: Name, id: Name, kind: Kind) -> Type {
        let builtin = if kind == Kind::Primitive {
            Builtin::primitive(syms.str(id))
        } else {
            Builtin::from_id(syms.str(id))
        };
        Type::with_builtin(name, id, kind, builtin)
    }

    /// A bare type of one kind whose built-in identity is already known.
    pub fn with_builtin(name: Name, id: Name, kind: Kind, builtin: Option<Builtin>) -> Type {
        Type {
            name,
            id,
            kind,
            args: Vec::new(),
            params: Vec::new(),
            result: None,
            def: None,
            bounds: RefCell::new(Vec::new()),
            default: RefCell::new(None),
            defaults: None,
            builtin,
        }
    }

    /// Whether `name` is an omittable parameter.
    pub fn is_default(&self, name: Name) -> bool {
        self.defaults.as_ref().is_some_and(|d| d.contains(&name))
    }

    /// Whether a default-aware function value passes `name` as an optional.
    pub fn is_lifted(&self, name: Name) -> bool {
        self.is_default(name)
    }

    /// The result of a function type (panics if absent: function types always have one).
    pub fn result_ty(&self) -> Ty {
        self.result.clone().unwrap_or_else(invalid)
    }

    /// The type variable's bounds (snapshot).
    pub fn bounds(&self) -> Vec<Ty> {
        self.bounds.borrow().clone()
    }

    /// The variable's default.
    pub fn default_ty(&self) -> Option<Ty> {
        self.default.borrow().clone()
    }

    /// The `<invalid>` marker.
    pub fn is_invalid(&self) -> bool {
        self.kind == Kind::Invalid
    }

    /// The `Never` primitive.
    pub fn is_never(&self) -> bool {
        self.kind == Kind::Primitive && self.is(Builtin::Never)
    }

    /// The `String` primitive.
    pub fn is_string(&self) -> bool {
        self.kind == Kind::Primitive && self.is(Builtin::String)
    }

    /// Standard type test: id is `@std/<name>`.
    pub fn is_std(&self, syms: ms_syntax::Names, name: &str) -> bool {
        let id = syms.str(self.id);
        id.len() == 5 + name.len() && id.starts_with("@std/") && &id[5..] == name
    }

    /// Whether this is the built-in standard type `b`.
    pub fn is(&self, b: Builtin) -> bool {
        self.builtin == Some(b)
    }

    /// Whether this is `TestHooks` of `@std/test/test.ms`.
    pub fn is_test_hooks(&self, syms: ms_syntax::Names) -> bool {
        self.is_source_type(syms, "@std/test/test.ms", "TestHooks")
    }

    /// Whether this is the type `name` declared by the bundled source module `module`.
    pub fn is_source_type(&self, syms: ms_syntax::Names, module: &str, name: &str) -> bool {
        syms.str(self.name) == name && self.symbol().is_some_and(|s| syms.str(s.module) == module)
    }

    /// The nominal definition's symbol, if any.
    pub fn symbol(&self) -> Option<SymRef> {
        self.def.as_ref().and_then(|d| d.symbol())
    }

    /// The declaring file of an `opaque type`, or `None` for any other type.
    pub fn opaque_module(&self) -> Option<Name> {
        let symbol = self.symbol()?;
        let opaque = match &symbol.decl.as_ref()?.decl().kind {
            DeclKind::Type(r) => r.opaque,
            DeclKind::Alternative(a) => a.opaque,
            _ => false,
        };
        opaque.then_some(symbol.module)
    }
}

/// A named type slot of a case.
#[derive(Clone, Debug)]
pub struct Case {
    /// Case name.
    pub name: Name,
    /// Payload fields.
    pub fields: Vec<Param>,
}

/// A receiver or contract operation's signature and source identity.
#[derive(Clone)]
pub struct Operation {
    /// Operation name.
    pub name: Name,
    /// Signature.
    pub ty: Ty,
    /// Declaration.
    pub decl: Option<FuncRef>,
}

/// Whether interface `t` declares a `var fn` operation: a call through it may change the
/// value, so a converted value cannot stay a view of borrowed storage.
pub fn contract_mutates(t: &Ty) -> bool {
    let Some(def) = &t.def else {
        return false;
    };
    let mutating = |op: &Operation| {
        let f = op.decl.as_ref()?;
        Some(f.decl.methods().get(f.index?)?.mutating)
    };
    def.operations
        .borrow()
        .iter()
        .any(|op| mutating(op).unwrap_or(false))
}

/// A nominal type definition.
pub struct Definition {
    symbol: RefCell<Weak<Sym>>,
    // Signature resolution preserves these immutable source field positions.
    field_indices: HashMap<Name, usize>,
    /// Definition kind (type, alternative, contract, native).
    pub kind: Kind,
    /// Declared type variables.
    pub variables: RefCell<Vec<Ty>>,
    /// Type fields.
    pub fields: RefCell<Vec<Param>>,
    /// Alternative cases.
    pub cases: RefCell<Vec<Case>>,
    /// Position in [`Definition::cases`] of each case name (the first on a duplicate), so finding a
    /// case does not scan an enum with thousands of them once per match arm.
    case_indices: RefCell<HashMap<Name, usize>>,
    /// Contract or native operations.
    pub operations: RefCell<Vec<Operation>>,
}

impl Definition {
    /// A new definition owned by `symbol`.
    pub fn new(symbol: &SymRef, kind: Kind) -> Rc<Definition> {
        let mut field_indices = HashMap::new();
        if let Some(decl) = &symbol.decl {
            for (index, field) in decl.type_fields().iter().enumerate() {
                // Invalid duplicate declarations still resolve to the first field.
                field_indices.entry(field.name).or_insert(index);
            }
        }
        Rc::new(Definition {
            symbol: RefCell::new(Rc::downgrade(symbol)),
            field_indices,
            kind,
            variables: RefCell::new(Vec::new()),
            fields: RefCell::new(Vec::new()),
            cases: RefCell::new(Vec::new()),
            case_indices: RefCell::new(HashMap::new()),
            operations: RefCell::new(Vec::new()),
        })
    }

    /// Drops every case, so a signature pass that runs again over the same declaration replaces
    /// the cases instead of appending a second copy.
    pub fn clear_cases(&self) {
        self.cases.borrow_mut().clear();
        self.case_indices.borrow_mut().clear();
    }

    /// Appends a case; add cases only through this so the name index stays in step.
    pub fn push_case(&self, case: Case) {
        let mut cases = self.cases.borrow_mut();
        self.case_indices
            .borrow_mut()
            .entry(case.name)
            .or_insert(cases.len());
        cases.push(case);
    }

    /// The owning symbol.
    pub fn symbol(&self) -> Option<SymRef> {
        self.symbol.borrow().upgrade()
    }

    /// Declared variables (snapshot of the list of pointers).
    pub fn variables(&self) -> Vec<Ty> {
        self.variables.borrow().clone()
    }

    /// Number of declared variables.
    pub fn arity(&self) -> usize {
        self.variables.borrow().len()
    }
}

/// Whether a module-level symbol is a type or a function.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum SymKind {
    /// A type (named type, alternative, interface or primitive).
    Type,
    /// A function (including constants and native functions).
    Fn,
    /// `type Name = Type`: its `ty` is the aliased type over the alias's own variables.
    Alias,
}

/// What a declaration binds to: a source body, a contract operation, or a bodiless native.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub enum Native {
    /// A source body.
    #[default]
    Source,
    /// An interface operation, dispatched through the receiver's implementation.
    Contract,
    /// An `extern fn`: a runtime symbol. A bundled one follows the runtime table's convention;
    /// a user one follows the shim ABI.
    Extern {
        /// The symbol the declaration is named after.
        symbol: Name,
        /// Declared by an embedded standard module.
        bundled: bool,
    },
    /// A bodiless standard declaration lowered by the compiler: `module/name` for a function,
    /// the method name for a receiver method, the type name for a native type.
    Builtin(Name),
}

impl Native {
    /// Whether the declaration has no body of its own (an extern or a builtin).
    pub fn is_bodiless(self) -> bool {
        matches!(self, Native::Extern { .. } | Native::Builtin(_))
    }

    /// The builtin identity, if any.
    pub fn builtin(self) -> Option<Name> {
        match self {
            Native::Builtin(name) => Some(name),
            _ => None,
        }
    }

    /// Whether this is the builtin identity spelled `text`.
    pub fn is(self, syms: ms_syntax::Names, text: &str) -> bool {
        self.builtin().is_some_and(|b| syms.str(b) == text)
    }

    /// The builtin identity's text, or "" when the declaration is not a builtin.
    pub fn text(self, syms: ms_syntax::Names) -> &'static str {
        self.builtin().map_or("", |b| syms.str(b))
    }
}

/// A module-level symbol.
pub struct Sym {
    /// Name.
    pub name: Name,
    /// Unique id.
    pub id: Name,
    /// Kind.
    pub kind: SymKind,
    /// Declaring module file.
    pub module: Name,
    /// What the symbol binds to.
    pub native: Native,
    /// Exported.
    pub export: bool,
    /// Type (function type for functions, the nominal type for types).
    pub ty: RefCell<Option<Ty>>,
    /// Declared type variables.
    pub variables: RefCell<Vec<Ty>>,
    /// Declaration.
    pub decl: Option<DeclRef>,
}

/// A shared symbol.
pub type SymRef = Rc<Sym>;

impl Sym {
    /// The symbol's type (panics if not yet resolved).
    pub fn ty(&self, syms: ms_syntax::Names) -> Ty {
        self.ty.borrow().clone().unwrap_or_else(|| {
            panic!(
                "symbol type resolved: {} in {}",
                syms.str(self.name),
                syms.str(self.module)
            )
        })
    }

    /// The symbol's type if resolved.
    pub fn ty_opt(&self) -> Option<Ty> {
        self.ty.borrow().clone()
    }

    /// Declared variables.
    pub fn variables(&self) -> Vec<Ty> {
        self.variables.borrow().clone()
    }

    /// Whether this is `caller_site` of `@std/test/test.ms`, the default that names the
    /// position of the call that omitted it.
    pub fn is_caller_site(&self, syms: ms_syntax::Names) -> bool {
        self.kind == SymKind::Fn
            && syms.str(self.name) == "caller_site"
            && syms.str(self.module) == "@std/test/test.ms"
    }

    /// Whether this is a module-level `let` constant.
    pub fn is_constant(&self) -> bool {
        self.kind == SymKind::Fn && self.decl.as_ref().is_some_and(|d| d.is_constant())
    }

    /// The type a name of the symbol has as an expression.
    pub fn value_type(&self) -> Option<Ty> {
        let t = self.ty_opt()?;
        if self.is_constant()
            && let Some(r) = &t.result
        {
            return Some(r.clone());
        }
        Some(t)
    }

    /// Stable key for hash maps.
    pub fn key(self: &Rc<Sym>) -> usize {
        Rc::as_ptr(self) as usize
    }
}

/// A local variable, parameter or pattern binding.
pub struct Binding {
    /// Source name.
    pub name: Name,
    /// Unique id.
    pub id: Name,
    /// Process-unique numeric identity.
    pub uid: usize,
    /// Type.
    pub ty: Ty,
    /// Declared with `var`.
    pub mutable: bool,
    /// Where the name is declared.
    pub decl: ms_syntax::Pos,
    /// Function (closure) nesting number that owns it.
    pub function: usize,
}

/// A shared binding.
pub type BindingRef = Rc<Binding>;

/// A method: an implementation operation, a contract operation or a native operation.
pub struct Method {
    /// Unique id (empty for contract and native views).
    pub id: Name,
    /// Declaring module file.
    pub module: Name,
    /// An extension implemented outside the receiver's defining module.
    pub local: bool,
    /// Receiver type.
    pub receiver: Ty,
    /// Implemented contract.
    pub contract: Option<Ty>,
    /// Signature.
    pub ty: Ty,
    /// Implementation variables.
    pub variables: Vec<Ty>,
    /// Declaration.
    pub decl: Option<FuncRef>,
    /// What the method binds to.
    pub native: Native,
}

/// A shared method.
pub type MethodRef = Rc<Method>;

impl Method {
    /// Extensions stay in their declaring module; implementations owned by the
    /// receiver's defining module are available wherever the type is used.
    pub fn visible_in(&self, module: Name) -> bool {
        !self.local || self.module == module
    }

    /// Whether the method is a type's own (`fn Type.name`, `impl Type:`), declared through the
    /// type's synthesized inherent interface instead of a written one.
    pub fn is_inherent(&self, syms: ms_syntax::Names) -> bool {
        self.contract
            .as_ref()
            .is_some_and(|c| syms.str(c.name).ends_with(crate::passes::INHERENT_SUFFIX))
    }

    /// Whether the method releases its receiver: a `Closeable` implementation, or a type's own
    /// `fn var Type.close() Unit!`, which satisfies `Closeable` by shape.
    pub fn closes(&self, syms: ms_syntax::Names) -> bool {
        if self
            .contract
            .as_ref()
            .is_some_and(|c| c.is(Builtin::Closeable))
        {
            return true;
        }
        self.is_inherent(syms)
            && self.name().is_some_and(|n| syms.str(n) == "close")
            && self.ty.params.is_empty()
            && is_close_result(syms, &self.ty.result_ty())
    }

    /// Whether the method is a type's own `equals(other: Self) Bool` or `hash() Int`, which
    /// decides the matching property by shape without an `impl Equal` or `impl Hashable`.
    pub fn overrides(&self, syms: ms_syntax::Names, property: Builtin) -> bool {
        if !self.is_inherent(syms) {
            return false;
        }
        let Some(name) = self.name().map(|n| syms.str(n)) else {
            return false;
        };
        match (property, name) {
            (Builtin::Equal, "equals") => {
                self.ty.params.len() == 1
                    && self.ty.params[0].ty.id == self.receiver.id
                    && self.ty.result_ty().is(Builtin::Bool)
            }
            (Builtin::Hashable, "hash") => {
                self.ty.params.is_empty() && self.ty.result_ty().is(Builtin::Int)
            }
            _ => false,
        }
    }

    /// The operation name.
    pub fn name(&self) -> Option<Name> {
        self.decl.as_ref().map(|d| d.name())
    }

    /// The variables declared by the implementation and fixed by its receiver, and the type
    /// parameters the method declares for itself (the trailing variables).
    pub fn split_variables(&self) -> (&[Ty], &[Ty]) {
        let own = self
            .decl
            .as_ref()
            .and_then(|d| d.func())
            .map_or(0, |f| f.type_params.len())
            .min(self.variables.len());
        self.variables.split_at(self.variables.len() - own)
    }
}

impl Clone for Method {
    fn clone(&self) -> Method {
        Method {
            id: self.id,
            module: self.module,
            local: self.local,
            receiver: self.receiver.clone(),
            contract: self.contract.clone(),
            ty: self.ty.clone(),
            variables: self.variables.clone(),
            decl: self.decl.clone(),
            native: self.native,
        }
    }
}

// ----------------------------------------------------------------- builders

thread_local! {
    /// The primitives of the interner they were made for, rebuilt when the current one changes.
    static PRIMS: RefCell<Option<(u64, Rc<Prims>)>> = const { RefCell::new(None) };
}

fn with_prims<R>(f: impl FnOnce(&Prims) -> R) -> R {
    let generation = ms_syntax::Names::global().generation();
    let prims = PRIMS.with(|cell| {
        let mut cell = cell.borrow_mut();
        match &*cell {
            Some((g, prims)) if *g == generation => prims.clone(),
            _ => {
                let prims = Rc::new(Prims::new());
                *cell = Some((generation, prims.clone()));
                prims
            }
        }
    });
    f(&prims)
}

struct Prims {
    int: Ty,
    float: Ty,
    bool_: Ty,
    string: Ty,
    unit: Ty,
    never: Ty,
    invalid: Ty,
    inferred: Ty,
}

impl Prims {
    fn new() -> Prims {
        let p = |s: &str| {
            Rc::new(Type::with_builtin(
                n(s),
                n(s),
                Kind::Primitive,
                Builtin::primitive(s),
            ))
        };
        Prims {
            int: p("Int"),
            float: p("Float"),
            bool_: p("Bool"),
            string: p("String"),
            unit: p("Unit"),
            never: p("Never"),
            invalid: Rc::new(Type::with_builtin(
                n("<invalid>"),
                n("<invalid>"),
                Kind::Invalid,
                None,
            )),
            inferred: Rc::new(Type::with_builtin(
                n("<inferred>"),
                n("<inferred>"),
                Kind::Inferred,
                None,
            )),
        }
    }
}

/// A primitive type by name.
pub fn primitive(name: &str) -> Ty {
    with_prims(|p| match name {
        "Int" => p.int.clone(),
        "Float" => p.float.clone(),
        "Bool" => p.bool_.clone(),
        "String" => p.string.clone(),
        "Unit" => p.unit.clone(),
        "Never" => p.never.clone(),
        other => Rc::new(Type::with_builtin(
            n(other),
            n(other),
            Kind::Primitive,
            Builtin::primitive(other),
        )),
    })
}

/// `Int`.
pub fn int() -> Ty {
    primitive("Int")
}

/// Bit width of `Int`; `Int64` or `Int32` is the same type as `Int` when it matches.
pub const DEFAULT_INT_BITS: u32 = 64;
/// Bit width of `Float`; `Float64` or `Float32` is the same type as `Float` when it matches.
pub const DEFAULT_FLOAT_BITS: u32 = 64;

/// The type identity a built-in type name denotes: the default-width names
/// `Int64` and `Float64` are aliases of `Int` and `Float`.
pub fn primitive_id(name: &'static str) -> &'static str {
    match name {
        "Int64" if DEFAULT_INT_BITS == 64 => "Int",
        "Int32" if DEFAULT_INT_BITS == 32 => "Int",
        "Float64" if DEFAULT_FLOAT_BITS == 64 => "Float",
        "Float32" if DEFAULT_FLOAT_BITS == 32 => "Float",
        other => other,
    }
}

/// Bit width of an integer type, or none for any other type.
pub fn int_bits(t: &Type) -> Option<u32> {
    match t.builtin? {
        Builtin::Int => Some(DEFAULT_INT_BITS),
        Builtin::Int8 | Builtin::UInt8 => Some(8),
        Builtin::Int16 | Builtin::UInt16 => Some(16),
        Builtin::Int32 | Builtin::UInt32 => Some(32),
        Builtin::Int64 | Builtin::UInt64 => Some(64),
        _ => None,
    }
}

/// Whether `t` is an unsigned integer type.
pub fn int_unsigned(t: &Type) -> bool {
    matches!(
        t.builtin,
        Some(Builtin::UInt8 | Builtin::UInt16 | Builtin::UInt32 | Builtin::UInt64)
    )
}

/// The inclusive range of values an integer type holds, or none for any other type.
pub fn int_range(t: &Type) -> Option<(i128, i128)> {
    let bits = int_bits(t)?;
    Some(if int_unsigned(t) {
        (0, (1i128 << bits) - 1)
    } else {
        (-(1i128 << (bits - 1)), (1i128 << (bits - 1)) - 1)
    })
}

/// Bit width of a floating-point type, or none for any other type.
pub fn float_bits(t: &Type) -> Option<u32> {
    match t.builtin? {
        Builtin::Float => Some(DEFAULT_FLOAT_BITS),
        Builtin::Float32 => Some(32),
        Builtin::Float64 => Some(64),
        _ => None,
    }
}
/// `Bool`.
pub fn bool_() -> Ty {
    primitive("Bool")
}
/// `String`.
pub fn string() -> Ty {
    primitive("String")
}
/// `Unit`.
pub fn unit() -> Ty {
    primitive("Unit")
}
/// `Never`.
pub fn never() -> Ty {
    primitive("Never")
}
/// The `<invalid>` marker type.
pub fn invalid() -> Ty {
    with_prims(|p| p.invalid.clone())
}
/// The `<inferred>` placeholder type.
pub fn inferred() -> Ty {
    with_prims(|p| p.inferred.clone())
}

/// A function type.
pub fn function(syms: ms_syntax::Names, params: Vec<Param>, result: Ty) -> Ty {
    let mut t = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    t.params = params;
    t.result = Some(result);
    Rc::new(t)
}

/// A function type with omittable parameters.
pub fn function_with(
    syms: ms_syntax::Names,
    params: Vec<Param>,
    result: Ty,
    defaults: Defaults,
) -> Ty {
    let mut t = Type::new(syms, n("fn"), n("fn"), Kind::Function);
    t.params = params;
    t.result = Some(result);
    t.defaults = defaults;
    Rc::new(t)
}

/// A copy of `t` with new type arguments.
pub fn with_args(t: &Ty, args: Vec<Ty>) -> Ty {
    let mut r = (**t).clone();
    r.args = args;
    Rc::new(r)
}

/// Whether `t` is `Result[Unit, Error]`, the result of every `close`.
pub fn is_close_result(syms: ms_syntax::Names, t: &Ty) -> bool {
    t.is(Builtin::Result)
        && t.args.len() == 2
        && syms.str(t.args[0].id) == "Unit"
        && t.args[1].is(Builtin::Error)
}

// ------------------------------------------------------------ type algebra

/// Substitution of type variables by id.
pub type Subst = HashMap<Name, Ty>;

/// Structural identity.
pub fn same(a: &Ty, b: &Ty) -> bool {
    if Rc::ptr_eq(a, b) && a.args.is_empty() && a.params.is_empty() {
        return true;
    }
    struct Comparison {
        remaining: u8,
        equal: Option<HashSet<(*const Type, *const Type)>>,
    }
    fn compare(a: &Ty, b: &Ty, context: &mut Comparison) -> bool {
        if Rc::ptr_eq(a, b) && a.args.is_empty() && a.params.is_empty() {
            return true;
        }
        if a.id != b.id
            || a.kind != b.kind
            || a.args.len() != b.args.len()
            || a.params.len() != b.params.len()
        {
            return false;
        }
        if a.kind != Kind::Function && a.args.is_empty() {
            return true;
        }
        // Reuse only completed successes, and only after a bounded amount of
        // ordinary work. Active comparisons and missing results prove nothing.
        let key = (Rc::as_ptr(a), Rc::as_ptr(b));
        if context.remaining > 0 {
            context.remaining -= 1;
        } else if context
            .equal
            .as_ref()
            .is_some_and(|equal| equal.contains(&key))
        {
            return true;
        }
        for (x, y) in a.args.iter().zip(&b.args) {
            if !compare(x, y, context) {
                return false;
            }
        }
        if a.kind == Kind::Function {
            for (p, q) in a.params.iter().zip(&b.params) {
                if p.mutable != q.mutable || !compare(&p.ty, &q.ty, context) {
                    return false;
                }
            }
            let same_result = match (&a.result, &b.result) {
                (Some(x), Some(y)) => compare(x, y, context),
                _ => false,
            };
            if !same_result {
                return false;
            }
        }
        if context.remaining == 0 {
            context.equal.get_or_insert_with(HashSet::new).insert(key);
        }
        true
    }

    compare(
        a,
        b,
        &mut Comparison {
            remaining: 64,
            equal: None,
        },
    )
}

/// `Same` over optional types: nil is never the same as anything.
pub fn same_opt(a: &Option<Ty>, b: &Option<Ty>) -> bool {
    match (a, b) {
        (Some(a), Some(b)) => same(a, b),
        _ => false,
    }
}

/// `compatible`: the actual type is `Never` or the same as expected.
pub fn compatible(actual: &Option<Ty>, expected: &Ty) -> bool {
    match actual {
        Some(a) => a.is_never() || same(a, expected),
        None => false,
    }
}

/// Whether `actual` is `expected` except that it reads some parameters `expected` may change:
/// a function that takes `x` stands in where one that takes `var x` is expected, never the other
/// way round.
pub fn reads_where_var_expected(actual: &Ty, expected: &Ty) -> bool {
    actual.kind == Kind::Function
        && expected.kind == Kind::Function
        && actual.params.len() == expected.params.len()
        && actual
            .params
            .iter()
            .zip(&expected.params)
            .any(|(a, e)| !a.mutable && e.mutable)
        && actual
            .params
            .iter()
            .zip(&expected.params)
            .all(|(a, e)| (a.mutable == e.mutable || e.mutable) && same(&a.ty, &e.ty))
        && match (&actual.result, &expected.result) {
            (Some(a), Some(e)) => same(a, e),
            _ => false,
        }
}

/// Substitutes type variables.
pub fn sub(t: &Ty, bindings: &Subst) -> Ty {
    sub_walk(t, bindings)
}

fn sub_walk(t: &Ty, bindings: &Subst) -> Ty {
    if let Some(v) = bindings.get(&t.id) {
        return v.clone();
    }
    if t.kind == Kind::Variable {
        // Copy the variable, snapshotting its bounds.
        return Rc::new((**t).clone());
    }
    if t.args.is_empty() && t.params.is_empty() && t.result.is_none() {
        return t.clone();
    }
    // Most substitutions leave concrete children unchanged. Allocate each collection only
    // at its first changed child, while still walking variables to snapshot their bounds.
    let mut args: Option<Vec<Ty>> = None;
    for (i, a) in t.args.iter().enumerate() {
        // An argument that is the same node as the previous unchanged one is unchanged too, and
        // holds no variable to snapshot: skip the repeated walk of a shared subtree.
        if i > 0 && Rc::ptr_eq(a, &t.args[i - 1]) {
            continue;
        }
        let r = sub_walk(a, bindings);
        if Rc::ptr_eq(&r, a) {
            continue;
        }
        let mut values = Vec::with_capacity(t.args.len());
        values.extend_from_slice(&t.args[..i]);
        values.push(r);
        values.extend(t.args[i + 1..].iter().map(|a| sub_walk(a, bindings)));
        args = Some(values);
        break;
    }
    let mut params: Option<Vec<Param>> = None;
    for (i, p) in t.params.iter().enumerate() {
        let r = sub_walk(&p.ty, bindings);
        if Rc::ptr_eq(&r, &p.ty) {
            continue;
        }
        let mut values = Vec::with_capacity(t.params.len());
        values.extend_from_slice(&t.params[..i]);
        values.push(Param {
            name: p.name,
            ty: r,
            mutable: p.mutable,
            positional: p.positional,
        });
        values.extend(t.params[i + 1..].iter().map(|p| Param {
            name: p.name,
            ty: sub_walk(&p.ty, bindings),
            mutable: p.mutable,
            positional: p.positional,
        }));
        params = Some(values);
        break;
    }
    let mut changed = args.is_some() || params.is_some();
    let result = t.result.as_ref().map(|r| {
        let s = sub_walk(r, bindings);
        changed |= !Rc::ptr_eq(&s, r);
        s
    });
    if !changed {
        return t.clone();
    }
    Rc::new(Type {
        name: t.name,
        id: t.id,
        kind: t.kind,
        args: args.unwrap_or_else(|| t.args.clone()),
        params: params.unwrap_or_else(|| t.params.clone()),
        result,
        def: t.def.clone(),
        bounds: RefCell::new(t.bounds.borrow().clone()),
        default: RefCell::new(t.default.borrow().clone()),
        defaults: t.defaults.clone(),
        builtin: t.builtin,
    })
}

/// Erases omission permissions and selects the ordinary required-argument form
/// used by explicit function types and generic inference.
pub fn required_type(t: &Ty) -> Ty {
    if !type_any::<true>(t, |t| t.defaults.is_some()) {
        return t.clone();
    }
    required_walk(t)
}

fn required_walk(t: &Ty) -> Ty {
    let mut changed = t.defaults.is_some();
    let mut args: Option<Vec<Ty>> = None;
    for (i, a) in t.args.iter().enumerate() {
        let r = required_walk(a);
        if !Rc::ptr_eq(&r, a) && args.is_none() {
            args = Some(t.args.clone());
            changed = true;
        }
        if let Some(v) = args.as_mut() {
            v[i] = r;
        }
    }
    let mut params: Option<Vec<Param>> = None;
    for (i, p) in t.params.iter().enumerate() {
        let r = required_walk(&p.ty);
        if !Rc::ptr_eq(&r, &p.ty) && params.is_none() {
            params = Some(t.params.clone());
            changed = true;
        }
        if let Some(v) = params.as_mut() {
            v[i].ty = r;
        }
    }
    let result = t.result.as_ref().map(required_walk);
    if let (Some(r), Some(o)) = (&result, &t.result)
        && !Rc::ptr_eq(r, o)
    {
        changed = true;
    }
    if !changed {
        return t.clone();
    }
    let mut r = (**t).clone();
    r.defaults = None;
    if let Some(a) = args {
        r.args = a;
    }
    if let Some(p) = params {
        r.params = p;
    }
    r.result = result;
    Rc::new(r)
}

/// The substitution binding a nominal type's variables to its arguments.
pub fn substitution(t: &Ty) -> Subst {
    let mut r = Subst::new();
    bind_type_arguments(t, &mut r);
    r
}

/// Adds `t`'s variable-to-argument bindings.
pub fn bind_type_arguments(t: &Ty, bindings: &mut Subst) {
    if let Some(def) = &t.def {
        for (i, v) in def.variables.borrow().iter().enumerate() {
            if i < t.args.len() {
                bindings.insert(v.id, t.args[i].clone());
            }
        }
    }
}

/// Type fields with the type arguments substituted.
pub fn fields(t: &Ty) -> Vec<Param> {
    let Some(def) = &t.def else {
        return Vec::new();
    };
    let fs = def.fields.borrow();
    if fs.is_empty() {
        return Vec::new();
    }
    let s = substitution(t);
    fs.iter()
        .map(|p| Param::new(p.name, sub(&p.ty, &s)))
        .collect()
}

/// Whether the bound `b` makes a type parameter `Clonable`: `Data` and `Hashable` hold no
/// resource, so their values can be copied, as `Hashable` implies `Equal`.
pub fn implies_clonable(b: &Ty) -> bool {
    b.is(Builtin::Clonable) || b.is(Builtin::Data) || b.is(Builtin::Hashable)
}

/// Whether `t` is, or holds, a function value, which owns its captures and has no `clone`.
pub fn holds_function(t: &Ty) -> bool {
    holds_function_in(t, &mut Vec::new())
}

fn holds_function_in(t: &Ty, seen: &mut Vec<Name>) -> bool {
    match t.kind {
        Kind::Function => true,
        Kind::Type | Kind::Alternative => {
            if seen.contains(&t.id) {
                return false;
            }
            seen.push(t.id);
            let found = fields(t).iter().any(|f| holds_function_in(&f.ty, seen))
                || cases(t)
                    .iter()
                    .any(|c| c.fields.iter().any(|f| holds_function_in(&f.ty, seen)));
            seen.pop();
            found
        }
        _ => t.args.iter().any(|a| holds_function_in(a, seen)),
    }
}

/// Whether the native `t` declares an infallible `clone` of its own as an operation of its
/// definition (`fn clone() Bytes: ...` in `impl Bytes:`): the runtime can duplicate its storage.
/// A clone implemented in source (`BigInt`, `List`) is a method instead.
pub fn native_declares_clone(syms: ms_syntax::Names, t: &Ty) -> bool {
    t.def.as_ref().is_some_and(|d| {
        d.operations
            .borrow()
            .iter()
            .any(|o| syms.str(o.name) == "clone" && o.ty.result_ty().id == t.id)
    })
}

/// One declared type field, freshly substituted with the receiver's type arguments.
pub fn field_of(t: &Ty, name: Name) -> Option<Param> {
    let def = t.def.as_ref()?;
    let index = *def.field_indices.get(&name)?;
    let fs = def.fields.borrow();
    let field = fs.get(index)?;
    Some(Param::new(field.name, sub(&field.ty, &substitution(t))))
}

/// Alternative cases with the type arguments substituted.
pub fn cases(t: &Ty) -> Vec<Case> {
    let Some(def) = &t.def else {
        return Vec::new();
    };
    let cs = def.cases.borrow();
    if cs.is_empty() {
        return Vec::new();
    }
    let mut s = Subst::new();
    let mut bound = false;
    cs.iter()
        .map(|c| {
            if c.fields.is_empty() {
                return Case {
                    name: c.name,
                    fields: Vec::new(),
                };
            }
            if !bound {
                bind_type_arguments(t, &mut s);
                bound = true;
            }
            Case {
                name: c.name,
                fields: c
                    .fields
                    .iter()
                    .map(|p| Param::new(p.name, sub(&p.ty, &s)))
                    .collect(),
            }
        })
        .collect()
}

/// One case by name.
///
/// Only the named case has its type arguments substituted: building every case to pick one made
/// a match with many arms quadratic.
pub fn case_of(t: &Ty, name: Name) -> Option<Case> {
    let def = t.def.as_ref()?;
    let cs = def.cases.borrow();
    let c = cs.get(*def.case_indices.borrow().get(&name)?)?;
    let mut s = Subst::new();
    if !c.fields.is_empty() {
        bind_type_arguments(t, &mut s);
    }
    Some(Case {
        name: c.name,
        fields: c
            .fields
            .iter()
            .map(|p| Param::new(p.name, sub(&p.ty, &s)))
            .collect(),
    })
}

/// A set of type-variable ids.
pub type VarSet = HashSet<Name>;

/// Builds the variable-id set of `types`.
pub fn variable_set(types: &[Ty]) -> VarSet {
    types.iter().map(|t| t.id).collect()
}

/// One-way unification of `pattern` against `actual`, binding `vars`.
pub fn unify(pattern: &Ty, actual: &Ty, vars: &VarSet, bindings: &mut Subst) -> bool {
    unify_at(pattern, actual, vars, bindings, true)
}

/// Reader adaptation belongs to a callable value's outer boundary. Nominal arguments and
/// a callable's parameter/result types keep their invariant identity during matching.
fn unify_at(
    pattern: &Ty,
    actual: &Ty,
    vars: &VarSet,
    bindings: &mut Subst,
    adapt_reader: bool,
) -> bool {
    if vars.contains(&pattern.id) {
        if let Some(previous) = bindings.get(&pattern.id) {
            return same(previous, actual);
        }
        bindings.insert(pattern.id, required_type(actual));
        return true;
    }
    if pattern.id != actual.id
        || pattern.args.len() != actual.args.len()
        || pattern.params.len() != actual.params.len()
    {
        return false;
    }
    for (p, a) in pattern.args.iter().zip(&actual.args) {
        if !unify_at(p, a, vars, bindings, false) {
            return false;
        }
    }
    if pattern.kind == Kind::Function {
        for (p, q) in pattern.params.iter().zip(&actual.params) {
            // A function that only reads a parameter stands in for one that may change it.
            let mode_matches = p.mutable == q.mutable || (adapt_reader && p.mutable);
            if !mode_matches || !unify_at(&p.ty, &q.ty, vars, bindings, false) {
                return false;
            }
        }
        return match (&pattern.result, &actual.result) {
            (Some(p), Some(a)) => unify_at(p, a, vars, bindings, false),
            _ => false,
        };
    }
    true
}

/// Names the fix when a Result is used where its success type is required.
pub fn result_use_hint(actual: &Ty, expected: &Ty) -> String {
    if !actual.is(Builtin::Result) || actual.args.is_empty() || !same(&actual.args[0], expected) {
        return String::new();
    }
    "unwrap it with a trailing '?' inside a function that returns a compatible Result, with 'if value := x', or with '.get()'".to_string()
}

/// "expected X, found Y" plus a result hint.
pub fn format_mismatch(syms: ms_syntax::Names, actual: &Ty, expected: &Ty) -> String {
    let mut message = format!(
        "expected {expected_t}, found {actual_t}",
        expected_t = expected.display(syms),
        actual_t = actual.display(syms)
    );
    let hint = result_use_hint(actual, expected);
    if !hint.is_empty() {
        message.push_str("; ");
        message.push_str(&hint);
    }
    message
}

/// Minimum positional arity: only a fully defaulted trailing suffix may be omitted.
/// Invalid declarations can leave a required parameter after an earlier default.
pub fn required_type_arguments(vars: &[Ty]) -> usize {
    vars.iter()
        .rposition(|v| v.default.borrow().is_none())
        .map_or(0, |index| index + 1)
}

/// Fills unresolved and omitted trailing arguments from defaults.
pub fn complete_type_arguments(vars: &[Ty], args: &[Option<Ty>]) -> Vec<Option<Ty>> {
    let mut result: Vec<Option<Ty>> = args.to_vec();
    let mut bindings = Subst::new();
    for (index, v) in vars.iter().enumerate() {
        if index >= result.len() {
            result.push(None);
        }
        if result[index].is_none()
            && let Some(d) = v.default_ty()
        {
            result[index] = Some(sub(&d, &bindings));
        }
        if let Some(r) = &result[index] {
            bindings.insert(v.id, r.clone());
        }
    }
    result
}

/// Extends explicit arguments with defaults of the remaining variables.
pub fn with_default_arguments(vars: &[Ty], args: &[Ty]) -> Vec<Ty> {
    let mut result: Vec<Ty> = args.to_vec();
    let mut bindings = Subst::new();
    for (i, a) in result.iter().enumerate() {
        bindings.insert(vars[i].id, a.clone());
    }
    for v in &vars[args.len()..] {
        let d = v.default_ty().expect("default exists for omitted argument");
        let a = sub(&d, &bindings);
        bindings.insert(v.id, a.clone());
        result.push(a);
    }
    result
}

/// Whether `t` mentions `<invalid>` anywhere.
pub fn invalid_type(t: &Option<Ty>) -> bool {
    t.as_ref().is_some_and(invalid_ty)
}

/// Searches a type graph without allocating for ordinary small queries.
/// `CALLABLES` selects whether parameter/result edges are part of the query.
/// The predicate must remain stable for each node throughout the query.
pub(crate) fn type_any<const CALLABLES: bool>(t: &Ty, matches: impl Fn(&Ty) -> bool) -> bool {
    fn bounded<const CALLABLES: bool>(
        t: &Ty,
        matches: &impl Fn(&Ty) -> bool,
        remaining: &mut u8,
    ) -> Option<bool> {
        if matches(t) {
            return Some(true);
        }
        if t.args.is_empty() && (!CALLABLES || (t.params.is_empty() && t.result.is_none())) {
            return Some(false);
        }
        *remaining = remaining.checked_sub(1)?;
        for a in &t.args {
            if bounded::<CALLABLES>(a, matches, remaining)? {
                return Some(true);
            }
        }
        if CALLABLES {
            for p in &t.params {
                if bounded::<CALLABLES>(&p.ty, matches, remaining)? {
                    return Some(true);
                }
            }
            if let Some(r) = &t.result {
                return bounded::<CALLABLES>(r, matches, remaining);
            }
        }
        Some(false)
    }
    fn visit<const CALLABLES: bool>(
        t: &Ty,
        matches: &impl Fn(&Ty) -> bool,
        seen: &mut HashSet<*const Type>,
    ) -> bool {
        if matches(t) {
            return true;
        }
        if !seen.insert(Rc::as_ptr(t)) {
            return false;
        }
        t.args.iter().any(|a| visit::<CALLABLES>(a, matches, seen))
            || (CALLABLES
                && (t
                    .params
                    .iter()
                    .any(|p| visit::<CALLABLES>(&p.ty, matches, seen))
                    || t.result
                        .as_ref()
                        .is_some_and(|r| visit::<CALLABLES>(r, matches, seen))))
    }
    if t.args.is_empty() && (!CALLABLES || (t.params.is_empty() && t.result.is_none())) {
        return matches(t);
    }
    // Ordinary queries need only a stack counter. Retry a large query with
    // deduplication after at most64 nonleaf expansions, independent of DAG size.
    bounded::<CALLABLES>(t, &matches, &mut 64)
        .unwrap_or_else(|| visit::<CALLABLES>(t, &matches, &mut HashSet::new()))
}

/// Whether `t` mentions `<invalid>` anywhere.
pub fn invalid_ty(t: &Ty) -> bool {
    type_any::<true>(t, |t| t.is_invalid())
}

/// Whether the top-level id is `<invalid>`.
pub fn is_invalid_id(t: &Ty) -> bool {
    t.is_invalid()
}

/// Whether `t` mentions a variable of `variables`.
pub fn mentions_variable(t: &Ty, variables: &VarSet) -> bool {
    type_any::<true>(t, |t| variables.contains(&t.id))
}

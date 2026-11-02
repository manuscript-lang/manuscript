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
    Name::intern(text)
}

/// A shared, immutable checked type.
pub type Ty = Rc<Type>;

/// The kind of a type .
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    /// `Int`, `Bool`, ... and the `<invalid>` marker.
    Primitive,
    /// A type parameter.
    Variable,
    /// A record type (`type T:` with fields).
    Record,
    /// An alternative type (`type T:` with cases).
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
            Kind::Variable => "variable",
            Kind::Record => "record",
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

    /// The already-omittable native parameter whose MissingValue is made at the call.
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
        }
    }
}

impl fmt::Debug for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self}")
    }
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.kind == Kind::Function {
            f.write_str("fn(")?;
            for (i, a) in self.params.iter().enumerate() {
                if i > 0 {
                    f.write_str(", ")?;
                }
                write!(f, "{}", a.ty)?;
            }
            f.write_str(") ")?;
            return match &self.result {
                Some(r) => write!(f, "{r}"),
                None => f.write_str("<unknown>"),
            };
        }
        if self.is_std("Optional") && self.args.len() == 1 {
            let inner = &self.args[0];
            return if inner.kind == Kind::Function {
                write!(f, "({inner})?")
            } else {
                write!(f, "{inner}?")
            };
        }
        f.write_str(self.name.as_str())?;
        if !self.args.is_empty() {
            f.write_char('[')?;
            for (i, a) in self.args.iter().enumerate() {
                if i > 0 {
                    f.write_str(", ")?;
                }
                write!(f, "{a}")?;
            }
            f.write_char(']')?;
        }
        Ok(())
    }
}

/// Formats an optional type; `None` prints as `<unknown>`.
pub fn show(t: &Option<Ty>) -> String {
    match t {
        Some(t) => t.to_string(),
        None => "<unknown>".to_string(),
    }
}

impl Type {
    /// A bare type of one kind.
    pub fn new(name: Name, id: Name, kind: Kind) -> Type {
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

    /// The id as text.
    pub fn id_str(&self) -> &'static str {
        self.id.as_str()
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

    /// Standard type test: id is `@std/<name>`.
    pub fn is_std(&self, name: &str) -> bool {
        let id = self.id.as_str();
        id.len() == 5 + name.len() && id.starts_with("@std/") && &id[5..] == name
    }

    /// Whether this is `Duration`, `Instant` or `Timestamp` of `@std/os/time.ms`.
    pub fn is_time(&self, name: &str) -> bool {
        self.is_source_type("@std/os/time.ms", name)
    }

    /// Whether this is the type `name` declared by the bundled source module `module`.
    pub fn is_source_type(&self, module: &str, name: &str) -> bool {
        self.name.as_str() == name && self.symbol().is_some_and(|s| s.module.as_str() == module)
    }

    /// The nominal definition's symbol, if any.
    pub fn symbol(&self) -> Option<SymRef> {
        self.def.as_ref().and_then(|d| d.symbol())
    }

    /// The declaring file of an `opaque type`, or `None` for any other type.
    pub fn opaque_module(&self) -> Option<Name> {
        let symbol = self.symbol()?;
        let opaque = match &symbol.decl.as_ref()?.decl().kind {
            DeclKind::Record(r) => r.opaque,
            DeclKind::Alternative(a) => a.opaque,
            _ => false,
        };
        opaque.then_some(symbol.module)
    }
}

/// `std(t, name)` for an optional type.
pub fn std_is(t: &Option<Ty>, name: &str) -> bool {
    t.as_ref().is_some_and(|t| t.is_std(name))
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
    /// Definition kind (record, alternative, contract, native).
    pub kind: Kind,
    /// Declared type variables.
    pub variables: RefCell<Vec<Ty>>,
    /// Record fields.
    pub fields: RefCell<Vec<Param>>,
    /// Alternative cases.
    pub cases: RefCell<Vec<Case>>,
    /// Contract or native operations.
    pub operations: RefCell<Vec<Operation>>,
}

impl Definition {
    /// A new definition owned by `symbol`.
    pub fn new(symbol: &SymRef, kind: Kind) -> Rc<Definition> {
        let mut field_indices = HashMap::new();
        if let Some(decl) = &symbol.decl {
            for (index, field) in decl.record_fields().iter().enumerate() {
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
            operations: RefCell::new(Vec::new()),
        })
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
    /// A type (record, alternative, interface or primitive).
    Type,
    /// A function (including constants and native functions).
    Fn,
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
    /// Native binding identity ("" when the symbol has a source body).
    pub native: Name,
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
    pub fn ty(&self) -> Ty {
        self.ty
            .borrow()
            .clone()
            .unwrap_or_else(|| panic!("symbol type resolved: {} in {}", self.name, self.module))
    }

    /// The symbol's type if resolved.
    pub fn ty_opt(&self) -> Option<Ty> {
        self.ty.borrow().clone()
    }

    /// Declared variables.
    pub fn variables(&self) -> Vec<Ty> {
        self.variables.borrow().clone()
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
    /// Native identity ("contract" for a contract operation).
    pub native: Name,
}

/// A shared method.
pub type MethodRef = Rc<Method>;

impl Method {
    /// Extensions stay in their declaring module; implementations owned by the
    /// receiver's defining module are available wherever the type is used.
    pub fn visible_in(&self, module: Name) -> bool {
        !self.local || self.module == module
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
    static PRIMS: Prims = Prims::new();
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
        let p = |s: &str| Rc::new(Type::new(n(s), n(s), Kind::Primitive));
        Prims {
            int: p("Int"),
            float: p("Float"),
            bool_: p("Bool"),
            string: p("String"),
            unit: p("Unit"),
            never: p("Never"),
            invalid: p("<invalid>"),
            inferred: p("<inferred>"),
        }
    }
}

/// A primitive type by name.
pub fn primitive(name: &str) -> Ty {
    PRIMS.with(|p| match name {
        "Int" => p.int.clone(),
        "Float" => p.float.clone(),
        "Bool" => p.bool_.clone(),
        "String" => p.string.clone(),
        "Unit" => p.unit.clone(),
        "Never" => p.never.clone(),
        "<invalid>" => p.invalid.clone(),
        "<inferred>" => p.inferred.clone(),
        other => Rc::new(Type::new(n(other), n(other), Kind::Primitive)),
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
    match t.id.as_str() {
        "Int" => Some(DEFAULT_INT_BITS),
        "Int8" => Some(8),
        "Int16" => Some(16),
        "Int32" => Some(32),
        "Int64" => Some(64),
        "UInt8" => Some(8),
        "UInt16" => Some(16),
        "UInt32" => Some(32),
        "UInt64" => Some(64),
        _ => None,
    }
}

/// Whether `t` is an unsigned integer type.
pub fn int_unsigned(t: &Type) -> bool {
    matches!(t.id.as_str(), "UInt8" | "UInt16" | "UInt32" | "UInt64")
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
    match t.id.as_str() {
        "Float" => Some(DEFAULT_FLOAT_BITS),
        "Float32" => Some(32),
        "Float64" => Some(64),
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
    primitive("<invalid>")
}

/// A function type.
pub fn function(params: Vec<Param>, result: Ty) -> Ty {
    let mut t = Type::new(n("fn"), n("fn"), Kind::Function);
    t.params = params;
    t.result = Some(result);
    Rc::new(t)
}

/// A function type with omittable parameters.
pub fn function_with(params: Vec<Param>, result: Ty, defaults: Defaults) -> Ty {
    let mut t = Type::new(n("fn"), n("fn"), Kind::Function);
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

/// Standard declaration lookup is provided by the loaded standard world.
pub fn standard(name: &str, args: Vec<Ty>) -> Ty {
    let sym =
        crate::stdlib::standard_symbol(name).unwrap_or_else(|| panic!("standard type {name}"));
    with_args(&sym.ty(), args)
}

/// `Duration`, `Instant` or `Timestamp`, the records of `@std/os/time.ms`.
pub fn time_type(name: &str) -> Ty {
    // The module is checked on first use; its records have no fields before that.
    crate::stdlib::standard_exports("@std/os/time.ms");
    let sym = crate::stdlib::source_type(n("@std/os/time.ms"), n(name))
        .unwrap_or_else(|| panic!("standard time type {name}"));
    sym.ty()
}

/// `TestOutcome`: the implicit `Result[Unit, Error]` of a test block.
pub fn test_outcome() -> Ty {
    standard("Result", vec![unit(), standard("Error", vec![])])
}

/// Whether `t` is `Result[Unit, Error]`, the result of every `close`.
pub fn is_close_result(t: &Ty) -> bool {
    t.is_std("Result") && t.args.len() == 2 && t.args[0].id == "Unit" && t.args[1].is_std("Error")
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
                if !compare(&p.ty, &q.ty, context) {
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
        Some(a) => a.id == "Never" || same(a, expected),
        None => false,
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
        });
        values.extend(t.params[i + 1..].iter().map(|p| Param {
            name: p.name,
            ty: sub_walk(&p.ty, bindings),
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
    })
}

/// `Sub` over an optional type.
pub fn sub_opt(t: &Option<Ty>, bindings: &Subst) -> Option<Ty> {
    t.as_ref().map(|t| sub(t, bindings))
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

/// Record fields with the type arguments substituted.
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
        .map(|p| Param {
            name: p.name,
            ty: sub(&p.ty, &s),
        })
        .collect()
}

/// Whether the bound `b` makes a type parameter `Clonable`: `Data` and `Hashable` hold no
/// resource, so their values can be copied, as `Hashable` implies `Equal`.
pub fn implies_clonable(b: &Ty) -> bool {
    b.is_std("Clonable") || b.is_std("Data") || b.is_std("Hashable")
}

/// One declared record field, freshly substituted with the receiver's type arguments.
pub fn field_of(t: &Ty, name: Name) -> Option<Param> {
    let def = t.def.as_ref()?;
    let index = *def.field_indices.get(&name)?;
    let fs = def.fields.borrow();
    let field = fs.get(index)?;
    Some(Param {
        name: field.name,
        ty: sub(&field.ty, &substitution(t)),
    })
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
                    .map(|p| Param {
                        name: p.name,
                        ty: sub(&p.ty, &s),
                    })
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
    let c = cs.iter().find(|c| c.name == name)?;
    let mut s = Subst::new();
    if !c.fields.is_empty() {
        bind_type_arguments(t, &mut s);
    }
    Some(Case {
        name: c.name,
        fields: c
            .fields
            .iter()
            .map(|p| Param {
                name: p.name,
                ty: sub(&p.ty, &s),
            })
            .collect(),
    })
}

/// Constructor inputs and omission permissions.
pub fn constructor_signature(t: &Ty) -> Ty {
    let mut params = fields(t);
    if t.is_std("Bytes") {
        params = vec![Param {
            name: n("values"),
            ty: standard("List", vec![primitive("UInt8")]),
        }];
    }
    if t.is_std("Set") && t.args.len() == 1 {
        params = vec![Param {
            name: n("values"),
            ty: standard("List", vec![t.args[0].clone()]),
        }];
    }
    let mut defaults: HashSet<Name> = HashSet::new();
    if let Some(sym) = t.symbol()
        && let Some(decl) = &sym.decl
    {
        for f in decl.record_fields() {
            if f.default.is_some() {
                defaults.insert(f.name);
            }
        }
    }
    let defaults = if defaults.is_empty() {
        None
    } else {
        Some(Rc::new(ParameterDefaults::new(defaults)))
    };
    function_with(params, t.clone(), defaults)
}

/// A key identifying a type's structure.
pub fn type_key(t: &Ty) -> String {
    let mut key = String::new();
    write_type_key(&mut key, t, false);
    key
}

/// `type_key` plus which function parameters are represented as optionals.
pub fn lowering_key(t: &Ty) -> String {
    let mut key = String::new();
    write_type_key(&mut key, t, true);
    key
}

fn write_type_key(key: &mut String, t: &Ty, lifted: bool) {
    key.push_str(t.id.as_str());
    if t.kind == Kind::Function {
        for p in &t.params {
            key.push('[');
            write_type_key(key, &p.ty, lifted);
            if lifted && t.is_lifted(p.name) {
                key.push('=');
            }
            key.push(']');
        }
        key.push_str("[result:");
        if let Some(r) = &t.result {
            write_type_key(key, r, lifted);
        }
        key.push(']');
    }
    for a in &t.args {
        key.push('[');
        write_type_key(key, a, lifted);
        key.push(']');
    }
}

/// A set of type-variable ids.
pub type VarSet = HashSet<Name>;

/// Builds the variable-id set of `types`.
pub fn variable_set(types: &[Ty]) -> VarSet {
    types.iter().map(|t| t.id).collect()
}

/// One-way unification of `pattern` against `actual`, binding `vars`.
pub fn unify(pattern: &Ty, actual: &Ty, vars: &VarSet, bindings: &mut Subst) -> bool {
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
        if !unify(p, a, vars, bindings) {
            return false;
        }
    }
    if pattern.kind == Kind::Function {
        for (p, q) in pattern.params.iter().zip(&actual.params) {
            if !unify(&p.ty, &q.ty, vars, bindings) {
                return false;
            }
        }
        return match (&pattern.result, &actual.result) {
            (Some(p), Some(a)) => unify(p, a, vars, bindings),
            _ => false,
        };
    }
    true
}

/// "expected X, found Y" plus a result hint.
pub fn format_mismatch(actual: &Ty, expected: &Ty) -> String {
    let mut message = format!("expected {expected}, found {actual}");
    let hint = crate::hints::result_use_hint(actual, expected);
    if !hint.is_empty() {
        message.push_str("; ");
        message.push_str(&hint);
    }
    message
}

/// Counts the leading type variables without a default.
pub fn required_type_arguments(vars: &[Ty]) -> usize {
    for (i, v) in vars.iter().enumerate() {
        if v.default.borrow().is_some() {
            return i;
        }
    }
    vars.len()
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
    type_any::<true>(t, |t| t.id == "<invalid>")
}

/// Whether the top-level id is `<invalid>`.
pub fn is_invalid_id(t: &Ty) -> bool {
    t.id == "<invalid>"
}

/// Whether `t` mentions a variable of `variables`.
pub fn mentions_variable(t: &Ty, variables: &VarSet) -> bool {
    type_any::<true>(t, |t| variables.contains(&t.id))
}

/// Names of params.
pub fn param_names(params: &[Param]) -> Vec<&'static str> {
    params.iter().map(|p| p.name.as_str()).collect()
}

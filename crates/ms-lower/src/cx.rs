//! Whole-program lowering state: module queries, type mapping and function instances.

use crate::Error;
use ms_check::Program;
use ms_check::api::NodeId;
use ms_check::api::hir::{Callable, ModuleHir};
use ms_check::api::ownership::BorrowKind;
use ms_check::api::types::{self as ct, Builtin, Kind, Name, Subst};
use ms_check::fxmap::HashMap;
use ms_mir::ir::{FuncId, Module};
use ms_mir::types::{CaseDef, IfaceDef, MethodSig, Std, Ty as MTy};
use ms_mir::types::{Native, NativeType};
use std::rc::Rc;

/// What an instance is requested with besides its type variables.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, Hash)]
pub struct Variant {
    /// The instance takes the parameters its body moving_params owned.
    pub owned: bool,
    /// The module whose local implementations the instance's type variables use.
    pub evidence: Option<ms_check::api::types::Name>,
}

/// A dense side column indexed by a MIR type or declaration number: a vector of slots, no hashing.
#[derive(Clone, Debug)]
pub struct Column<T>(Vec<Option<T>>);

impl<T> Default for Column<T> {
    fn default() -> Self {
        Column(Vec::new())
    }
}

impl<T> Column<T> {
    /// The value at `at`, if set.
    pub fn get(&self, at: usize) -> Option<&T> {
        self.0.get(at)?.as_ref()
    }

    /// Whether `at` is set.
    pub fn contains(&self, at: usize) -> bool {
        self.get(at).is_some()
    }

    /// Sets `at` unless it already holds a value.
    pub fn set_if_absent(&mut self, at: usize, value: T) {
        if self.0.len() <= at {
            self.0.resize_with(at + 1, || None);
        }
        self.0[at].get_or_insert(value);
    }
}

/// What a bound-method thunk reaches the method through.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum BoundTarget {
    /// Interface `iface`, method `k`.
    Iface(u32, usize),
    /// A source instance.
    Func(FuncId),
}

/// Identity of a generated helper function: one variant per kind, with the types and flags
/// that distinguish its instances.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum HelperKey {
    Eq(MTy, u32),
    Fmt(MTy, bool),
    Json {
        encode: bool,
        ty: ms_check::api::tytable::TyId,
    },
    JsonTree(ms_check::api::tytable::TyId),
    JsonTreeView(ms_check::api::tytable::TyId),
    CloseParts(ms_check::api::tytable::TyId, bool),
    CloseOptional(MTy, crate::close::CloseKind),
    CloseIface {
        iface: u32,
        k: u32,
        in_slot: bool,
    },
    CloseFunc {
        fid: FuncId,
        writes_back: bool,
        in_slot: bool,
    },
    Thunk(FuncId),
    /// An inlinable map or set lookup of the given slot shape and result.
    MapProbe(crate::rtinline::Shape, crate::rtinline::Answer),
    /// The inlinable fast path of `String.view`.
    StringView,
    /// The close of an owner whose failure is dropped: a function of its own, by the type it closes.
    CloseSilent(MTy, crate::close::CloseKind),
    /// The close of a loop's cursor over an owned list of the given type, closing the elements it
    /// never reached with the given close, when there is one.
    ListTail(MTy, Option<crate::close::CloseKind>),
    /// The close of a field held in memory that never turns into a returning close.
    CloseField(MTy, crate::close::CloseKind),
    /// What a type holds besides the resource fields at these paths, which other owners close.
    SplitRest(MTy, Vec<Vec<u32>>),
    /// How a failed scope-end close becomes the return of a function of the given type: the
    /// close's `Result` type, the function's return type, whether a pending return is held, and
    /// whether that return is a borrow the exit must not release.
    CloseExit(MTy, MTy, bool, bool),
    /// The function that runs a slot close and returns its `Result`.
    CloseResult(FuncId),
    DefaultThunk {
        fid: FuncId,
        fty: MTy,
        shared: bool,
    },
    DirectDefault(FuncId),
    IfaceThunk {
        iface: u32,
        k: usize,
        fty: MTy,
        addr: bool,
    },
    BoundSharedIface {
        iface: u32,
        k: usize,
        fty: MTy,
    },
    BoundSharedFunc {
        fid: FuncId,
        fty: MTy,
    },
    Bound {
        target: BoundTarget,
        fty: MTy,
        addr: bool,
    },
    BoundNative {
        native: ct::Native,
        rty: MTy,
        fty: MTy,
        held: Held,
        scope: Option<Name>,
    },
    NativeThunk {
        native: ct::Native,
        fty: MTy,
    },
    TostringThunk(MTy, bool),
    MsFn(MTy),
    WalkThunk(MTy, bool),
    ServeThunk(MTy),
}

/// Identity of a generated interface implementation table.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum VtableKey {
    Impl {
        ty: ms_check::api::tytable::TyId,
        iface: u32,
        scope: Option<Name>,
    },
    Handle {
        module: Name,
        iface: u32,
    },
}

impl VtableKey {
    /// The table's name in the module, as before keys were typed.
    pub fn name(&self, syms: ms_check::api::Names) -> String {
        match self {
            VtableKey::Impl { ty, iface, scope } => match scope {
                Some(s) => format!("impl:{}:{iface}@{}", ty.index(), syms.str(s)),
                None => format!("impl:{}:{iface}", ty.index()),
            },
            VtableKey::Handle { module, iface } => format!("handle:{}:{iface}", syms.str(module)),
        }
    }
}

/// The key of a reserved instance: the callable, its type variables and its variant.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct InstKey {
    pub file: ms_check::api::types::Name,
    pub node: NodeId,
    pub subst: Vec<(ms_check::api::types::Name, ms_check::api::tytable::TyId)>,
    pub variant: Variant,
}

/// What a reserved function is made of.
pub enum JobKind {
    /// A source callable under a substitution.
    Source {
        /// What to lower.
        callable: Rc<Callable>,
        /// Type variables of the instance.
        subst: Subst,
        /// Ownership and evidence the instance was requested with.
        variant: Variant,
    },
    /// The text form of a value of the MIR type.
    Format(MTy, bool),
    /// A lambda body under the instance substitution.
    Lambda(Rc<LambdaJob>),
    /// Structural equality of two values of the MIR type.
    Equal(MTy, u32),
    /// A native function used as a value.
    NativeThunk(Rc<NativeThunkJob>),
    /// A native method bound to its receiver.
    BoundNative(Rc<BoundNativeJob>),
    /// A native method behind an interface table entry.
    IfaceNative(Rc<IfaceNativeJob>),
    /// A mutating method value bound to a mutable alias.
    BoundAlias(Rc<crate::bound_alias::BoundAliasJob>),
    /// A source callable used as a value whose omittable parameters are optionals.
    DefaultThunk(Rc<DefaultThunkJob>),
    /// An interface method used as a value whose function type takes optionals.
    IfaceThunk(Rc<IfaceThunkJob>),
    /// A function value viewed with its omittable parameters as plain values.
    FnAdapt(Rc<FnAdaptJob>),
    /// A JSON decoder or encoder of a type.
    Json(Rc<crate::json::JsonJob>),
    /// A forwarder of an interface operation to a runtime handle function.
    HandleMethod(Rc<crate::natiface::MethodJob>),
}

/// An interface method value waiting to be lowered; the closure holds the interface value.
pub struct IfaceThunkJob {
    /// The interface and the method's vtable index.
    pub iface: ms_mir::types::IfaceId,
    pub index: u32,
    /// The method as declared.
    pub method: ct::MethodRef,
    /// Module the use is written in.
    pub hir: Rc<ModuleHir>,
    /// The interface type of the receiver.
    pub recv: MTy,
    /// The closure holds the address of the receiver (a variable the method changes, or one a
    /// value that stays local only reads) instead of the receiver.
    pub shared: bool,
}

/// How a method value's closure holds its receiver.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Held {
    /// The receiver itself, owned by the closure.
    Value,
    /// The address of the variable the method changes, and the receiver's type.
    Shared(MTy),
    /// The address of the receiver a value that stays local only reads (`bound_borrows`), and
    /// the receiver's type.
    Borrowed(MTy),
}

impl Held {
    /// The type of the closure's capture.
    pub fn capture(self, recv: MTy) -> MTy {
        match self {
            Held::Value => recv,
            Held::Shared(_) | Held::Borrowed(_) => MTy::PTR,
        }
    }
}

/// A function value whose omittable parameters are optionals, passed where plain ones are taken.
pub struct FnAdaptJob {
    /// Module the use is written in.
    pub hir: Rc<ModuleHir>,
    /// The held function type.
    pub have: MTy,
    /// The held value points into its maker's frame, so the adapter reads it through a pointer
    /// and stays inside that frame too.
    pub scoped: bool,
    /// Parameters the held value reads that the adapter receives as the address of a slot.
    pub reads: Vec<bool>,
}

/// A bound native method waiting to be lowered; the closure holds the receiver.
pub struct BoundNativeJob {
    /// Consuming implementation parameters in declaration order, excluding the receiver.
    pub consumed_arguments: Vec<bool>,
    /// The method.
    pub method: ct::MethodRef,
    /// Module the use is written in.
    pub hir: Rc<ModuleHir>,
    /// How the closure holds the receiver.
    pub held: Held,
    /// The module whose local implementations the method's key and element types use.
    pub scope: Name,
}

/// A native method called through an interface table, waiting to be lowered. The first
/// parameter is the address of the implementing value.
pub struct IfaceNativeJob {
    /// The method under the implementing type's substitution.
    pub method: ct::MethodRef,
    /// Module the method is declared in.
    pub hir: Rc<ModuleHir>,
    /// The implementing type.
    pub data: MTy,
    /// The module whose local implementations the method's types use.
    pub scope: Name,
}

/// A native function value waiting to be lowered.
pub struct NativeThunkJob {
    /// The native function.
    pub native: ct::Native,
    /// Declared parameters under the use site's substitution.
    pub params: Vec<ct::Param>,
    /// Declared result under the use site's substitution.
    pub result: ct::Ty,
    /// The declaration, for the defaults of omitted parameters.
    pub sym: ct::SymRef,
    /// Module the use is written in.
    pub hir: Rc<ModuleHir>,
}

/// A lambda waiting to be lowered.
pub struct LambdaJob {
    /// The lambda expression.
    pub expr: ms_check::api::ast::Expr,
    /// Module the lambda is written in.
    pub hir: Rc<ModuleHir>,
    /// Type variables of the enclosing instance.
    pub subst: Subst,
    /// Ownership and evidence of the enclosing instance.
    pub variant: Variant,
    /// Source captures and their slots in the closure environment.
    pub captures: Vec<crate::closure::LambdaCapture>,
}

/// A source callable behind a function value that fills omitted defaults.
pub struct DefaultThunkJob {
    /// The callable.
    pub callable: Rc<Callable>,
    /// Type variables of the instance.
    pub subst: Subst,
    /// The captured receiver type of a bound method.
    pub recv: Option<MTy>,
    /// The receiver's type when the closure holds the address of the variable it changes.
    pub shared: Option<MTy>,
}

/// A function body waiting to be lowered.
pub struct Job {
    /// The reserved function.
    pub func: FuncId,
    /// What to lower.
    pub kind: JobKind,
}

/// Whole-program lowering context.
/// Positions in `Cx::methods` by operation name and receiver type, so finding the method a type
/// provides does not scan every method of the program (a table per implementing type would make
/// that quadratic).
#[derive(Default)]
pub struct MethodIndex {
    by_receiver: HashMap<(Name, Name), Vec<usize>>,
    /// Methods whose receiver is a type variable match any receiver.
    by_variable: HashMap<Name, Vec<usize>>,
}

impl MethodIndex {
    fn new(methods: &[ct::MethodRef]) -> Self {
        let mut index = MethodIndex::default();
        for (at, m) in methods.iter().enumerate() {
            let Some(op) = m.name() else { continue };
            if m.variables.iter().any(|v| v.id == m.receiver.id) {
                index.by_variable.entry(op).or_default().push(at);
            } else {
                index
                    .by_receiver
                    .entry((m.receiver.id, op))
                    .or_default()
                    .push(at);
            }
        }
        index
    }

    /// The positions of the methods named `op` that can match `receiver`, in declaration order.
    pub fn candidates(&self, receiver: Name, op: Name) -> Vec<usize> {
        let mut at: Vec<usize> = [
            self.by_receiver.get(&(receiver, op)),
            self.by_variable.get(&op),
        ]
        .into_iter()
        .flatten()
        .flatten()
        .copied()
        .collect();
        at.sort_unstable();
        at
    }
}

pub struct Cx {
    /// Reads and interns identifier text.
    pub syms: ms_check::api::Names,
    /// The session whose standard library the program was checked against.
    pub session: Rc<ms_check::Session>,
    /// Lowering sites that copied a borrow into an owning position, with the producer op.
    pub copy_gaps: Vec<String>,
    /// Module queries by file.
    pub mods: HashMap<Name, Rc<ModuleHir>>,
    /// Callables by (module file, declaration or method node id).
    pub callables: HashMap<(Name, NodeId), Rc<Callable>>,
    /// MIR types by checker type key.
    pub tycache: Vec<Option<MTy>>,
    /// Checker type identities, interned on demand while lowering.
    pub tys: ms_check::api::tytable::TyTable,
    /// The runtime's raw `fs` info type, once built.
    pub fs_info_raw: Option<MTy>,
    /// Function instances by key.
    pub insts: HashMap<InstKey, FuncId>,
    /// Bodies waiting to be lowered.
    pub queue: Vec<Job>,
    /// Types and alternatives declared `opaque type`; their text form is the type name.
    pub opaque_tys: Column<()>,
    /// Helper functions (formatting, equality, ...) by key.
    pub helpers: HashMap<HelperKey, FuncId>,
    /// The type a loop over an owned list keeps in memory (the list and the next index) by
    /// list type.
    pub list_cursors: HashMap<MTy, (ms_mir::types::TypeId, MTy)>,
    /// Interface implementation tables built by lowering.
    pub vtables: HashMap<VtableKey, ms_mir::ir::VtableId>,
    /// The checker type of every lowered interface.
    pub contracts: HashMap<ms_mir::types::IfaceId, ct::Ty>,
    /// Every implementation method of the program.
    pub methods: Vec<ct::MethodRef>,
    /// `methods` by receiver and operation name.
    pub method_index: MethodIndex,
    /// The checker type behind each lowered type or alternative.
    pub source_tys: Column<ct::Ty>,
    /// The `.ms` methods of the native types, built once from the program's methods.
    pub native_ops: crate::nativetype::NativeOps,
    /// Types whose descriptor glue is registered, per implementation scope.
    pub glue_seen: ms_check::fxmap::HashSet<(MTy, u32)>,
    /// Nominal types with an extension implemented outside their defining module.
    pub extended: ms_check::fxmap::HashSet<Name>,
    /// The modules that scoped tables were built for; a scope number is the position plus one.
    pub scope_names: Vec<Name>,
    /// Parameters (receiver first) that functions hand back changed.
    pub mutated: ms_check::fxmap::HashSet<crate::mutation::ParamKey>,
    /// The `make_fixture` factory and hooks type of each module with tests.
    pub fixtures: HashMap<Name, ms_check::TestFixture>,
    /// What the ownership stage decided: moves, borrows, getters, captures, per-node and per-binding
    /// facts. Lowering reads these and decides none of them again.
    pub ownership: Rc<ms_check::api::ownership::OwnershipFacts>,
    /// Which types are resources, for the closers of types and collections that hold them.
    pub classes: ms_check::api::ownership::Classifier,
}

impl Cx {
    /// Fails when lowering recorded an implicit copy of a borrow.
    pub fn check_strict_copies(&self) -> Result<(), crate::Error> {
        if self.copy_gaps.is_empty() {
            return Ok(());
        }
        let mut sites = self.copy_gaps.clone();
        sites.sort();
        let total = sites.len();
        sites.dedup();
        Err(crate::Error::new(format!(
            "internal: {total} implicit copies of a borrow at {}",
            sites.join(", ")
        )))
    }

    /// The binding is a `var` borrow: it lowers as a path into its origin.
    pub fn exclusive(&self, uid: usize) -> bool {
        self.ownership.binding_facts.borrow(uid) == Some(BorrowKind::Exclusive)
    }

    /// The binding is a `let` borrow of a place: it may point into its origin instead of copying.
    pub fn shared(&self, uid: usize) -> bool {
        self.ownership.binding_facts.borrow(uid) == Some(BorrowKind::Shared)
    }

    /// Indexes every module of the program.
    pub fn new(syms: ms_check::api::Names, program: &Program) -> Cx {
        let mut mods = HashMap::default();
        let mut callables = HashMap::default();
        for m in program.hir().modules() {
            for c in m.callables() {
                callables.insert((m.data.file, c.id()), Rc::new(c));
            }
            mods.insert(m.data.file, Rc::new(m));
        }
        let mutated = crate::mutation::infer_mutated(&callables);
        let native_ops = crate::nativetype::NativeOps::new(syms, program, &callables);
        let extended = program
            .methods
            .iter()
            .filter(|m| m.local)
            .map(|m| m.receiver.id)
            .collect();
        Cx {
            syms: program.syms,
            session: program.session.clone(),
            copy_gaps: Vec::new(),
            extended,
            scope_names: Vec::new(),
            mods,
            callables,
            mutated,
            source_tys: Default::default(),
            native_ops,
            glue_seen: Default::default(),
            tycache: Vec::new(),
            tys: Default::default(),
            fs_info_raw: None,
            insts: HashMap::default(),
            queue: Vec::new(),
            opaque_tys: Default::default(),
            helpers: HashMap::default(),
            list_cursors: HashMap::default(),
            vtables: HashMap::default(),
            contracts: HashMap::default(),
            method_index: MethodIndex::new(&program.methods),
            methods: program.methods.clone(),
            fixtures: program.test_fixtures.clone(),
            ownership: program.ownership.clone(),
            classes: ms_check::api::ownership::Classifier::new(program),
        }
    }

    /// The module queries for `file`.
    pub fn module(&self, file: Name) -> Result<Rc<ModuleHir>, Error> {
        self.mods.get(&file).cloned().ok_or_else(|| {
            Error::new(format!(
                "unknown module {file_t} (have {:?})",
                self.mods
                    .keys()
                    .map(|k| self.syms.str(k).to_string())
                    .collect::<Vec<_>>(),
                file_t = self.syms.str(file)
            ))
        })
    }

    /// Maps a concrete checker type to a MIR type.
    pub fn lower_ty(&mut self, m: &mut Module, t: &ct::Ty) -> Result<MTy, Error> {
        match t.kind {
            Kind::Primitive => {
                return match t.builtin {
                    Some(Builtin::Int | Builtin::Int64) => Ok(MTy::INT),
                    Some(Builtin::Int8) => Ok(MTy::INT8),
                    Some(Builtin::Int16) => Ok(MTy::INT16),
                    Some(Builtin::Int32) => Ok(MTy::INT32),
                    Some(Builtin::UInt8) => Ok(MTy::UINT8),
                    Some(Builtin::UInt16) => Ok(MTy::UINT16),
                    Some(Builtin::UInt32) => Ok(MTy::UINT32),
                    Some(Builtin::UInt64) => Ok(MTy::UINT64),
                    Some(Builtin::Float | Builtin::Float64) => Ok(MTy::FLOAT),
                    Some(Builtin::Float32) => Ok(MTy::FLOAT32),
                    Some(Builtin::Bool) => Ok(MTy::BOOL),
                    Some(Builtin::String) => Ok(MTy::STR),
                    Some(Builtin::Unit | Builtin::Never) => Ok(MTy::UNIT),
                    _ => Err(Error::new(format!(
                        "unsupported primitive type {}",
                        self.syms.str(t.id)
                    ))),
                };
            }
            Kind::Invalid | Kind::Inferred => {
                return Err(Error::new(format!(
                    "unsupported primitive type {}",
                    self.syms.str(t.id)
                )));
            }
            Kind::Variable => {
                return Err(Error::new(format!(
                    "unsubstituted type variable {}",
                    self.syms.str(t.name)
                )));
            }
            _ => {}
        }
        let key = self.tys.intern(t);
        if let Some(Some(found)) = self.tycache.get(key.index()) {
            return Ok(*found);
        }
        let out = self.lower_ty_uncached(m, t, key)?;
        if matches!(
            m.types.kind(out),
            ms_mir::types::TyKind::Type(_)
                | ms_mir::types::TyKind::Alt(_)
                | ms_mir::types::TyKind::Opt(_)
                | ms_mir::types::TyKind::List(_)
                | ms_mir::types::TyKind::Obj(..)
        ) {
            // The checker type behind a MIR type, so cleanup can ask for its class: an
            // `Optional`, `List` or `Map` of a resource is one too.
            self.source_tys.set_if_absent(out.0 as usize, t.clone());
        }
        self.set_lowered(key, out);
        Ok(out)
    }

    fn set_lowered(&mut self, key: ms_check::api::tytable::TyId, ty: MTy) {
        if self.tycache.len() <= key.index() {
            self.tycache
                .resize(self.tys.len().max(key.index() + 1), None);
        }
        self.tycache[key.index()] = Some(ty);
    }

    fn lower_ty_uncached(
        &mut self,
        m: &mut Module,
        t: &ct::Ty,
        key: ms_check::api::tytable::TyId,
    ) -> Result<MTy, Error> {
        match t.kind {
            Kind::Function => {
                let mut params = Vec::new();
                for p in &t.params {
                    if p.mutable {
                        // A changed parameter travels as the address of a slot the callee takes
                        // the value from and puts the final value back into, as in a direct call.
                        params.push(MTy::PTR);
                        continue;
                    }
                    let pt = self.lower_ty(m, &p.ty)?;
                    // A parameter that may be omitted crosses a function value as an optional.
                    let lifted = t.is_lifted(p.name);
                    params.push(if lifted { m.types.opt(pt) } else { pt });
                }
                let ret = self.lower_ty(m, &t.result_ty())?;
                Ok(m.types.func(params, ret))
            }
            Kind::Native => self.lower_native_ty(m, t),
            Kind::Type if t.is(Builtin::Bytes) => Ok(MTy::BYTES),
            Kind::Alternative if t.is(Builtin::Optional) => {
                let inner = self.lower_ty(m, &t.args[0])?;
                Ok(m.types.opt(inner))
            }
            Kind::Type | Kind::Alternative if self.is_native_collection(t) => {
                self.lower_native_ty(m, t)
            }
            Kind::Type => {
                let (id, ty) = m.add_type(&t.display(self.syms).to_string(), Vec::new());
                m.type_defs[id.index()].native = if t.is(Builtin::Timestamp) {
                    Some(NativeType::Timestamp)
                } else if t.is(Builtin::Instant) {
                    Some(NativeType::Instant)
                } else if t.is(Builtin::Duration) {
                    Some(NativeType::Duration)
                } else {
                    None
                };
                m.type_defs[id.index()].indirect = t.is(Builtin::Error);
                self.set_lowered(key, ty);
                if t.opaque_module().is_some() {
                    self.opaque_tys.set_if_absent(ty.0 as usize, ());
                }
                let mut fields = Vec::new();
                for f in ct::fields(t) {
                    let ty = self.lower_ty(m, &f.ty)?;
                    fields.push((self.syms.str(f.name).to_string(), ty));
                }
                m.type_defs[id.index()].fields = fields;
                Ok(ty)
            }
            Kind::Alternative => {
                let (id, ty) = m.add_alt(&t.display(self.syms).to_string(), Vec::new());
                self.set_lowered(key, ty);
                if t.opaque_module().is_some() {
                    self.opaque_tys.set_if_absent(ty.0 as usize, ());
                }
                let mut cases = Vec::new();
                for c in ct::cases(t) {
                    let mut fields = Vec::new();
                    for f in &c.fields {
                        fields.push((self.syms.str(f.name).to_string(), self.lower_ty(m, &f.ty)?));
                    }
                    cases.push(CaseDef {
                        name: self.syms.str(c.name).to_string(),
                        fields,
                    });
                }
                m.alts[id.index()].cases = cases;
                if t.is(Builtin::Result) {
                    m.alts[id.index()].std = Std::Result;
                }
                Ok(ty)
            }
            Kind::Contract => {
                let id = ms_mir::types::IfaceId(m.ifaces.len() as u32);
                m.ifaces.push(IfaceDef {
                    name: t.display(self.syms).to_string(),
                    std: if t.is(Builtin::Comparable) {
                        Std::Comparable
                    } else if t.is(Builtin::Equal) {
                        Std::Equal
                    } else {
                        Std::None
                    },
                    close: None,
                    methods: Vec::new(),
                });
                let ty = m.types.iface(id);
                self.set_lowered(key, ty);
                self.contracts.insert(id, t.clone());
                let mut subst = ct::substitution(t);
                // `Self` in an operation is the interface value itself.
                subst.insert(ms_check::self_variable(self.syms, t.id).id, t.clone());
                let mut methods = Vec::new();
                if let Some(def) = &t.def {
                    let ops = def.operations.borrow().clone();
                    for op in ops {
                        // An operation with type parameters of its own is static dispatch only.
                        if op
                            .decl
                            .as_ref()
                            .and_then(|d| d.func())
                            .is_some_and(|f| !f.type_params.is_empty())
                        {
                            continue;
                        }
                        let self_params = op
                            .ty
                            .params
                            .iter()
                            .map(|p| p.ty.is(ct::Builtin::SelfType))
                            .collect();
                        let sig = ct::sub(&op.ty, &subst);
                        let vars = op_var_params(&op);
                        let mut params = Vec::new();
                        for (i, p) in sig.params.iter().enumerate() {
                            // A `var` parameter travels as the address of the caller's slot.
                            if vars.get(i).copied().unwrap_or(false) {
                                params.push(MTy::PTR);
                            } else {
                                params.push(self.lower_ty(m, &p.ty)?);
                            }
                        }
                        let ret = self.lower_ty(m, &sig.result_ty())?;
                        if self.syms.str(op.name) == "close" {
                            m.ifaces[id.index()].close = Some(methods.len() as u32);
                        }
                        methods.push(MethodSig {
                            name: self.syms.str(op.name).to_string(),
                            params,
                            ret,
                            self_params,
                        });
                    }
                }
                m.ifaces[id.index()].methods = methods;
                Ok(ty)
            }
            Kind::Primitive | Kind::Invalid | Kind::Inferred | Kind::Variable => {
                unreachable!("handled by lower_ty")
            }
        }
    }

    fn is_native_collection(&self, t: &ct::Ty) -> bool {
        t.is(Builtin::List) || t.is(Builtin::Map) || t.is(Builtin::Set)
    }

    fn lower_native_ty(&mut self, m: &mut Module, t: &ct::Ty) -> Result<MTy, Error> {
        if t.is(Builtin::List) {
            let e = self.lower_ty(m, &t.args[0])?;
            return Ok(m.types.list(e));
        }
        let native = match t.builtin {
            Some(Builtin::Map) => Some(Native::Map),
            Some(Builtin::Set) => Some(Native::Set),
            _ => None,
        };
        if let Some(native) = native {
            let mut args = Vec::new();
            for a in &t.args {
                args.push(self.lower_ty(m, a)?);
            }
            return Ok(m.types.native(native, args));
        }
        // Bytes is a growable byte buffer; the text and byte builders are owned values over one.
        if t.is(Builtin::Bytes) || ms_check::api::ownership::is_text_builder(self.syms, t) {
            return Ok(MTy::BYTES);
        }
        // `Decimal` is plain data in the runtime's `repr(C)` layout (`ms_rt::decimal::Dec`).
        if t.is(Builtin::Decimal) {
            let (id, ty) = m.add_type("Decimal", Vec::new());
            m.type_defs[id.index()].native = Some(NativeType::Decimal);
            m.type_defs[id.index()].fields = ["lo", "hi", "exp"]
                .iter()
                .map(|f| (f.to_string(), MTy::INT))
                .collect();
            return Ok(ty);
        }
        // Arbitrary-precision integers have no runtime yet; the type exists so interfaces
        // that mention one (`FileInfo.exact`) can be declared.
        if t.is(Builtin::BigInt) {
            return Ok(m.types.obj("BigInt", Vec::new()));
        }
        // Any other opaque runtime type is a reference-counted handle.
        Ok(m.types.obj(self.syms.str(t.name), Vec::new()))
    }
}

impl Cx {
    /// Whether `fact` holds for node `id` of module `file`.
    pub fn fact(
        &self,
        file: Name,
        id: ms_check::api::ast::NodeId,
        fact: ms_check::api::ownership::Fact,
    ) -> bool {
        self.ownership.node_facts.has(file, id, fact)
    }
}

/// Which parameters of an interface operation are declared `var`.
pub(crate) fn op_var_params(op: &ct::Operation) -> Vec<bool> {
    let Some(f) = op.decl.as_ref() else {
        return Vec::new();
    };
    let params = match (f.method(), f.func()) {
        (Some(m), _) => &m.func.params,
        (None, Some(func)) => &func.params,
        (None, None) => return Vec::new(),
    };
    params.iter().map(|p| p.mutable).collect()
}

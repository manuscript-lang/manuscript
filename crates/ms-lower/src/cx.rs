//! Whole-program lowering state: module queries, type mapping and function instances.

use crate::Error;
use ms_check::Program;
use ms_check::hir::{Callable, ModuleHir};
use ms_check::ownership::BorrowKind;
use ms_check::types::{self as ct, Builtin, Kind, Name, Subst};
use ms_mir::ir::{FuncId, Module};
use ms_mir::types::{CaseDef, IfaceDef, MethodSig, Ty as MTy};
use ms_mir::types::{Native, NativeRec};
use ms_syntax::NodeId;
use std::collections::HashMap;
use std::rc::Rc;

/// What an instance is requested with besides its type variables.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, Hash)]
pub struct Variant {
    /// The instance takes the parameters its body consumes owned.
    pub owned: bool,
    /// The module whose local implementations the instance's type variables use.
    pub evidence: Option<ms_check::types::Name>,
}

/// The key of a reserved instance: the callable, its type variables and its variant.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct InstKey {
    pub file: ms_check::types::Name,
    pub node: NodeId,
    pub subst: Vec<(ms_check::types::Name, String)>,
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
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
}

/// A bound native method waiting to be lowered; the closure holds the receiver.
pub struct BoundNativeJob {
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
    /// The native, `module/name`.
    pub native: String,
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
    pub expr: ms_syntax::ast::Expr,
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
pub struct Cx {
    /// Module queries by file.
    pub mods: HashMap<Name, Rc<ModuleHir>>,
    /// Callables by (module file, declaration or method node id).
    pub callables: HashMap<(Name, NodeId), Rc<Callable>>,
    /// MIR types by checker type key.
    pub tycache: HashMap<String, MTy>,
    /// Function instances by key.
    pub insts: HashMap<InstKey, FuncId>,
    /// Bodies waiting to be lowered.
    pub queue: Vec<Job>,
    /// Records and alternatives declared `opaque type`; their text form is the type name.
    pub opaque_tys: std::collections::HashSet<MTy>,
    /// Alternatives declared by the standard library.
    pub std_alts: std::collections::HashSet<usize>,
    /// Helper functions (formatting, equality, ...) by key.
    pub helpers: HashMap<String, FuncId>,
    /// Interface implementation tables built by lowering.
    pub vtables: HashMap<String, ms_mir::ir::VtableId>,
    /// The checker type of every lowered interface.
    pub contracts: HashMap<ms_mir::types::IfaceId, ct::Ty>,
    /// Every implementation method of the program.
    pub methods: Vec<ct::MethodRef>,
    /// The checker type behind each lowered record or alternative.
    pub source_tys: HashMap<MTy, ct::Ty>,
    /// The `.ms` methods of the native records, built once from the program's methods.
    pub native_ops: crate::nativerec::NativeOps,
    /// Types whose descriptor glue is registered, per implementation scope.
    pub glue_seen: std::collections::HashSet<(MTy, u32)>,
    /// Nominal types with an extension implemented outside their defining module.
    pub extended: std::collections::HashSet<Name>,
    /// The modules that scoped tables were built for; a scope number is the position plus one.
    pub scope_names: Vec<Name>,
    /// Parameters (receiver first) that functions hand back changed.
    pub mutated: std::collections::HashSet<crate::mutation::ParamKey>,
    /// The `make_fixture` factory and hooks type of each module with tests.
    pub fixtures: HashMap<Name, ms_check::TestFixture>,
    /// Bindings that borrow a place another binding owns, and how.
    pub borrows: Rc<HashMap<usize, BorrowKind>>,
    /// Resource bindings closed implicitly when their scope ends.
    pub implicit_closes: Rc<std::collections::HashSet<usize>>,
    /// Closing bindings the program also closes with an explicit `.close()` call.
    pub explicit_closes: Rc<std::collections::HashSet<usize>>,
    /// The name expressions that move a closed resource binding, by binding: the scope-end close
    /// runs only on the paths that never reach one.
    pub close_moves: Rc<HashMap<usize, std::collections::HashSet<ms_syntax::ast::NodeId>>>,
    /// Every move of a whole binding, by binding: the name expressions (or lambdas) that take
    /// its value out of the local.
    pub moves: Rc<HashMap<usize, std::collections::HashSet<ms_syntax::ast::NodeId>>>,
    /// The moved bindings some path keeps to the end of their scope: their local can be empty.
    pub conditional_moves: Rc<std::collections::HashSet<usize>>,
    /// Resource fields moved out of an owned binding, by binding and member node.
    pub resource_moves:
        Rc<HashMap<usize, HashMap<ms_syntax::ast::NodeId, Vec<ms_check::types::Name>>>>,
    /// Captures a non-escaping lambda only reads: the closure points at them instead of copying.
    pub borrowed_captures: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId, usize)>>,
    /// Parameters each callable consumes, by module file and node.
    pub consumes: Rc<HashMap<(Name, ms_syntax::ast::NodeId), Vec<bool>>>,
    /// Calls bound as a mutable borrow of a field path of their argument, by module file and node.
    pub getters: Rc<HashMap<(Name, ms_syntax::ast::NodeId), Vec<Name>>>,
    /// Callables whose result is a reference into their arguments, by module file and node.
    pub lenders: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId)>>,
    /// Callables whose result is an interface view of their arguments (`ret_view`).
    pub view_lenders: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId)>>,
    /// Wrappers of lent values built as `opt.view` / `alt.view`, by module file and node.
    pub view_wraps: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId)>>,
    /// Method values that stay local and borrow their receiver's place: the closure holds the
    /// receiver's address instead of a copy.
    pub bound_borrows: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId)>>,
    /// Name expressions moving an interface view out of the local holding it.
    pub view_moves: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId)>>,
    /// Lending calls whose result the caller owns because an argument is a temporary: the
    /// result is copied out before the temporary is dropped.
    pub owned_lends: Rc<
        std::collections::HashMap<(Name, ms_syntax::ast::NodeId), ms_check::ownership::OwnedLend>,
    >,
    /// Conditional and match expressions whose value is a reference on every arm.
    pub lent_matches: Rc<std::collections::HashSet<(Name, ms_syntax::ast::NodeId)>>,
    /// Which types are resources, for the closers of records and collections that hold them.
    pub classes: ms_check::ownership::Classifier,
}

impl Cx {
    /// The binding is a `var` borrow: it lowers as a path into its origin.
    pub fn exclusive(&self, uid: usize) -> bool {
        self.borrows.get(&uid) == Some(&BorrowKind::Exclusive)
    }

    /// The binding is a `let` borrow of a place: it may point into its origin instead of copying.
    pub fn shared(&self, uid: usize) -> bool {
        self.borrows.get(&uid) == Some(&BorrowKind::Shared)
    }

    /// Indexes every module of the program.
    pub fn new(program: &Program) -> Cx {
        let mut mods = HashMap::new();
        let mut callables = HashMap::new();
        for m in program.hir().modules() {
            for c in m.callables() {
                callables.insert((m.data.file, c.id()), Rc::new(c));
            }
            mods.insert(m.data.file, Rc::new(m));
        }
        let mutated = crate::mutation::infer_mutated(&mods, &callables);
        let native_ops = crate::nativerec::NativeOps::new(program, &callables);
        let extended = program
            .methods
            .iter()
            .filter(|m| m.local)
            .map(|m| m.receiver.id)
            .collect();
        Cx {
            extended,
            scope_names: Vec::new(),
            mods,
            callables,
            mutated,
            source_tys: HashMap::new(),
            native_ops,
            glue_seen: Default::default(),
            tycache: HashMap::new(),
            insts: HashMap::new(),
            queue: Vec::new(),
            opaque_tys: Default::default(),
            std_alts: Default::default(),
            helpers: HashMap::new(),
            vtables: HashMap::new(),
            contracts: HashMap::new(),
            methods: program.methods.clone(),
            fixtures: program.test_fixtures.clone(),
            borrows: program.borrows.clone(),
            implicit_closes: program.implicit_closes.clone(),
            explicit_closes: program.explicit_closes.clone(),
            close_moves: program.close_moves.clone(),
            moves: program.moves.clone(),
            conditional_moves: program.conditional_moves.clone(),
            resource_moves: program.resource_moves.clone(),
            borrowed_captures: program.borrowed_captures.clone(),
            consumes: program.consumes.clone(),
            getters: program.getter_borrows.clone(),
            lenders: program.lenders.clone(),
            view_lenders: program.view_lenders.clone(),
            view_wraps: program.view_wraps.clone(),
            bound_borrows: program.bound_borrows.clone(),
            view_moves: program.view_moves.clone(),
            owned_lends: program.owned_lends.clone(),
            lent_matches: program.lent_matches.clone(),
            classes: ms_check::ownership::Classifier::new(program),
        }
    }

    /// The module queries for `file`.
    pub fn module(&self, file: Name) -> Result<Rc<ModuleHir>, Error> {
        self.mods.get(&file).cloned().ok_or_else(|| {
            Error::new(format!(
                "unknown module {file} (have {:?})",
                self.mods.keys().map(|k| k.to_string()).collect::<Vec<_>>()
            ))
        })
    }

    /// Maps a concrete checker type to a MIR type.
    pub fn lower_ty(&mut self, m: &mut Module, t: &ct::Ty) -> Result<MTy, Error> {
        match t.kind {
            Kind::Primitive => {
                return match t.id.as_str() {
                    "Int" | "Int64" => Ok(MTy::INT),
                    "Int8" => Ok(MTy::INT8),
                    "Int16" => Ok(MTy::INT16),
                    "Int32" => Ok(MTy::INT32),
                    "UInt8" => Ok(MTy::UINT8),
                    "UInt16" => Ok(MTy::UINT16),
                    "UInt32" => Ok(MTy::UINT32),
                    "UInt64" => Ok(MTy::UINT64),
                    "Float" | "Float64" => Ok(MTy::FLOAT),
                    "Float32" => Ok(MTy::FLOAT32),
                    "Bool" => Ok(MTy::BOOL),
                    "String" => Ok(MTy::STR),
                    "Unit" | "Never" => Ok(MTy::UNIT),
                    other => Err(Error::new(format!("unsupported primitive type {other}"))),
                };
            }
            Kind::Invalid | Kind::Inferred => {
                return Err(Error::new(format!("unsupported primitive type {}", t.id)));
            }
            Kind::Variable => {
                return Err(Error::new(format!(
                    "unsubstituted type variable {}",
                    t.name
                )));
            }
            _ => {}
        }
        let key = ct::lowering_key(t);
        if let Some(found) = self.tycache.get(&key) {
            return Ok(*found);
        }
        let out = self.lower_ty_uncached(m, t, &key)?;
        if matches!(
            m.types.kind(out),
            ms_mir::types::TyKind::Rec(_)
                | ms_mir::types::TyKind::Alt(_)
                | ms_mir::types::TyKind::Opt(_)
                | ms_mir::types::TyKind::List(_)
                | ms_mir::types::TyKind::Obj(..)
        ) {
            // The checker type behind a MIR type, so cleanup can ask for its class: an
            // `Optional`, `List` or `Map` of a resource is one too.
            self.source_tys.entry(out).or_insert_with(|| t.clone());
        }
        self.tycache.insert(key, out);
        Ok(out)
    }

    fn lower_ty_uncached(&mut self, m: &mut Module, t: &ct::Ty, key: &str) -> Result<MTy, Error> {
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
            Kind::Record if t.is(Builtin::Bytes) => Ok(MTy::BYTES),
            Kind::Alternative if t.is(Builtin::Optional) => {
                let inner = self.lower_ty(m, &t.args[0])?;
                Ok(m.types.opt(inner))
            }
            Kind::Record | Kind::Alternative if self.is_native_collection(t) => {
                self.lower_native_ty(m, t)
            }
            Kind::Record => {
                let (id, ty) = m.add_record(&t.to_string(), Vec::new());
                m.records[id.index()].native = if t.is_time("Timestamp") {
                    Some(NativeRec::Timestamp)
                } else if t.is_time("Instant") {
                    Some(NativeRec::Instant)
                } else if t.is_time("Duration") {
                    Some(NativeRec::Duration)
                } else {
                    None
                };
                self.tycache.insert(key.to_string(), ty);
                if t.opaque_module().is_some() {
                    self.opaque_tys.insert(ty);
                }
                let mut fields = Vec::new();
                for f in ct::fields(t) {
                    let ty = self.lower_ty(m, &f.ty)?;
                    fields.push((f.name.to_string(), ty));
                }
                m.records[id.index()].fields = fields;
                Ok(ty)
            }
            Kind::Alternative => {
                let (id, ty) = m.add_alt(&t.to_string(), Vec::new());
                self.tycache.insert(key.to_string(), ty);
                if t.opaque_module().is_some() {
                    self.opaque_tys.insert(ty);
                }
                if t.symbol()
                    .is_some_and(|s| s.module.as_str().starts_with("@std/"))
                {
                    self.std_alts.insert(id.index());
                }
                let mut cases = Vec::new();
                for c in ct::cases(t) {
                    let mut fields = Vec::new();
                    for f in &c.fields {
                        fields.push((f.name.to_string(), self.lower_ty(m, &f.ty)?));
                    }
                    cases.push(CaseDef {
                        name: c.name.to_string(),
                        fields,
                    });
                }
                m.alts[id.index()].cases = cases;
                Ok(ty)
            }
            Kind::Contract => {
                let id = ms_mir::types::IfaceId(m.ifaces.len() as u32);
                m.ifaces.push(IfaceDef {
                    name: t.to_string(),
                    methods: Vec::new(),
                });
                let ty = m.types.iface(id);
                self.tycache.insert(key.to_string(), ty);
                self.contracts.insert(id, t.clone());
                let mut subst = ct::substitution(t);
                // `Self` in an operation is the interface value itself.
                subst.insert(ms_check::self_variable(t.id).id, t.clone());
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
                            .map(|p| p.ty.id.as_str().ends_with("/Self"))
                            .collect();
                        let sig = ct::sub(&op.ty, &subst);
                        let mut params = Vec::new();
                        for p in &sig.params {
                            params.push(self.lower_ty(m, &p.ty)?);
                        }
                        let ret = self.lower_ty(m, &sig.result_ty())?;
                        methods.push(MethodSig {
                            name: op.name.to_string(),
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
        if t.is(Builtin::Bytes) || ms_check::effects::is_text_builder(t) {
            return Ok(MTy::BYTES);
        }
        // Plain-data natives share the runtime's `repr(C)` layout.
        let pod: &[(&str, &[&str])] = &[("Decimal", &["lo", "hi", "exp"])];
        for (name, fields) in pod {
            if t.is_std(name) {
                let (id, ty) = m.add_record(name, Vec::new());
                m.records[id.index()].native = Some(NativeRec::Decimal);
                m.records[id.index()].fields =
                    fields.iter().map(|f| (f.to_string(), MTy::INT)).collect();
                return Ok(ty);
            }
        }
        // Arbitrary-precision integers have no runtime yet; the type exists so interfaces
        // that mention one (`FileInfo.exact`) can be declared.
        if t.is(Builtin::BigInt) {
            return Ok(m.types.obj("BigInt", Vec::new()));
        }
        // Any other opaque runtime type is a reference-counted handle.
        Ok(m.types.obj(t.name.as_str(), Vec::new()))
    }
}

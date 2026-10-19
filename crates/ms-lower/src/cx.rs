//! Whole-program lowering state: module queries, type mapping and function instances.

use crate::Error;
use ms_check::Program;
use ms_check::hir::{Callable, ModuleHir};
use ms_check::types::{self as ct, Kind, Name, Subst};
use ms_mir::ir::{FuncId, Module};
use ms_mir::types::{CaseDef, IfaceDef, MethodSig, Ty as MTy};
use ms_syntax::NodeId;
use std::collections::HashMap;
use std::rc::Rc;

/// What a reserved function is made of.
pub enum JobKind {
    /// A source callable under a substitution.
    Source {
        /// What to lower.
        callable: Rc<Callable>,
        /// Type variables of the instance.
        subst: Subst,
    },
    /// The text form of a value of the MIR type.
    Format(MTy, bool),
    /// A lambda body under the instance substitution.
    Lambda(Rc<LambdaJob>),
    /// Structural equality of two values of the MIR type.
    Equal(MTy),
}

/// A lambda waiting to be lowered.
pub struct LambdaJob {
    /// The lambda expression.
    pub expr: ms_syntax::ast::Expr,
    /// Module the lambda is written in.
    pub hir: Rc<ModuleHir>,
    /// Type variables of the enclosing instance.
    pub subst: Subst,
    /// Captured variables in closure-object order.
    pub captures: Vec<ct::BindingRef>,
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
    pub insts: HashMap<String, FuncId>,
    /// Bodies waiting to be lowered.
    pub queue: Vec<Job>,
    /// Helper functions (formatting, equality, ...) by key.
    pub helpers: HashMap<String, FuncId>,
    /// Interface implementation tables built by lowering.
    pub vtables: HashMap<String, ms_mir::ir::VtableId>,
    /// Every implementation method of the program.
    pub methods: Vec<ct::MethodRef>,
}

impl Cx {
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
        Cx {
            mods,
            callables,
            tycache: HashMap::new(),
            insts: HashMap::new(),
            queue: Vec::new(),
            helpers: HashMap::new(),
            vtables: HashMap::new(),
            methods: program.methods.clone(),
        }
    }

    /// The module queries for `file`.
    pub fn module(&self, file: Name) -> Result<Rc<ModuleHir>, Error> {
        self.mods
            .get(&file)
            .cloned()
            .ok_or_else(|| Error::new(format!("unknown module {file}")))
    }

    /// Maps a concrete checker type to a MIR type.
    pub fn lower_ty(&mut self, m: &mut Module, t: &ct::Ty) -> Result<MTy, Error> {
        match t.kind {
            Kind::Primitive => {
                return match t.id.as_str() {
                    "Int" => Ok(MTy::INT),
                    "Float" => Ok(MTy::FLOAT),
                    "Bool" => Ok(MTy::BOOL),
                    "String" => Ok(MTy::STR),
                    "Unit" | "Never" => Ok(MTy::UNIT),
                    other => Err(Error::new(format!("unsupported primitive type {other}"))),
                };
            }
            Kind::Variable => {
                return Err(Error::new(format!(
                    "unsubstituted type variable {}",
                    t.name
                )));
            }
            _ => {}
        }
        let key = ct::type_key(t);
        if let Some(found) = self.tycache.get(&key) {
            return Ok(*found);
        }
        let out = self.lower_ty_uncached(m, t, &key)?;
        self.tycache.insert(key, out);
        Ok(out)
    }

    fn lower_ty_uncached(&mut self, m: &mut Module, t: &ct::Ty, key: &str) -> Result<MTy, Error> {
        match t.kind {
            Kind::Function => {
                let mut params = Vec::new();
                for p in &t.params {
                    params.push(self.lower_ty(m, &p.ty)?);
                }
                let ret = self.lower_ty(m, &t.result_ty())?;
                Ok(m.types.func(params, ret))
            }
            Kind::Native => self.lower_native_ty(m, t),
            Kind::Record if t.is_std("Bytes") => Ok(MTy::BYTES),
            Kind::Alternative if t.is_std("Optional") => {
                let inner = self.lower_ty(m, &t.args[0])?;
                Ok(m.types.opt(inner))
            }
            Kind::Record | Kind::Alternative if self.is_native_collection(t) => {
                self.lower_native_ty(m, t)
            }
            Kind::Record => {
                let (id, ty) = m.add_record(&t.to_string(), Vec::new());
                self.tycache.insert(key.to_string(), ty);
                let mut fields = Vec::new();
                for f in ct::fields(t) {
                    fields.push((f.name.to_string(), self.lower_ty(m, &f.ty)?));
                }
                m.records[id.index()].fields = fields;
                Ok(ty)
            }
            Kind::Alternative => {
                let (id, ty) = m.add_alt(&t.to_string(), Vec::new());
                self.tycache.insert(key.to_string(), ty);
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
                let subst = ct::substitution(t);
                let mut methods = Vec::new();
                if let Some(def) = &t.def {
                    let ops = def.operations.borrow().clone();
                    for op in ops {
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
                        });
                    }
                }
                m.ifaces[id.index()].methods = methods;
                Ok(ty)
            }
            Kind::Primitive | Kind::Variable => unreachable!("handled by lower_ty"),
        }
    }

    fn is_native_collection(&self, t: &ct::Ty) -> bool {
        t.is_std("List") || t.is_std("Map") || t.is_std("Set")
    }

    fn lower_native_ty(&mut self, m: &mut Module, t: &ct::Ty) -> Result<MTy, Error> {
        if t.is_std("List") {
            let e = self.lower_ty(m, &t.args[0])?;
            return Ok(m.types.list(e));
        }
        if t.is_std("Map") || t.is_std("Set") {
            let mut args = Vec::new();
            for a in &t.args {
                args.push(self.lower_ty(m, a)?);
            }
            let name = if t.is_std("Map") { "Map" } else { "Set" };
            return Ok(m.types.obj(name, args));
        }
        // Builders are growable byte buffers.
        if t.is_std("Bytes") || t.is_std("StringBuilder") || t.is_std("BytesBuilder") {
            return Ok(MTy::BYTES);
        }
        Err(Error::new(format!("unsupported native type {t}")))
    }
}

//! The checker state and the module-level passes.

use crate::stdlib::{self, StdResult};
use crate::syntax::*;
use crate::types::*;
use crate::types::{Case, Param};
use ms_syntax::ast::*;
use ms_syntax::{Diagnostic, Phase, Pos};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};

/// Source of `Binding::uid`. Process-wide, because the standard library is checked by its own
/// checker and its bindings share the lowering's tables with the program's.
static BINDING_SERIAL: AtomicUsize = AtomicUsize::new(0);

/// Lexical scope of local bindings and type variables.
pub struct Scope {
    /// Enclosing scope.
    pub parent: Option<Rc<Scope>>,
    /// Local bindings.
    pub bindings: RefCell<HashMap<Name, BindingRef>>,
    /// Type variables.
    pub types: RefCell<HashMap<Name, Ty>>,
}

impl Scope {
    /// A new scope.
    pub fn new(parent: Option<Rc<Scope>>) -> Rc<Scope> {
        Rc::new(Scope {
            parent,
            bindings: RefCell::new(HashMap::new()),
            types: RefCell::new(HashMap::new()),
        })
    }

    /// Looks a binding up through enclosing scopes.
    pub fn binding(&self, name: Name) -> Option<BindingRef> {
        if let Some(b) = self.bindings.borrow().get(&name) {
            return Some(b.clone());
        }
        let mut s = self.parent.clone();
        while let Some(sc) = s {
            if let Some(b) = sc.bindings.borrow().get(&name) {
                return Some(b.clone());
            }
            s = sc.parent.clone();
        }
        None
    }

    /// Looks a type variable up; a binding of the same name hides it.
    pub fn typ(&self, name: Name) -> Option<Ty> {
        if self.bindings.borrow().contains_key(&name) {
            return None;
        }
        if let Some(t) = self.types.borrow().get(&name) {
            return Some(t.clone());
        }
        let mut s = self.parent.clone();
        while let Some(sc) = s {
            if sc.bindings.borrow().contains_key(&name) {
                return None;
            }
            if let Some(t) = sc.types.borrow().get(&name) {
                return Some(t.clone());
            }
            s = sc.parent.clone();
        }
        None
    }
}

/// The module-level symbol table of one module.
pub type Names = Rc<RefCell<HashMap<Name, SymRef>>>;

/// Options for one check.
#[derive(Default, Clone)]
pub struct CheckOptions {
    /// Capture the scope at name expressions with this text (editor queries).
    pub scope_marker: Option<String>,
    /// The bundled standard source module being checked for the shared cache.
    pub bundled: Option<Name>,
}

/// The concrete fixture injected into tests of a module.
#[derive(Clone)]
pub struct TestFixture {
    /// The `make_fixture` factory.
    pub factory: SymRef,
    /// Concrete fixture type.
    pub ty: Ty,
    /// The standard `TestHooks` contract.
    pub hooks: Ty,
}

/// The result of checking: modules with facts, symbols, methods, diagnostics.
#[derive(Default)]
pub struct Program {
    /// Fixtures per module file.
    pub test_fixtures: HashMap<Name, TestFixture>,
    /// Conservative potential effects by callable id.
    pub effects: HashMap<Name, Vec<&'static str>>,
    /// Modules in dependency order (reachable bundled source modules first).
    pub modules: Vec<ModRef>,
    /// Module-level symbols per module file.
    pub symbols: HashMap<Name, Names>,
    /// All implementation methods.
    pub methods: Vec<MethodRef>,
    /// Diagnostics in report order.
    pub diagnostics: Vec<Diagnostic>,
    /// Identities handed out while checking.
    pub serial: usize,
    /// Bindings that borrow a place another binding owns, and how, for lowering. Filled when
    /// the ownership pass ran (every program that type checks).
    pub borrows: Rc<HashMap<usize, crate::ownership::BorrowKind>>,
    /// Resource bindings closed implicitly when their scope ends. Filled together with `borrows`.
    pub implicit_closes: Rc<HashSet<usize>>,
    /// The name expressions that move a closed resource binding, by binding.
    pub close_moves: Rc<HashMap<usize, HashSet<NodeId>>>,
    /// Payload bindings of a consumed match scrutinee that some path moves out.
    pub moved_payloads: Rc<HashSet<usize>>,
    /// Calls bound with `var` as a mutable borrow of a field path of their argument, by module
    /// file and node, with the fields. Filled together with `borrows`.
    pub getter_borrows: Rc<HashMap<(Name, NodeId), Vec<Name>>>,
    /// `ref` functions that return a borrow on every path, by module file and node, for lowering.
    /// Filled together with `borrows`.
    pub lenders: Rc<HashSet<(Name, NodeId)>>,
    /// Captures a non-escaping lambda only reads, by module file, lambda node and binding
    /// identity. Filled together with `borrows`.
    pub borrowed_captures: Rc<HashSet<(Name, NodeId, usize)>>,
    /// Parameters each callable consumes (moves, stores or returns), by module file and node, for
    /// lowering. Filled together with `borrows`; only callables with a consumed parameter appear.
    pub consumes: Rc<std::collections::HashMap<(Name, NodeId), Vec<bool>>>,
}

/// A body-check result retained from an inference probe.
#[derive(Clone)]
pub struct CheckedArgument {
    /// The probed fact.
    pub info: Option<Info>,
    /// Diagnostics the probe produced.
    pub diagnostics: Vec<Diagnostic>,
}

/// Collected callback returns (`callbackReturns`).
#[derive(Default)]
pub struct CallbackReturns {
    /// The one exact return type.
    pub ty: Option<Ty>,
    /// Expected result context.
    pub context: Option<Ty>,
    /// A return whose type is not yet known.
    pub unresolved: bool,
    /// The result depends on later context.
    pub context_dependent: bool,
}

/// A default-bound check deferred until implementations are bound.
pub struct DeferredBound {
    /// Default type.
    pub resolved: Ty,
    /// Bound it must satisfy.
    pub bound: Ty,
    /// Where to report.
    pub pos: Pos,
    /// File of the declaring module.
    pub module: ModRef,
}

/// Resolves local imports to canonical module keys: `(importing file, import
/// node id) -> target module file`.
#[derive(Default, Clone)]
pub struct ImportMap(pub HashMap<(Name, NodeId), Name>);

impl ImportMap {
    /// Records an import resolution.
    pub fn insert(&mut self, file: Name, id: NodeId, target: Name) {
        self.0.insert((file, id), target);
    }
    /// Looks an import up.
    pub fn get(&self, file: Name, id: NodeId) -> Option<Name> {
        self.0.get(&(file, id)).copied()
    }
}

/// The checker.
pub struct Checker {
    /// Where the next checked expression is used, e.g. "argument 'a' of f".
    pub(crate) mismatch_context: Option<String>,
    pub(crate) scope_marker: Option<String>,
    pub(crate) standard_declarations: bool,
    pub(crate) deferred_default_bounds: Vec<DeferredBound>,
    pub(crate) id_scope: String,
    /// Mutually importing bundled source modules checked together.
    pub(crate) group: Vec<ModRef>,
    pub(crate) p: Program,
    /// Candidate positions in declaration order; type arguments are matched at use.
    pub(crate) methods_by_receiver: HashMap<Name, Vec<usize>>,
    pub(crate) methods_by_name: HashMap<(Name, Name), Vec<usize>>,
    pub(crate) module: Option<ModRef>,
    pub(crate) names: Names,
    pub(crate) scope: Rc<Scope>,
    pub(crate) result: Option<Ty>,
    pub(crate) return_inference: Option<CallbackReturns>,
    pub(crate) inference_variables: VarSet,
    pub(crate) checked_arguments: Option<HashMap<NodeId, CheckedArgument>>,
    /// The member expression that is a call's callee, with the call's argument count.
    pub(crate) call_arity: Option<(NodeId, usize)>,
    pub(crate) function: usize,
    pub(crate) serial: usize,
    pub(crate) loops: usize,
    /// `(function, place)` of each `lock` guard that is still held.
    pub(crate) held_locks: Vec<(usize, String, Name)>,
    pub(crate) test_function: usize,
    pub(crate) rejected_names: HashSet<Name>,
    pub(crate) unknown_type: bool,
    pub(crate) unresolved_constructors: HashSet<Pos>,
    /// Failed-bound messages reported while resolving written types, so the later
    /// declaration well-formedness pass does not restate them at the declaration.
    pub(crate) reported_bounds: HashSet<String>,
    pub(crate) in_declaration_checks: bool,
    pub(crate) label_mismatch: bool,
    /// Arguments whose generic-inference conflict is already reported, so the final argument check stays quiet.
    pub(crate) conflicted_arguments: HashSet<ms_syntax::ast::NodeId>,
    pub(crate) call_name: String,
    pub(crate) call_pos: Option<Pos>,
    pub(crate) captures: HashMap<usize, HashMap<usize, BindingRef>>,
    pub(crate) constants_visiting: HashSet<usize>,
    pub(crate) cycle_reported: HashSet<usize>,
    pub(crate) imports: ImportMap,
}

/// Maximum identity serial reservation per standard module check.
use crate::stdlib::PRIMITIVE_NAMES;

impl Checker {
    /// A fresh checker.
    pub fn new(options: &CheckOptions) -> Checker {
        Checker {
            mismatch_context: None,
            scope_marker: options.scope_marker.clone(),
            standard_declarations: false,
            deferred_default_bounds: Vec::new(),
            id_scope: String::new(),
            group: Vec::new(),
            p: Program::default(),
            methods_by_receiver: HashMap::new(),
            methods_by_name: HashMap::new(),
            module: None,
            names: Rc::new(RefCell::new(HashMap::new())),
            scope: Scope::new(None),
            result: None,
            return_inference: None,
            inference_variables: VarSet::new(),
            checked_arguments: None,
            call_arity: None,
            function: 0,
            serial: 0,
            loops: 0,
            held_locks: Vec::new(),
            test_function: 0,
            rejected_names: HashSet::new(),
            unknown_type: false,
            unresolved_constructors: HashSet::new(),
            reported_bounds: HashSet::new(),
            in_declaration_checks: false,
            label_mismatch: false,
            conflicted_arguments: HashSet::new(),
            call_name: String::new(),
            call_pos: None,
            captures: HashMap::new(),
            constants_visiting: HashSet::new(),
            cycle_reported: HashSet::new(),
            imports: ImportMap::default(),
        }
    }

    /// The current module (panics outside a module check).
    pub(crate) fn m(&self) -> ModRef {
        self.module.clone().expect("module")
    }

    /// The current module file, or empty.
    pub(crate) fn current_file(&self) -> Name {
        self.module
            .as_ref()
            .map(|m| m.file)
            .unwrap_or_else(|| n(""))
    }

    /// Hands out a unique identity.
    pub(crate) fn unique(&mut self, prefix: &str) -> Name {
        self.serial += 1;
        let mut s = String::new();
        s.push_str(&self.id_scope);
        if self.standard_declarations {
            s.push_str("standard_");
        }
        s.push_str(prefix);
        s.push_str(&self.serial.to_string());
        n(&s)
    }

    // ------------------------------------------------------------ diagnostics

    fn import_reported(&self, name: &str, pos: Pos) -> bool {
        let hint = format!("; add: import {name} from ");
        let file = self.current_file();
        let _ = pos;
        self.p
            .diagnostics
            .iter()
            .any(|d| d.file.as_ref() == file.as_str() && d.message.contains(&hint))
    }

    /// Reports a diagnostic, applying the checker's suppression rules.
    pub(crate) fn error(&mut self, pos: Pos, phase: Phase, message: impl Into<String>) {
        let message: String = message.into();
        let file = self.current_file();
        self.error_in(file, pos, phase, message);
    }

    /// Reports a diagnostic in an explicit file.
    pub(crate) fn error_in(&mut self, file: Name, pos: Pos, phase: Phase, message: String) {
        if phase == Phase::Resolution
            && message.starts_with("Decimal literal requires")
            && self.import_reported("Decimal", pos)
        {
            return;
        }
        if let Some(m) = &self.module {
            for span in &m.recovered {
                if in_span(pos.offset, span) {
                    return;
                }
            }
            if phase == Phase::Resolution {
                for name in &m.omitted {
                    if message == format!("unknown binding {name}")
                        || message.starts_with(&format!("unknown binding {name};"))
                        || message.starts_with(&format!("unknown type {name};"))
                        || message == format!("unknown type {name}")
                    {
                        return;
                    }
                }
            }
        }
        if self.unknown_type && phase != Phase::Resolution && message.contains("<invalid>") {
            return;
        }
        self.p.diagnostics.push(Diagnostic {
            file: file.as_str().into(),
            pos,
            phase,
            message,
            end: None,
            fix: None,
        });
    }

    /// A type-phase diagnostic.
    pub(crate) fn type_error(&mut self, pos: Pos, message: impl Into<String>) {
        self.error(pos, Phase::Type, message);
    }

    /// Reports `what` when `t` is an `opaque type` declared in another file; true when it did.
    pub(crate) fn opaque_denied(&mut self, pos: Pos, t: &Ty, what: &str) -> bool {
        let Some(module) = t.opaque_module().filter(|m| *m != self.current_file()) else {
            return false;
        };
        self.type_error(
            pos,
            format!("{t} is opaque outside {module}: {what}; use the functions {module} exports"),
        );
        true
    }

    /// A resolution-phase diagnostic.
    pub(crate) fn res_error(&mut self, pos: Pos, message: impl Into<String>) {
        self.error(pos, Phase::Resolution, message);
    }

    pub(crate) fn module_position(&self) -> Pos {
        Pos::new(0, 1, 1)
    }

    // ---------------------------------------------------------------- symbols

    pub(crate) fn sym(&self, name: Name) -> Option<SymRef> {
        self.names.borrow().get(&name).cloned()
    }

    /// A name that resolves to neither a binding nor a symbol.
    pub(crate) fn unbound(&self, name: Name) -> bool {
        self.scope.binding(name).is_none() && self.names.borrow().get(&name).is_none()
    }

    pub(crate) fn add_symbol(&mut self, name: Name, s: SymRef, pos: Pos) {
        let existing = self.sym(name);
        if let Some(e) = &existing
            && stdlib::is_prelude_symbol(e)
            && !stdlib::is_prelude_symbol(&s)
            && e.module != self.current_file()
        {
            self.res_error(
                    pos,
                    format!(
                        "declaration {name} reuses a prelude name; rename it, because {name} always refers to the standard declaration"
                    ),
                );
            self.rejected_names.insert(name);
            return;
        }
        if existing.is_some() {
            self.res_error(
                pos,
                format!(
                    "duplicate or intrinsic name {name}; this name is already declared, imported, or built in, so rename one of them"
                ),
            );
            self.rejected_names.insert(name);
            return;
        }
        self.names.borrow_mut().insert(name, s);
    }

    /// Makes `Self` available while an interface's operations are resolved: the implementing
    /// type, which an implementation or a call replaces with its receiver.
    pub(crate) fn declare_self(&mut self, owner: &Ty) {
        if owner.kind == Kind::Contract {
            self.scope
                .types
                .borrow_mut()
                .insert(n("Self"), self_variable(owner.id));
        }
    }

    /// `Self` is limited to whole parameter and result types, the positions where a call can
    /// substitute the implementing type.
    pub(crate) fn check_self_use(&mut self, op: &Ty, pos: Pos) {
        fn mentions(t: &Ty) -> bool {
            t.id.as_str().ends_with("/Self")
                || t.args.iter().any(mentions)
                || t.params.iter().any(|p| mentions(&p.ty))
                || t.result.as_ref().is_some_and(mentions)
        }
        let misplaced = op
            .params
            .iter()
            .any(|p| !p.ty.id.as_str().ends_with("/Self") && mentions(&p.ty))
            || op
                .result
                .as_ref()
                .is_some_and(|r| !r.id.as_str().ends_with("/Self") && mentions(r));
        if misplaced {
            self.type_error(
                pos,
                "Self can only be a whole parameter or result type of an interface operation; write 'other: Self', not 'List[Self]'",
            );
        }
    }

    /// Declares the type parameters of an interface or native operation in the current scope and
    /// records them as the operation's own variables (`owner/name`).
    pub(crate) fn operation_variables(&mut self, owner: Name, method: &ms_syntax::ast::Method) {
        let mut variables: Vec<Ty> = Vec::new();
        for param in &method.func.type_params {
            if self.scope.types.borrow().contains_key(&param.name) {
                self.type_error(
                    param.pos,
                    format!(
                        "type parameter {} shadows a type parameter of the receiver; choose a different name",
                        param.name
                    ),
                );
            }
            let v: Ty = Rc::new(Type::new(
                param.name,
                n(&format!("{owner}/{}/{}", method.func.name, param.name)),
                Kind::Variable,
            ));
            variables.push(v.clone());
            self.scope.types.borrow_mut().insert(param.name, v);
        }
        for (i, param) in method.func.type_params.iter().enumerate() {
            for bound in &param.bounds {
                let t = self.resolve(Some(bound));
                variables[i].bounds.borrow_mut().push(t);
            }
        }
        self.type_defaults(&method.func.type_params, &variables);
        stdlib::set_operation_variables(format!("{owner}/{}", method.func.name), variables);
    }

    pub(crate) fn variable_scope(&self, vars: &[Ty]) -> Rc<Scope> {
        let s = Scope::new(None);
        for v in vars {
            s.types.borrow_mut().insert(v.name, v.clone());
        }
        s
    }

    // ----------------------------------------------------------------- driver

    /// Runs the full check over modules in dependency order. Bundled source
    /// modules the input reaches are added first.
    pub(crate) fn check_modules(mut self, modules: Vec<ModRef>, bundled: Option<Name>) -> Program {
        let (modules, dependency_diagnostics) = stdlib::source_standard_dependencies(modules);
        self.p.diagnostics = dependency_diagnostics;
        for module in &modules {
            for d in &module.inherent {
                self.p.diagnostics.push(d.clone());
            }
        }
        if !self.p.diagnostics.is_empty() {
            self.p.modules = modules;
            return self.p;
        }
        for method in stdlib::standard_implementations() {
            self.add_method(method);
        }
        let mut checked: Vec<ModRef> = Vec::new();
        for module in &modules {
            if !self.group.is_empty() && self.group.iter().any(|g| g.file == module.file) {
                continue;
            }
            if stdlib::is_source_module(module) && Some(module.file) != bundled {
                self.adopt_checked(module, bundled.is_some());
                continue;
            }
            self.check_module(module);
            checked.push(module.clone());
        }
        if !self.group.is_empty() {
            let group = self.group.clone();
            self.check_group(&group);
            checked.extend(group);
        }
        self.p.modules = modules;
        crate::passes::finish_modules(&checked);
        self.finite_type_applications();
        self.finite_applications();
        self.p.diagnostics = unique_diagnostics(std::mem::take(&mut self.p.diagnostics));
        if self.p.diagnostics.is_empty() {
            self.effect_summaries();
        }
        self.p.serial = self.serial;
        self.p
    }

    fn adopt_checked(&mut self, module: &ModRef, held: bool) {
        let r: Rc<StdResult> = if held {
            stdlib::done(module.file).expect("dependency checked")
        } else {
            stdlib::ensure_source(module)
        };
        self.p.symbols.insert(module.file, r.symbols.clone());
        for method in &r.methods {
            self.add_method(method.clone());
        }
    }

    /// Declaration passes for one module, in order.
    pub(crate) fn check_module(&mut self, module: &ModRef) {
        self.module = Some(module.clone());
        self.names = Rc::new(RefCell::new(HashMap::new()));
        self.p.symbols.insert(module.file, self.names.clone());
        self.scope = Scope::new(None);
        for name in PRIMITIVE_NAMES {
            let nm = n(name);
            let s = Rc::new(Sym {
                name: nm,
                id: n(primitive_id(name)),
                kind: SymKind::Type,
                module: n(""),
                native: n(""),
                export: true,
                ty: RefCell::new(Some(primitive(primitive_id(name)))),
                variables: RefCell::new(Vec::new()),
                decl: None,
            });
            self.names.borrow_mut().insert(nm, s);
        }
        self.add_standard_prelude();
        self.import_symbols(module);
        self.declare_symbols(module);
        self.declare_type_variables(module);
        self.resolve_signatures(module);
        self.check_constant_cycles(module);
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_)) {
                self.implementation(d);
            }
        }
        self.check_test_fixture(module);
        self.check_defaults(module);
        self.check_bodies(module);
        self.declaration_checks(module);
    }

    fn enter_module(&mut self, module: &ModRef) {
        self.module = Some(module.clone());
        self.names = self.p.symbols[&module.file].clone();
        self.scope = Scope::new(None);
    }

    /// Checks mutually importing bundled modules in lockstep: every module declares its
    /// symbols before any module imports, resolves signatures or checks bodies.
    fn check_group(&mut self, group: &[ModRef]) {
        for module in group {
            self.module = Some(module.clone());
            self.names = Rc::new(RefCell::new(HashMap::new()));
            self.p.symbols.insert(module.file, self.names.clone());
            self.scope = Scope::new(None);
            for name in PRIMITIVE_NAMES {
                let nm = n(name);
                let s = Rc::new(Sym {
                    name: nm,
                    id: n(primitive_id(name)),
                    kind: SymKind::Type,
                    module: n(""),
                    native: n(""),
                    export: true,
                    ty: RefCell::new(Some(primitive(primitive_id(name)))),
                    variables: RefCell::new(Vec::new()),
                    decl: None,
                });
                self.names.borrow_mut().insert(nm, s);
            }
            self.add_standard_prelude();
            self.declare_symbols(module);
        }
        for module in group {
            self.enter_module(module);
            self.import_symbols(module);
        }
        for module in group {
            self.enter_module(module);
            self.declare_type_variables(module);
        }
        for module in group {
            self.enter_module(module);
            self.resolve_signatures(module);
            self.check_constant_cycles(module);
        }
        for module in group {
            self.enter_module(module);
            for d in &module.decls {
                if matches!(d.decl().kind, DeclKind::Impl(_)) {
                    self.implementation(d);
                }
            }
        }
        for module in group {
            self.enter_module(module);
            self.check_test_fixture(module);
            self.check_defaults(module);
            self.check_bodies(module);
        }
        for module in group {
            self.enter_module(module);
            self.declaration_checks(module);
        }
    }

    fn import_symbols(&mut self, module: &ModRef) {
        for item in &module.imports {
            let path = item.path.as_ref();
            let found: Option<SymRef> = if path.starts_with("@std/") {
                let pn = n(path);
                if stdlib::standard_source_module(pn).is_some() {
                    let f = self
                        .p
                        .symbols
                        .get(&pn)
                        .and_then(|names| names.borrow().get(&item.name).cloned());
                    f.filter(|f| f.module == pn)
                } else {
                    stdlib::standard_module_symbol(pn, item.name)
                }
            } else {
                self.imports
                    .get(module.file, item.id)
                    .and_then(|target| self.p.symbols.get(&target).cloned())
                    .and_then(|names| names.borrow().get(&item.name).cloned())
            };
            let usable = found.as_ref().filter(|f| f.export).cloned();
            let Some(found) = usable else {
                let end = Pos::new(
                    item.name_pos.offset + item.name.len() as u32,
                    item.name_pos.line,
                    item.name_pos.column + item.name.len() as u32,
                );
                let message = self.export_message(item);
                self.p.diagnostics.push(Diagnostic {
                    file: module.file.as_str().into(),
                    pos: item.name_pos,
                    phase: Phase::Resolution,
                    message,
                    end: Some(end),
                    fix: None,
                });
                continue;
            };
            if stdlib::is_prelude_symbol(&found) {
                self.redundant_prelude_import(module, item);
            }
            self.add_symbol(item.name, found, item.name_pos);
        }
    }

    fn declare_symbols(&mut self, module: &ModRef) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                continue;
            }
            let name = d.name();
            if matches!(&d.decl().kind, DeclKind::Record(r) if r.external) {
                // An opaque runtime type: the loader registered its canonical symbol.
                let canonical = stdlib::is_source_module(module)
                    .then(|| stdlib::standard_symbol(name.as_str()))
                    .flatten()
                    .filter(|s| s.decl.as_ref().is_some_and(|sd| sd.same(d)));
                match canonical {
                    Some(s) => self.add_symbol(name, s, d.pos()),
                    None => self.type_error(
                        d.pos(),
                        "extern type is available only in bundled standard modules; declare a record or alternative instead",
                    ),
                }
                continue;
            }
            if matches!(
                d.decl().kind,
                DeclKind::Record(_) | DeclKind::Alternative(_) | DeclKind::Interface(_)
            ) {
                // A bundled module's exported types were declared when it was registered.
                let predeclared = stdlib::is_source_module(module)
                    .then(|| stdlib::source_type(module.file, name))
                    .flatten()
                    .filter(|s| s.decl.as_ref().is_some_and(|sd| sd.same(d)));
                if let Some(s) = predeclared {
                    self.add_symbol(name, s, d.pos());
                    continue;
                }
            }
            let id = self.unique("symbol");
            let kind = match &d.decl().kind {
                DeclKind::Fn(_) | DeclKind::Const(_) => None,
                DeclKind::Record(_) => Some(Kind::Record),
                DeclKind::Alternative(_) => Some(Kind::Alternative),
                DeclKind::Interface(_) => Some(Kind::Contract),
                _ => None,
            };
            // An `extern fn` calls the native symbol named after it.
            let native = match &d.decl().kind {
                DeclKind::Fn(f) if f.external => n(&format!("extern:{name}")),
                _ => n(""),
            };
            let s = Rc::new(Sym {
                name,
                id,
                kind: if kind.is_some() {
                    SymKind::Type
                } else {
                    SymKind::Fn
                },
                module: module.file,
                native,
                export: d.decl().export,
                ty: RefCell::new(None),
                variables: RefCell::new(Vec::new()),
                decl: Some(d.clone()),
            });
            if let Some(kind) = kind {
                let def = Definition::new(&s, kind);
                let mut t = Type::new(
                    name,
                    n(&format!("module/{}#{}", hex(module.file.as_str()), name)),
                    kind,
                );
                t.def = Some(def);
                *s.ty.borrow_mut() = Some(Rc::new(t));
            }
            self.add_symbol(name, s, d.pos());
        }
    }

    /// The symbol declared by `d` in this module (not shadowed by a duplicate).
    pub(crate) fn own_symbol(&self, d: &DeclRef) -> Option<SymRef> {
        let s = self.sym(d.name())?;
        match &s.decl {
            Some(sd) if sd.same(d) => Some(s),
            _ => None,
        }
    }

    fn declare_type_variables(&mut self, module: &ModRef) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                continue;
            }
            let Some(s) = self.own_symbol(d) else {
                continue;
            };
            let old = std::mem::replace(&mut self.scope, Scope::new(None));
            let vars = self.type_variables(d.type_params());
            *s.variables.borrow_mut() = vars.clone();
            if s.kind == SymKind::Type {
                let t = s.ty();
                *t.def.as_ref().expect("def").variables.borrow_mut() = vars.clone();
                // The declaration's own type carries its variables as arguments.
                let with = with_args(&t, vars);
                *s.ty.borrow_mut() = Some(with);
                // Keep Definition::symbol's type consistent: the definition is shared.
            }
            self.scope = old;
        }
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                continue;
            }
            if let Some(s) = self.own_symbol(d) {
                let vars = s.variables();
                self.type_defaults(d.type_params(), &vars);
            }
        }
    }

    /// Resolves default type arguments.
    pub(crate) fn type_defaults(&mut self, params: &[TypeParam], vars: &[Ty]) {
        let mut defaulted = false;
        let old = self.scope.clone();
        for (index, p) in params.iter().enumerate() {
            let Some(default) = &p.default else {
                if defaulted {
                    self.type_error(
                        p.pos,
                        format!(
                            "type parameter {} needs a default because an earlier parameter has one; give {} a default or move it before the defaulted parameters",
                            p.name, p.name
                        ),
                    );
                }
                continue;
            };
            defaulted = true;
            self.scope = self.variable_scope(&vars[..index]);
            let resolved = self.resolve(Some(default));
            if invalid_ty(&resolved) {
                continue;
            }
            for bound in vars[index].bounds() {
                if self.standard_declarations {
                    self.deferred_default_bounds.push(DeferredBound {
                        resolved: resolved.clone(),
                        bound: bound.clone(),
                        pos: default.pos,
                        module: self.m(),
                    });
                } else if !self.satisfies(&resolved, &bound) {
                    let msg = self.unsatisfied_message(
                        &resolved,
                        &bound,
                        "choose a default that already implements it",
                    );
                    self.type_error(default.pos, msg);
                }
            }
            *vars[index].default.borrow_mut() = Some(resolved);
        }
        self.scope = old;
    }

    fn resolve_signatures(&mut self, module: &ModRef) {
        for pass in 0..2 {
            self.resolve_signature_pass(module, pass == 1);
        }
    }

    fn resolve_signature_pass(&mut self, module: &ModRef, constants: bool) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                continue;
            }
            if d.is_constant() != constants {
                continue;
            }
            let Some(s) = self.own_symbol(d) else {
                continue;
            };
            let old = self.scope.clone();
            self.scope = self.variable_scope(&s.variables());
            if d.is_constant() {
                self.constant_type(&s);
            } else if s.kind == SymKind::Fn {
                let f = d.func().expect("fn");
                let t = self.signature(&f.params, Some(&f.result));
                *s.ty.borrow_mut() = Some(t);
            } else {
                let def = s.ty().def.clone().expect("def");
                let fields = self.params(d.record_fields());
                *def.fields.borrow_mut() = fields;
                let mut seen: HashSet<Name> = HashSet::new();
                for cs in d.cases() {
                    if !seen.insert(cs.name) {
                        self.type_error(
                            cs.pos,
                            format!("duplicate case {}; rename or remove one of them", cs.name),
                        );
                    }
                    let fields = self.params(&cs.fields);
                    def.cases.borrow_mut().push(Case {
                        name: cs.name,
                        fields,
                    });
                }
                let mut seen: HashSet<Name> = HashSet::new();
                for (mi, m) in d.methods().iter().enumerate() {
                    if !seen.insert(m.func.name) {
                        self.type_error(
                            m.pos,
                            format!(
                                "duplicate operation {}; rename or remove one of them",
                                m.func.name
                            ),
                        );
                    }
                    self.scope = self.variable_scope(&s.variables());
                    self.declare_self(&s.ty());
                    self.operation_variables(s.ty().id, m);
                    let ty = self.signature(&m.func.params, Some(&m.func.result));
                    // An inherent `impl` is desugared to a synthesized interface that no
                    // interface value can reach, so `Self` may appear anywhere in its methods.
                    if !d.decl().synthetic {
                        self.check_self_use(&ty, m.pos);
                    }
                    def.operations.borrow_mut().push(Operation {
                        name: m.func.name,
                        ty,
                        decl: Some(FuncRef {
                            decl: d.clone(),
                            index: Some(mi),
                        }),
                    });
                }
            }
            self.scope = old;
        }
    }

    fn check_defaults(&mut self, module: &ModRef) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Record(_))
                && let Some(s) = self.own_symbol(d)
            {
                self.check_field_defaults(d, &s);
            }
            if let DeclKind::Interface(i) = &d.decl().kind {
                if i.methods.is_empty() && !stdlib::is_source_module(module) {
                    self.type_error(
                        d.pos(),
                        "an interface declares at least one operation; only the standard library declares a property without operations, like `Data`",
                    );
                }
                for method in &i.methods {
                    for param in method.func.params.iter().filter(|p| p.mutable) {
                        self.type_error(
                            param.pos,
                            "an interface operation cannot take a `var` parameter, only a `var` receiver; return the new value, or pass a type that holds the state",
                        );
                    }
                    for param in &method.func.params {
                        let Some(default) = &param.default else {
                            continue;
                        };
                        let old = self.scope.clone();
                        let vars = self.sym(i.name).map(|s| s.variables()).unwrap_or_default();
                        self.scope = self.variable_scope(&vars);
                        let typ = self.resolve(param.ty.as_ref());
                        self.expression(default, Some(&typ));
                        let is_none =
                            matches!(&default.kind, ExprKind::Name(nm) if nm.as_str() == "none");
                        // Bundled interfaces are implemented by the runtime, which fills any default.
                        let bundled = stdlib::is_source_module(module);
                        if !bundled && (typ.id != "@std/Optional" || !is_none) {
                            self.type_error(
                                param.pos,
                                "interface defaults must be Optional.none; write '= none' or remove the default",
                            );
                        }
                        self.scope = old;
                    }
                }
            }
        }
    }

    fn check_bodies(&mut self, module: &ModRef) {
        for d in &module.decls {
            match &d.decl().kind {
                DeclKind::Fn(f) if f.external => {
                    if let Some(s) = self.own_symbol(d) {
                        self.check_extern_signature(d.name().as_str(), f, &s.ty(), d.pos());
                    }
                }
                DeclKind::Fn(_) | DeclKind::Const(_) => {
                    if let Some(s) = self.own_symbol(d) {
                        let t = s.ty();
                        if d.is_constant() && t.result_ty().id == "<invalid>" {
                            continue;
                        }
                        self.check_function(&FuncRef::of_decl(d.clone()), &t, &s.variables(), None);
                    }
                }
                DeclKind::Test(_) => {
                    self.check_function(
                        &FuncRef::of_decl(d.clone()),
                        &function(Vec::new(), test_outcome()),
                        &[],
                        None,
                    );
                }
                _ => {}
            }
        }
        let methods: Vec<MethodRef> = self.p.methods.clone();
        for m in methods {
            if let Some(decl) = &m.decl
                && m.module == module.file
            {
                self.check_function(decl, &m.ty, &m.variables, Some(&m.receiver));
            }
        }
    }

    // --------------------------------------------------------------- bindings

    pub(crate) fn bind(&mut self, name: Name, t: &Ty, mutable: bool, pos: Pos) -> BindingRef {
        self.bind_reporting(name, t, mutable, pos, true)
    }

    /// Binds a name; `report` suppresses the duplicate error for callers that
    /// already diagnosed it.
    pub(crate) fn bind_reporting(
        &mut self,
        name: Name,
        t: &Ty,
        mutable: bool,
        pos: Pos,
        report: bool,
    ) -> BindingRef {
        // `_` names a value nothing reads, so several may share a scope.
        if report
            && name.as_str() != "_"
            && (self.scope.bindings.borrow().contains_key(&name)
                || self.scope.types.borrow().contains_key(&name))
        {
            self.type_error(
                pos,
                format!(
                    "duplicate local binding {name}; this scope already has that name, so choose another name or assign to the existing 'var'"
                ),
            );
        }
        if report
            && !name.as_str().starts_with('_')
            && name != "self"
            && self
                .scope
                .parent
                .as_ref()
                .is_some_and(|outer| outer.binding(name).is_some())
        {
            self.type_error(
                pos,
                format!(
                    "binding {name} shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'"
                ),
            );
        }
        let t = if mutable { required_type(t) } else { t.clone() };
        let id = self.unique("local");
        let b = Rc::new(Binding {
            name,
            id: n(&format!("{id}_{name}")),
            uid: BINDING_SERIAL.fetch_add(1, Ordering::Relaxed) + 1,
            ty: t,
            mutable,
            decl: pos,
            function: self.function,
        });
        self.scope.bindings.borrow_mut().insert(name, b.clone());
        b
    }

    pub(crate) fn type_variables(&mut self, params: &[TypeParam]) -> Vec<Ty> {
        let mut vars: Vec<Ty> = Vec::new();
        for p in params {
            let intrinsic = self
                .sym(p.name)
                .is_some_and(|s| s.module.as_str().is_empty())
                || self.scope.types.borrow().contains_key(&p.name)
                || matches!(
                    p.name.as_str(),
                    "Equal" | "Comparable" | "Hashable" | "Clonable"
                );
            if intrinsic {
                self.res_error(
                    p.pos,
                    format!(
                        "duplicate or intrinsic type parameter {}; choose a different type parameter name",
                        p.name
                    ),
                );
            }
            let id = self.unique("typevar");
            let v: Ty = Rc::new(Type::new(p.name, id, Kind::Variable));
            vars.push(v.clone());
            self.scope.types.borrow_mut().insert(p.name, v);
        }
        for (i, p) in params.iter().enumerate() {
            for b in &p.bounds {
                // A declaration's own parameters are not registered yet, so resolving it here would misreport its arity.
                if let TypeKind::Named { name, .. } = &b.kind
                    && !self.scope.types.borrow().contains_key(name)
                    && let Some(s) = self.sym(*name).filter(|s| s.kind == SymKind::Type)
                    && !matches!(s.ty().kind, Kind::Contract | Kind::Variable)
                {
                    self.type_error(
                        b.pos,
                        "a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'",
                    );
                    continue;
                }
                let t = self.resolve(Some(b));
                if t.kind != Kind::Contract {
                    if t.kind == Kind::Variable {
                        self.type_error(
                            b.pos,
                            format!(
                                "a bound must be an interface, but {} resolves to a type parameter; rename the type parameter or name an interface",
                                b.name()
                            ),
                        );
                    } else if t.id != "<invalid>" {
                        self.type_error(
                            b.pos,
                            "a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'",
                        );
                    }
                    continue;
                }
                vars[i].bounds.borrow_mut().push(t);
            }
        }
        vars
    }

    /// Resolves a written type.
    pub(crate) fn resolve(&mut self, t: Option<&TypeRef>) -> Ty {
        let Some(t) = t else {
            return invalid();
        };
        match &t.kind {
            TypeKind::Fn { params, result } => {
                let r = self.signature(params, Some(result));
                self.m().facts_mut().type_refs.insert(t.id, r.clone());
                r
            }
            TypeKind::Named { name, args } => {
                let name = *name;
                if self.scope.binding(name).is_some() {
                    self.res_error(
                        t.pos,
                        format!(
                            "a value shadows type {name}; rename the local binding so the type name is usable here"
                        ),
                    );
                    return invalid();
                }
                let base: Ty = if let Some(v) = self.scope.typ(name) {
                    v
                } else if let Some(s) = self.sym(name).filter(|s| s.kind == SymKind::Type) {
                    s.ty()
                } else {
                    let msg = self.unknown_type_message(name);
                    self.res_error_name(t.pos, name.len(), msg);
                    self.unknown_type = true;
                    return invalid();
                };
                if name == "Self" && args.is_empty() && !base.args.is_empty() {
                    // `Self` in an implementation already carries the receiver's arguments.
                    self.m().facts_mut().type_refs.insert(t.id, base.clone());
                    return base;
                }
                let mut r = (*base).clone();
                r.args = args.iter().map(|a| self.resolve(Some(a))).collect();
                let (arity, required) = match &base.def {
                    Some(def) => {
                        let vars = def.variables();
                        (vars.len(), required_type_arguments(&vars))
                    }
                    None => (0, 0),
                };
                if r.args.len() < arity && r.args.len() >= required {
                    let vars = base.def.as_ref().expect("def").variables();
                    r.args = with_default_arguments(&vars, &r.args);
                }
                if r.args.len() != arity {
                    if required < arity {
                        self.type_error(
                            t.pos,
                            format!(
                                "{} takes {} to {} type arguments, found {}; write {}",
                                base.name,
                                required,
                                arity,
                                r.args.len(),
                                crate::hints::type_sketch(base.name.as_str(), arity)
                            ),
                        );
                    } else {
                        let hint = self.prelude_shadow_hint(base.name);
                        self.type_error(
                            t.pos,
                            format!(
                                "{} requires {} type arguments, found {}; write {}{}",
                                base.name,
                                arity,
                                r.args.len(),
                                crate::hints::type_sketch(base.name.as_str(), arity),
                                hint
                            ),
                        );
                    }
                }
                let r = Rc::new(r);
                self.m().facts_mut().type_refs.insert(t.id, r.clone());
                r
            }
        }
    }

    /// An `extern fn` crosses the native ABI: scalars and borrowed strings in, a scalar,
    /// `Unit`, or an owned string out (`ms-rt/ABI.md`, section 1).
    fn check_extern_signature(&mut self, name: &str, f: &ms_syntax::ast::Func, t: &Ty, pos: Pos) {
        // Bundled modules cross any type the runtime defines a convention for; lowering rejects the rest.
        if self.module.as_ref().is_some_and(stdlib::is_source_module) {
            return;
        }
        if name.starts_with("msrt_") || name.starts_with("msstd_") {
            self.type_error(
                pos,
                format!("extern fn {name} names a runtime-internal symbol; msrt_ and msstd_ natives are reserved for bundled standard modules, so call the standard library instead"),
            );
        }
        if !f.type_params.is_empty() {
            self.type_error(
                pos,
                "an extern fn cannot be generic; declare the concrete types the native symbol takes",
            );
        }
        const ARGUMENTS: [&str; 4] = ["Int", "Float", "Bool", "String"];
        const RESULTS: [&str; 5] = ["Int", "Float", "Bool", "String", "Unit"];
        for (p, ty) in f.params.iter().zip(&t.params) {
            if p.mutable {
                self.type_error(
                    p.pos,
                    format!(
                        "extern parameter {} cannot be var; a native borrows its arguments",
                        p.name
                    ),
                );
            } else if p.default.is_some() {
                self.type_error(
                    p.pos,
                    format!("extern parameter {} cannot have a default; the native symbol takes every argument", p.name),
                );
            } else if ty.ty.id != "<invalid>" && !ARGUMENTS.contains(&ty.ty.id.as_str()) {
                self.type_error(
                    p.pos,
                    format!("extern parameter {} has type {}, which cannot cross the native boundary; use Int, Float, Bool, or String", p.name, ty.ty.name),
                );
            }
        }
        let result = t.result_ty();
        if result.id == "<invalid>" {
            return;
        }
        if result.is_std("Result") && result.args.len() == 2 {
            let (ok, error) = (&result.args[0], &result.args[1]);
            let cases = cases(error);
            if !RESULTS.contains(&ok.id.as_str()) {
                self.type_error(
                    f.result.pos,
                    format!("extern Result value has type {}, which cannot cross the native boundary; use Int, Float, Bool, String, or Unit", ok.name),
                );
            } else if cases.is_empty() || cases.iter().any(|c| !c.fields.is_empty()) {
                self.type_error(
                    f.result.pos,
                    format!("extern error type {} must be an alternative whose cases carry no payload; the native returns the status 1 + the case index", error.name),
                );
            }
        } else if !RESULTS.contains(&result.id.as_str()) {
            self.type_error(
                f.result.pos,
                format!("extern result has type {}, which cannot cross the native boundary; return Int, Float, Bool, String, Unit, or a Result of them", result.name),
            );
        }
    }

    pub(crate) fn params(&mut self, params: &[ms_syntax::ast::Param]) -> Vec<Param> {
        let mut result = Vec::new();
        let mut seen: HashSet<Name> = HashSet::new();
        for p in params {
            if !seen.insert(p.name) {
                self.type_error(
                    p.pos,
                    format!(
                        "duplicate parameter or field {}; each name may appear once, so rename one",
                        p.name
                    ),
                );
            }
            let ty = self.resolve(p.ty.as_ref());
            result.push(Param { name: p.name, ty });
        }
        result
    }

    pub(crate) fn signature(
        &mut self,
        params: &[ms_syntax::ast::Param],
        result: Option<&TypeRef>,
    ) -> Ty {
        let ps = self.params(params);
        let r = self.resolve(result);
        let mut defaults: HashSet<Name> = HashSet::new();
        for p in params {
            if p.default.is_some() {
                defaults.insert(p.name);
            }
        }
        let defaults = if defaults.is_empty() {
            None
        } else {
            Some(Rc::new(defaults))
        };
        function_with(ps, r, defaults)
    }

    // ----------------------------------------------------------- function body

    pub(crate) fn check_function(
        &mut self,
        d: &FuncRef,
        t: &Ty,
        vars: &[Ty],
        receiver: Option<&Ty>,
    ) {
        let old_scope = self.scope.clone();
        let old_result = self.result.clone();
        let old_function = self.function;
        let old_loops = self.loops;
        let old_test = self.test_function;
        self.scope = self.variable_scope(vars);
        self.result = t.result.clone();
        self.function = self.serial + 1;
        self.serial += 1;
        self.loops = 0;
        self.test_function = 0;
        let is_test = matches!(d.decl.decl().kind, DeclKind::Test(_)) && d.index.is_none();
        if is_test {
            self.test_function = self.function;
            // A bench body is timed repeatedly, so the file fixture and its hooks apply to tests only.
            let bench = matches!(&d.decl.decl().kind, DeclKind::Test(t) if t.bench);
            let fixture = self.p.test_fixtures.get(&self.current_file()).cloned();
            if let Some(fixture) = fixture.filter(|_| !bench) {
                let b = self.bind(n("fixture"), &fixture.ty, false, d.pos());
                self.m()
                    .facts_mut()
                    .decls
                    .entry(d.id())
                    .or_default()
                    .fixture = Some(b);
            }
        }
        if let Some(receiver) = receiver {
            self.scope
                .types
                .borrow_mut()
                .insert(n("Self"), receiver.clone());
            let b = self.bind(n("self"), receiver, false, d.pos());
            self.m()
                .facts_mut()
                .decls
                .entry(d.id())
                .or_default()
                .self_binding = Some(b);
        }
        let result_ty = t.result_ty();
        let fall;
        if let Some(c) = d.decl.constant().filter(|_| d.index.is_none()) {
            self.check_parameters(d, &[], &t.params);
            self.expression(&c.value, self.result.clone().as_ref());
            fall = false;
        } else {
            let params: &[ms_syntax::ast::Param] = match d.func() {
                Some(f) => &f.params,
                None => &[],
            };
            self.check_parameters(d, params, &t.params);
            let body: &[Stmt] = match (d.func(), &d.decl.decl().kind) {
                (Some(f), _) => &f.body,
                (None, DeclKind::Test(tt)) => &tt.body,
                _ => &[],
            };
            fall = self.block(body, false).0;
        }
        if fall && !is_test && result_ty.id != "Unit" && result_ty.id != "<invalid>" {
            self.type_error(
                d.pos(),
                format!(
                    "reachable fallthrough in function returning {rt}; end every path with 'return <{rt}>' (or make the last branch return)",
                    rt = result_ty
                ),
            );
        }
        self.scope = old_scope;
        self.result = old_result;
        self.function = old_function;
        self.loops = old_loops;
        self.test_function = old_test;
    }

    fn check_field_defaults(&mut self, d: &DeclRef, s: &SymRef) {
        let fields = d.record_fields();
        if !fields.iter().any(|f| f.default.is_some()) {
            return;
        }
        let old_scope = self.scope.clone();
        let old_result = self.result.clone();
        let old_function = self.function;
        let old_loops = self.loops;
        self.scope = self.variable_scope(&s.variables());
        self.result = Some(s.ty());
        self.serial += 1;
        self.function = self.serial;
        self.loops = 0;
        let def_fields = s.ty().def.as_ref().expect("def").fields.borrow().clone();
        self.check_parameters(&FuncRef::of_decl(d.clone()), fields, &def_fields);
        self.scope = old_scope;
        self.result = old_result;
        self.function = old_function;
        self.loops = old_loops;
    }

    pub(crate) fn check_parameters(
        &mut self,
        d: &FuncRef,
        params: &[ms_syntax::ast::Param],
        types: &[Param],
    ) {
        let mut seen: HashSet<Name> = HashSet::new();
        for (i, p) in types.iter().enumerate() {
            let repeated = !seen.insert(p.name);
            let pos = if i < params.len() {
                params[i].pos
            } else {
                d.pos()
            };
            if i < params.len()
                && let Some(default) = &params[i].default
            {
                self.expression(default, Some(&p.ty));
            }
            let mutable = params.get(i).is_some_and(|a| a.mutable);
            let b = self.bind_reporting(p.name, &p.ty, mutable, pos, !repeated);
            self.record_cleanup(&b);
            self.m()
                .facts_mut()
                .decls
                .entry(d.id())
                .or_default()
                .parameters
                .push(b);
        }
    }

    pub(crate) fn set_flow(&mut self, id: NodeId, falls: bool) {
        self.m()
            .facts_mut()
            .stmts
            .entry(id)
            .or_default()
            .falls_through = Some(falls);
    }

    // ---------------------------------------------------------- test fixtures

    fn check_test_fixture(&mut self, module: &ModRef) {
        if !module
            .decls
            .iter()
            .any(|d| matches!(d.decl().kind, DeclKind::Test(_)))
        {
            return;
        }
        let Some(factory) = self.sym(n("make_fixture")) else {
            return;
        };
        if factory.module != module.file {
            return;
        }
        let decl = factory.decl.clone().expect("decl");
        let t = factory.ty();
        if factory.kind != SymKind::Fn
            || decl.is_constant()
            || !factory.variables().is_empty()
            || !t.params.is_empty()
        {
            self.type_error(
                decl.pos(),
                "make_fixture must be a nongeneric zero-argument function; declare fn make_fixture() ConcreteFixture",
            );
            return;
        }
        let result = t.result_ty();
        let hooks = standard("TestHooks", vec![]);
        if !matches!(result.kind, Kind::Record | Kind::Alternative)
            || !self.implements(&result, &hooks)
        {
            self.type_error(
                decl.pos(),
                "make_fixture must return a concrete type implementing @std/test.ms TestHooks; return your fixture type and add impl TestHooks for it",
            );
            return;
        }
        self.p.test_fixtures.insert(
            module.file,
            TestFixture {
                factory,
                ty: result,
                hooks,
            },
        );
    }

    // --------------------------------------------------------------- prelude

    pub(crate) fn add_standard_prelude(&mut self) {
        let m = self.m();
        if !m.is_standard() {
            for d in &m.decls {
                if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                    continue;
                }
                let name = d.name();
                if matches!(name.as_str(), "some" | "none" | "ok" | "error") {
                    self.res_error(
                        d.pos(),
                        format!(
                            "declaration {name} reuses a prelude constructor name; rename it, because {name} always refers to the prelude case"
                        ),
                    );
                }
            }
        }
        // `a..b` is parsed as a call of `..`, which is always the standard `range`.
        if let Some(range) = stdlib::standard_module_symbol(n("@std/collections.ms"), n("range")) {
            self.names.borrow_mut().insert(n(".."), range);
        }
        for name in stdlib::STANDARD_PRELUDE_NAMES {
            let nm = n(name);
            let Some(symbol) = stdlib::standard_symbol(name) else {
                continue;
            };
            if symbol.module == m.file {
                continue;
            }
            let explicit = m
                .imports
                .iter()
                .any(|i| i.name == nm && i.path.starts_with("@std/"));
            if !explicit {
                self.names.borrow_mut().insert(nm, symbol);
            }
        }
    }
}

pub(crate) fn hex(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 2);
    for b in s.bytes() {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

/// Drops repeats of one message at one position.
pub fn unique_diagnostics(diagnostics: Vec<Diagnostic>) -> Vec<Diagnostic> {
    let mut seen: HashSet<(String, Pos, String)> = HashSet::new();
    let mut result = Vec::with_capacity(diagnostics.len());
    for d in diagnostics {
        // The position carries its file.
        let key = (d.file.to_string(), d.pos, d.message.clone());
        if seen.insert(key) {
            result.push(d);
        }
    }
    result
}

/// The implicit `Self` type of an interface: a variable that implementations and calls replace
/// with the receiver.
pub fn self_variable(owner: Name) -> Ty {
    Rc::new(Type::new(
        n("Self"),
        n(&format!("{owner}/Self")),
        Kind::Variable,
    ))
}

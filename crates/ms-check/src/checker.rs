//! The checker state and the module-level passes.

use crate::fxmap::{HashMap, HashSet};
use crate::stdlib::{Session, StdResult};
use crate::syntax::*;
use crate::types::*;
use crate::types::{Case, Param};
use crate::tytable::{TyId, TyTable};
use ms_syntax::ast::*;
use ms_syntax::{Cause, Diagnostic, Phase, Pos};
use std::cell::RefCell;
use std::rc::Rc;

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
            bindings: RefCell::new(HashMap::default()),
            types: RefCell::new(HashMap::default()),
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
    /// The session whose standard library the program was checked against.
    pub session: Rc<Session>,
    /// Reads and interns identifier text for this program.
    pub syms: ms_syntax::Names,
    /// Fixtures per module file.
    pub test_fixtures: HashMap<Name, TestFixture>,
    /// Conservative potential effects by callable id.
    pub effects: HashMap<Name, Vec<&'static str>>,
    /// Declared effects (`// ms: effect`) callers see, by callable id, sorted by name.
    pub declared_effects: HashMap<Name, Vec<String>>,
    /// `allow_effect` patterns in force per project callable (its own lines, else its file's);
    /// absent means no line, so the callable is pure.
    pub effect_permits: HashMap<Name, Vec<String>>,
    /// Project callables that reach a declared effect no `// ms: allow_effect` line permits.
    pub effect_violations: Vec<crate::effect_reach::Violation>,
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
    /// Ownership facts, filled by the ownership stage after the check succeeds.
    pub ownership: Rc<crate::ownership::OwnershipFacts>,
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

/// A default type check deferred until declarations and implementations are complete.
pub struct DeferredTypeDefault {
    /// Default type.
    pub resolved: Ty,
    /// The defaulted variable; its bounds, resolved after defaults, must hold for the default.
    pub variable: Ty,
    /// The declaration's variables. `resolved` captured them before their bounds were
    /// resolved, so the check re-reads each one's complete bounds.
    pub variables: Vec<Ty>,
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
    /// Facts about literal arithmetic trees, memoized per node so a long `a + b + c ...` chain is
    /// examined once per node, not once per enclosing operator.
    pub(crate) literal_facts: crate::constfaults::LiteralFacts,
    /// The session this checker reads the standard library from.
    pub(crate) session: Rc<Session>,
    /// Where the next checked expression is used, e.g. "argument 'a' of f".
    pub(crate) mismatch_context: Option<String>,
    pub(crate) scope_marker: Option<String>,
    pub(crate) standard_declarations: bool,
    pub(crate) deferred_type_defaults: Vec<DeferredTypeDefault>,
    pub(crate) id_scope: String,
    /// Mutually importing bundled source modules checked together.
    pub(crate) group: Vec<ModRef>,
    pub(crate) p: Program,
    /// Candidate positions in declaration order; type arguments are matched at use.
    pub(crate) methods_by_receiver: HashMap<Name, Vec<usize>>,
    /// Method indices by implemented contract id and receiver id, for a receiver that is not a type
    /// variable; methods of a contract variable are in `generic_contract_methods`. `implements`
    /// reads one bucket, so it does not scan every implementation of a widely implemented contract.
    pub(crate) methods_by_contract: HashMap<(Name, Name), Vec<usize>>,
    /// Method indices by implemented contract id for a receiver that is a type variable.
    pub(crate) variable_receiver_contract_methods: HashMap<Name, Vec<usize>>,
    pub(crate) generic_contract_methods: Vec<usize>,
    pub(crate) methods_by_name: HashMap<(Name, Name), Vec<usize>>,
    /// Types whose own `clone` is being looked up; a recursive type meets itself through its
    /// `List[Self]` field, whose `clone` bounds ask whether the element is clonable.
    pub(crate) clone_probes: RefCell<Vec<TyId>>,
    /// Type identities for the visited sets and property queries of the checks below.
    pub(crate) tys: RefCell<TyTable>,
    pub(crate) module: Option<ModRef>,
    pub(crate) names: Names,
    /// Reads and interns identifier text.
    pub(crate) syms: ms_syntax::Names,
    pub(crate) scope: Rc<Scope>,
    pub(crate) result: Option<Ty>,
    pub(crate) return_inference: Option<CallbackReturns>,
    pub(crate) inference_variables: VarSet,
    /// Callbacks whose body checks need a later result context.
    pub(crate) deferred_callbacks: HashSet<NodeId>,
    pub(crate) checked_arguments: Option<HashMap<NodeId, CheckedArgument>>,
    /// The member expression that is a call's callee, with the call's argument count.
    pub(crate) call_arity: Option<(NodeId, usize)>,
    pub(crate) function: usize,
    pub(crate) serial: usize,
    pub(crate) loops: usize,
    /// `(function, place)` of each `lock` guard that is still held.
    pub(crate) test_function: usize,
    pub(crate) rejected_names: HashSet<Name>,
    pub(crate) unknown_type: bool,
    /// Aliases whose target is being resolved, to reject a cycle.
    pub(crate) resolving_aliases: HashSet<Name>,
    /// Set while a bound or a type-set member is resolved: the only places a set may be named.
    pub(crate) allow_type_set: bool,
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
    pub fn new(session: &Rc<Session>, options: &CheckOptions) -> Checker {
        Checker {
            literal_facts: Default::default(),
            session: session.clone(),
            mismatch_context: None,
            scope_marker: options.scope_marker.clone(),
            standard_declarations: false,
            deferred_type_defaults: Vec::new(),
            id_scope: String::new(),
            group: Vec::new(),
            p: Program {
                syms: ms_syntax::Names::global(),
                session: session.clone(),
                ..Program::default()
            },
            methods_by_receiver: HashMap::default(),
            methods_by_contract: HashMap::default(),
            variable_receiver_contract_methods: HashMap::default(),
            generic_contract_methods: Vec::new(),
            methods_by_name: HashMap::default(),
            clone_probes: RefCell::new(Vec::new()),
            tys: RefCell::new(TyTable::new()),
            module: None,
            names: Rc::new(RefCell::new(HashMap::default())),
            syms: ms_syntax::Names::global(),
            scope: Scope::new(None),
            result: None,
            return_inference: None,
            inference_variables: VarSet::default(),
            deferred_callbacks: HashSet::default(),
            checked_arguments: None,
            call_arity: None,
            function: 0,
            serial: 0,
            loops: 0,
            test_function: 0,
            rejected_names: HashSet::default(),
            unknown_type: false,
            resolving_aliases: HashSet::default(),
            allow_type_set: false,
            unresolved_constructors: HashSet::default(),
            reported_bounds: HashSet::default(),
            in_declaration_checks: false,
            label_mismatch: false,
            conflicted_arguments: HashSet::default(),
            call_name: String::new(),
            call_pos: None,
            captures: HashMap::default(),
            constants_visiting: HashSet::default(),
            cycle_reported: HashSet::default(),
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

    /// Whether this file already reported `name` as unknown (and so suggested its import).
    pub(crate) fn unknown_reported(&self, name: Name) -> bool {
        let file = self.syms.str(self.current_file());
        self.p
            .diagnostics
            .iter()
            .any(|d| d.file.as_ref() == file && d.cause == Cause::Unknown(name))
    }

    /// Whether `e` is the prelude's `none`: the name, not shadowed by a local of that name
    /// (module declarations cannot reuse a prelude constructor name).
    pub(crate) fn names_none(&self, e: &Expr) -> bool {
        matches!(&e.kind, ExprKind::Name(nm) if self.syms.str(nm) == "none" && self.scope.binding(*nm).is_none())
    }

    /// Reports a diagnostic, applying the checker's suppression rules.
    pub(crate) fn error(&mut self, pos: Pos, phase: Phase, message: impl Into<String>) {
        let message: String = message.into();
        let file = self.current_file();
        self.error_in(file, pos, phase, message);
    }

    /// Reports a diagnostic and records why, for later decisions that read it.
    pub(crate) fn error_with_cause(
        &mut self,
        pos: Pos,
        phase: Phase,
        cause: Cause,
        message: impl Into<String>,
    ) {
        let file = self.current_file();
        self.report(file, pos, phase, message.into(), cause);
    }

    /// A type-phase diagnostic with its cause.
    pub(crate) fn type_error_with_cause(
        &mut self,
        pos: Pos,
        cause: Cause,
        message: impl Into<String>,
    ) {
        self.error_with_cause(pos, Phase::Type, cause, message);
    }

    /// Reports a diagnostic in an explicit file.
    pub(crate) fn error_in(&mut self, file: Name, pos: Pos, phase: Phase, message: String) {
        self.report(file, pos, phase, message, Cause::Other);
    }

    fn report(&mut self, file: Name, pos: Pos, phase: Phase, message: String, cause: Cause) {
        if let Some(m) = &self.module {
            for span in &m.recovered {
                if in_span(pos.offset, span) {
                    return;
                }
            }
            // A name the editor left out of a partial parse is not unknown.
            if let Cause::Unknown(name) = cause
                && m.omitted.iter().any(|o| o == self.syms.str(name))
            {
                return;
            }
        }
        if self.unknown_type && phase != Phase::Resolution && message.contains("<invalid>") {
            return;
        }
        self.p.diagnostics.push(Diagnostic {
            cause,
            opener_line: 0,
            file: self.syms.str(file).into(),
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
            format!(
                "{t_t} is opaque outside {module_t}: {what}; use the functions {module_t} exports",
                t_t = t.display(self.syms),
                module_t = self.syms.str(module)
            ),
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
            && self.session.is_prelude_symbol(e)
            && !self.session.is_prelude_symbol(&s)
            && e.module != self.current_file()
        {
            self.res_error(
                    pos,
                    format!(
                        "declaration {name_t} reuses a prelude name; rename it, because {name_t} always refers to the standard declaration"
                    , name_t = self.syms.str(name)),
                );
            self.rejected_names.insert(name);
            return;
        }
        if existing.is_some() {
            let current = self.current_file();
            let imported = s.module != current
                && existing
                    .as_ref()
                    .is_some_and(|e| !self.session.is_prelude_symbol(e));
            let message = if imported {
                format!(
                    "import {name_t} collides with another {name_t} in this module; an import cannot be renamed, so import only one {name_t} here and wrap the other in a small module that exports it under a new name",
                    name_t = self.syms.str(name)
                )
            } else {
                format!(
                    "duplicate or intrinsic name {name_t}; this name is already declared, imported, or built in, so rename one of them",
                    name_t = self.syms.str(name)
                )
            };
            self.res_error(pos, message);
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
                .insert(n("Self"), self_variable(self.syms, owner.id));
        }
    }

    /// `Self` is limited to whole parameter and result types, the positions where a call can
    /// substitute the implementing type.
    pub(crate) fn check_self_use(&mut self, op: &Ty, pos: Pos) {
        fn mentions(t: &Ty) -> bool {
            t.is(Builtin::SelfType)
                || t.args.iter().any(mentions)
                || t.params.iter().any(|p| mentions(&p.ty))
                || t.result.as_ref().is_some_and(mentions)
        }
        let misplaced = op
            .params
            .iter()
            .any(|p| !p.ty.is(Builtin::SelfType) && mentions(&p.ty))
            || op
                .result
                .as_ref()
                .is_some_and(|r| !r.is(Builtin::SelfType) && mentions(r));
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
                        self.syms.str(param.name)
                    ),
                );
            } else if self.intrinsic_type_parameter(param.name) {
                self.res_error(
                    param.pos,
                    format!(
                        "duplicate or intrinsic type parameter {}; choose a different type parameter name",
                        self.syms.str(param.name)
                    ),
                );
            }
            let v: Ty = Rc::new(Type::new(
                self.syms,
                param.name,
                n(&format!(
                    "{owner_t}/{}/{}",
                    self.syms.str(method.func.name),
                    self.syms.str(param.name),
                    owner_t = self.syms.str(owner)
                )),
                Kind::Variable,
            ));
            variables.push(v.clone());
            self.scope.types.borrow_mut().insert(param.name, v);
        }
        self.resolve_type_bounds(&method.func.type_params, &variables);
        self.type_defaults(&method.func.type_params, &variables);
        self.session.set_operation_variables(
            format!(
                "{owner_t}/{}",
                self.syms.str(method.func.name),
                owner_t = self.syms.str(owner)
            ),
            variables,
        );
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
        let (modules, dependency_diagnostics) = self.session.source_standard_dependencies(modules);
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
        for method in self.session.standard_implementations() {
            self.add_method(method);
        }
        let mut checked: Vec<ModRef> = Vec::new();
        for module in &modules {
            if !self.group.is_empty() && self.group.iter().any(|g| g.file == module.file) {
                continue;
            }
            if self.session.is_source_module(module) && Some(module.file) != bundled {
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
            self.session.done(module.file).expect("dependency checked")
        } else {
            match self.session.ensure_source(module) {
                Ok(r) => r,
                Err(e) => return self.internal_error(e),
            }
        };
        self.p.symbols.insert(module.file, r.symbols.clone());
        for method in &r.methods {
            self.add_method(method.clone());
        }
    }

    /// Reports a defect in the bundled library as a diagnostic instead of panicking.
    fn internal_error(&mut self, message: String) {
        let file = self.current_file();
        self.error_in(
            file,
            Pos::default(),
            Phase::Type,
            format!("internal error: {message}"),
        );
    }

    /// Starts a module: fresh symbol table seeded with the primitive types and the standard prelude.
    fn begin_module(&mut self, module: &ModRef) {
        self.module = Some(module.clone());
        self.names = Rc::new(RefCell::new(HashMap::default()));
        self.p.symbols.insert(module.file, self.names.clone());
        self.scope = Scope::new(None);
        for name in PRIMITIVE_NAMES {
            let nm = n(name);
            let s = Rc::new(Sym {
                name: nm,
                id: n(primitive_id(name)),
                kind: SymKind::Type,
                module: n(""),
                native: Native::Source,
                export: true,
                ty: RefCell::new(Some(primitive(primitive_id(name)))),
                variables: RefCell::new(Vec::new()),
                decl: None,
            });
            self.names.borrow_mut().insert(nm, s);
        }
        self.add_standard_prelude();
    }

    /// Declaration passes for one module, in order.
    pub(crate) fn check_module(&mut self, module: &ModRef) {
        self.begin_module(module);
        self.import_symbols(module);
        self.declare_symbols(module);
        self.declare_type_variables(module);
        self.resolve_declaration_defaults(module);
        self.resolve_declaration_bounds(module);
        self.resolve_aliases(module);
        self.resolve_signatures(module);
        self.check_constant_cycles(module);
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_)) {
                self.implementation(d);
            }
        }
        self.check_type_defaults();
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
            self.begin_module(module);
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
            self.resolve_declaration_defaults(module);
        }
        for module in group {
            self.enter_module(module);
            self.resolve_declaration_bounds(module);
        }
        for module in group {
            self.enter_module(module);
            self.resolve_aliases(module);
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
        self.check_type_defaults();
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
        let mut broken: Option<String> = None;
        for item in &module.imports {
            let path = item.path.as_ref();
            let found: Option<SymRef> = if path.starts_with("@std/") {
                let pn = n(path);
                if self.session.standard_source_module(pn).is_some() {
                    let f = self
                        .p
                        .symbols
                        .get(&pn)
                        .and_then(|names| names.borrow().get(&item.name).cloned());
                    f.filter(|f| f.module == pn)
                } else {
                    // A file that mixes native declarations and bodies exports both halves under its own name.
                    self.session
                        .standard_module_symbol(pn, item.name)
                        .or_else(|| {
                            let twin = self.session.import_source(item)?;
                            if self.group.iter().any(|g| g.file == twin.file) {
                                // The twin is checked together with this module: its symbols
                                // are declared in this program, not yet in the shared world.
                                return self
                                    .p
                                    .symbols
                                    .get(&twin.file)
                                    .and_then(|names| names.borrow().get(&item.name).cloned())
                                    .filter(|s| s.module == twin.file);
                            }
                            match self.session.ensure_source(&twin) {
                                Ok(r) => r
                                    .exports
                                    .get(&item.name)
                                    .filter(|s| s.module == twin.file)
                                    .cloned(),
                                Err(e) => {
                                    broken = Some(e);
                                    None
                                }
                            }
                        })
                }
            } else {
                self.imports.get(module.file, item.id).and_then(|target| {
                    self.p.symbols.get(&target).and_then(|names| {
                        names
                            .borrow()
                            .get(&item.name)
                            .filter(|symbol| symbol.module == target)
                            .cloned()
                    })
                })
            };
            if let Some(e) = broken.take() {
                self.internal_error(e);
                continue;
            }
            let hidden = crate::stdlib::is_internal(path)
                && !self.syms.str(module.file).starts_with("@std/");
            // An internal module declares the natives of its host and names the host's private types.
            let host = crate::stdlib::is_internal(self.syms.str(module.file));
            let usable = found
                .as_ref()
                .filter(|f| (f.export || host) && !hidden)
                .cloned();
            let Some(found) = usable else {
                let end = Pos::new(
                    item.name_pos.offset + self.syms.str(item.name).len() as u32,
                    item.name_pos.line,
                    item.name_pos.column + self.syms.str(item.name).len() as u32,
                );
                let message = self.export_message(item);
                self.p.diagnostics.push(Diagnostic {
                    cause: Default::default(),
                    opener_line: 0,
                    file: self.syms.str(module.file).into(),
                    pos: item.name_pos,
                    phase: Phase::Resolution,
                    message,
                    end: Some(end),
                    fix: None,
                });
                continue;
            };
            if self.session.is_prelude_symbol(&found) {
                self.redundant_prelude_import(module, item);
            }
            self.add_symbol(item.name, found, item.name_pos);
        }
    }

    /// A user `extern type`: an opaque handle a native shim makes with `ms_object_new`.
    fn declare_extern_type(&mut self, module: &ModRef, d: &DeclRef) {
        let name = d.name();
        if !d.type_params().is_empty() {
            self.type_error(
                d.pos(),
                format!("extern type {name_t} cannot be generic; declare one extern type per native handle", name_t = self.syms.str(name)),
            );
        }
        let id = n(&format!(
            "extern:{}/{name_t}",
            self.syms.str(module.file),
            name_t = self.syms.str(name)
        ));
        let s = Rc::new(Sym {
            name,
            id,
            kind: SymKind::Type,
            module: module.file,
            native: Native::Source,
            export: d.decl().export,
            ty: RefCell::new(None),
            variables: RefCell::new(Vec::new()),
            decl: Some(d.clone()),
        });
        let def = Definition::new(&s, Kind::Native);
        let mut t = Type::new(self.syms, name, id, Kind::Native);
        t.def = Some(def);
        *s.ty.borrow_mut() = Some(Rc::new(t));
        self.add_symbol(name, s, d.pos());
    }

    fn declare_symbols(&mut self, module: &ModRef) {
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                continue;
            }
            let name = d.name();
            if matches!(&d.decl().kind, DeclKind::Type(r) if r.external) {
                // An opaque runtime type: the loader registered its canonical symbol.
                let canonical = self
                    .session
                    .is_source_module(module)
                    .then(|| self.session.standard_symbol(self.syms.str(name)))
                    .flatten()
                    .filter(|s| s.decl.as_ref().is_some_and(|sd| sd.same(d)));
                match canonical {
                    Some(s) => self.add_symbol(name, s, d.pos()),
                    None => self.declare_extern_type(module, d),
                }
                continue;
            }
            if matches!(
                d.decl().kind,
                DeclKind::Type(_) | DeclKind::Alternative(_) | DeclKind::Interface(_)
            ) {
                // A bundled module's exported types were declared when it was registered.
                let predeclared = self
                    .session
                    .is_source_module(module)
                    .then(|| self.session.source_type(module.file, name))
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
                DeclKind::Type(_) => Some(Kind::Type),
                DeclKind::Alternative(_) => Some(Kind::Alternative),
                DeclKind::Interface(_) => Some(Kind::Contract),
                _ => None,
            };
            let is_alias = matches!(d.decl().kind, DeclKind::Alias(_));
            // An `extern fn` calls the native symbol named after it.
            let native = match &d.decl().kind {
                DeclKind::Fn(f) if f.external => Native::Extern {
                    symbol: name,
                    bundled: self.session.is_source_module(module),
                },
                _ => Native::Source,
            };
            let s = Rc::new(Sym {
                name,
                id,
                kind: if kind.is_some() {
                    SymKind::Type
                } else if is_alias {
                    SymKind::Alias
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
                    self.syms,
                    name,
                    n(&format!(
                        "module/{}#{}",
                        hex(self.syms.str(module.file)),
                        self.syms.str(name)
                    )),
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
                let t = s.ty(self.syms);
                *t.def.as_ref().expect("def").variables.borrow_mut() = vars.clone();
                // The declaration's own type carries its variables as arguments.
                let with = with_args(&t, vars);
                *s.ty.borrow_mut() = Some(with);
                // Keep Definition::symbol's type consistent: the definition is shared.
            }
            self.scope = old;
        }
    }

    /// Every nominal parameter list must be registered before a bound can apply it.
    fn resolve_declaration_bounds(&mut self, module: &ModRef) {
        for d in &module.decls {
            if !d.type_params().iter().any(|p| !p.bounds.is_empty()) {
                continue;
            }
            let Some(s) = self.own_symbol(d) else {
                continue;
            };
            let vars = s.variables();
            let scope = self.variable_scope(&vars);
            let old = std::mem::replace(&mut self.scope, scope);
            self.resolve_type_bounds(d.type_params(), &vars);
            self.scope = old;
        }
    }

    /// Resolves every alias target of the module, after type variables and bounds exist.
    fn resolve_aliases(&mut self, module: &ModRef) {
        for d in &module.decls {
            if let Some(s) = self.own_symbol(d).filter(|s| s.kind == SymKind::Alias) {
                self.alias_target(&s);
            }
        }
    }

    /// The type an alias names, over the alias's own variables; resolved once, on first use.
    fn alias_target(&mut self, s: &SymRef) -> Ty {
        if let Some(t) = s.ty_opt() {
            return t;
        }
        let Some(decl) = s.decl.clone() else {
            return invalid();
        };
        let same_module = self.module.as_ref().is_some_and(|m| m.file == s.module);
        if !same_module {
            return invalid();
        }
        if !self.resolving_aliases.insert(s.id) {
            self.res_error(
                decl.pos(),
                format!(
                    "type alias {} refers to itself; an alias names another type, so break the cycle with a type or enum",
                    self.syms.str(s.name)
                ),
            );
            return invalid();
        }
        let scope = self.variable_scope(&s.variables());
        let old = std::mem::replace(&mut self.scope, scope);
        let targets = decl.alias_targets();
        let target = if targets.len() > 1 {
            self.type_set(s, targets)
        } else {
            self.resolve(targets.first())
        };
        self.scope = old;
        self.resolving_aliases.remove(&s.id);
        *s.ty.borrow_mut() = Some(target.clone());
        target
    }

    /// The type set `type Name = A | B`: a bound-only type whose arguments are its members, with
    /// the members of a member set flattened in.
    fn type_set(&mut self, s: &SymRef, targets: &[TypeRef]) -> Ty {
        let mut members: Vec<Ty> = Vec::new();
        for target in targets {
            let was = std::mem::replace(&mut self.allow_type_set, true);
            let member = self.resolve(Some(target));
            self.allow_type_set = was;
            let flat = if member.is(Builtin::TypeSet) {
                member.args.clone()
            } else {
                vec![member]
            };
            for m in flat {
                if m.is_invalid() {
                    continue;
                }
                if m.kind == Kind::Variable || m.kind == Kind::Contract {
                    self.res_error(
                        target.pos,
                        "a type set holds concrete types; name a type such as Int, not a type parameter or interface",
                    );
                    continue;
                }
                if !members.iter().any(|x| same(x, &m)) {
                    members.push(m);
                }
            }
        }
        let id = self.unique("typeset");
        let mut t = Type::new(self.syms, s.name, id, Kind::Contract);
        t.builtin = Some(Builtin::TypeSet);
        t.args = members;
        Rc::new(t)
    }

    /// A written use of an alias: its target with the written arguments substituted.
    fn resolve_alias_use(&mut self, t: &TypeRef, s: &SymRef, args: &[TypeRef]) -> Ty {
        let target = self.alias_target(s);
        if target.is(Builtin::TypeSet) && !self.allow_type_set {
            self.type_error(
                t.pos,
                format!(
                    "{} is a type set, which constrains a type parameter and has no values; write fn f[T: {}](...) or use one of its members",
                    self.syms.str(s.name),
                    self.syms.str(s.name)
                ),
            );
            return invalid();
        }
        let vars = s.variables();
        let mut written: Vec<Ty> = args.iter().map(|a| self.resolve(Some(a))).collect();
        let required = required_type_arguments(&vars);
        if written.len() < vars.len() && written.len() >= required {
            written = with_default_arguments(&vars, &written);
        }
        if written.len() != vars.len() {
            let name = self.syms.str(s.name).to_string();
            self.type_error(
                t.pos,
                format!(
                    "alias {name} takes {} type arguments, found {}; write {}",
                    vars.len(),
                    written.len(),
                    crate::hints::type_sketch(&name, vars.len())
                ),
            );
            return invalid();
        }
        let mut bindings = Subst::default();
        for (v, a) in vars.iter().zip(written) {
            bindings.insert(v.id, a);
        }
        let r = sub(&target, &bindings);
        self.m().facts_mut().type_refs.insert(t.id, r.clone());
        r
    }

    fn resolve_declaration_defaults(&mut self, module: &ModRef) {
        // A default that names a type with defaulted parameters needs that type's defaults first,
        // whichever is declared earlier. A cycle leaves the inner type unresolved.
        let declared: HashMap<Name, usize> = module
            .decls
            .iter()
            .enumerate()
            .filter(|(_, d)| !matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)))
            .map(|(i, d)| (d.name(), i))
            .collect();
        let mut state: HashMap<usize, bool> = HashMap::default();
        for index in 0..module.decls.len() {
            self.declaration_type_defaults(module, &declared, &mut state, index);
        }
    }

    /// Resolves the type defaults of declaration `index` after those of the declarations its
    /// defaults name. `state` maps a started declaration to whether it finished.
    fn declaration_type_defaults(
        &mut self,
        module: &ModRef,
        declared: &HashMap<Name, usize>,
        state: &mut HashMap<usize, bool>,
        index: usize,
    ) {
        if state.contains_key(&index) {
            return;
        }
        state.insert(index, false);
        let d = &module.decls[index];
        if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
            return;
        }
        let Some(s) = self.own_symbol(d) else {
            return;
        };
        let mut named = Vec::new();
        for param in d.type_params() {
            if let Some(default) = &param.default {
                named_types(default, &mut named);
            }
        }
        for name in named {
            if let Some(&dependency) = declared.get(&name) {
                self.declaration_type_defaults(module, declared, state, dependency);
            }
        }
        let vars = s.variables();
        self.type_defaults(d.type_params(), &vars);
        state.insert(index, true);
    }

    /// Resolves default type arguments.
    pub(crate) fn type_defaults(&mut self, params: &[TypeParam], vars: &[Ty]) {
        if !params.iter().any(|param| param.default.is_some()) {
            return;
        }
        let mut defaulted = false;
        let old = self.scope.clone();
        // Receiver parameters and Self stay visible; this parameter list's own
        // variables become visible only after their defaults have been resolved.
        let enclosing = Scope::new(old.parent.clone());
        let own: HashSet<Name> = vars.iter().map(|v| v.id).collect();
        for (name, ty) in old.types.borrow().iter() {
            if !own.contains(&ty.id) {
                enclosing.types.borrow_mut().insert(*name, ty.clone());
            }
        }
        for (index, p) in params.iter().enumerate() {
            let Some(default) = &p.default else {
                if defaulted {
                    self.type_error(
                        p.pos,
                        format!(
                            "type parameter {} needs a default because an earlier parameter has one; give {} a default or move it before the defaulted parameters",
                            self.syms.str(p.name), self.syms.str(p.name)
                        ),
                    );
                }
                continue;
            };
            defaulted = true;
            self.scope = Scope::new(Some(enclosing.clone()));
            for var in &vars[..index] {
                self.scope.types.borrow_mut().insert(var.name, var.clone());
            }
            let resolved = self.resolve(Some(default));
            if invalid_ty(&resolved) {
                continue;
            }
            self.deferred_type_defaults.push(DeferredTypeDefault {
                resolved: resolved.clone(),
                variable: vars[index].clone(),
                variables: vars[..index].to_vec(),
                pos: default.pos,
                module: self.m(),
            });
            *vars[index].default.borrow_mut() = Some(resolved);
        }
        self.scope = old;
    }

    /// Fields and implementations must be complete before defaults are tested.
    pub(crate) fn check_type_defaults(&mut self) {
        let old_module = self.module.clone();
        for check in std::mem::take(&mut self.deferred_type_defaults) {
            self.module = Some(check.module);
            let current: Subst = check.variables.iter().map(|v| (v.id, v.clone())).collect();
            let resolved = sub(&check.resolved, &current);
            self.well_formed(&resolved, check.pos, &mut HashSet::default());
            let bindings = Subst::from_iter([(check.variable.id, resolved.clone())]);
            for bound in check.variable.bounds() {
                let bound = sub(&bound, &bindings);
                if !self.satisfies(&resolved, &bound) {
                    let message = self.unsatisfied_message(
                        &resolved,
                        &bound,
                        "choose a default that already implements it",
                    );
                    self.type_error(check.pos, message);
                }
            }
        }
        self.module = old_module;
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
            if s.kind == SymKind::Alias {
                continue;
            }
            let old = self.scope.clone();
            self.scope = self.variable_scope(&s.variables());
            if d.is_constant() {
                self.constant_type(&s);
            } else if s.kind == SymKind::Fn {
                let f = d.func().expect("fn");
                let t = self.signature(&f.params, Some(&f.result));
                *s.ty.borrow_mut() = Some(t);
            } else {
                let def = s.ty(self.syms).def.clone().expect("def");
                let fields = self.params(d.type_fields());
                *def.fields.borrow_mut() = fields;
                def.clear_cases();
                let mut seen: HashSet<Name> = HashSet::default();
                for cs in d.cases() {
                    if !seen.insert(cs.name) {
                        self.type_error(
                            cs.pos,
                            format!(
                                "duplicate case {}; rename or remove one of them",
                                self.syms.str(cs.name)
                            ),
                        );
                    }
                    let fields = self.params(&cs.fields);
                    def.push_case(Case {
                        name: cs.name,
                        fields,
                    });
                }
                let mut seen: HashSet<Name> = HashSet::default();
                for (mi, m) in d.methods().iter().enumerate() {
                    if !seen.insert(m.func.name) {
                        self.type_error(
                            m.pos,
                            format!(
                                "duplicate operation {}; rename or remove one of them",
                                self.syms.str(m.func.name)
                            ),
                        );
                    }
                    self.scope = self.variable_scope(&s.variables());
                    self.declare_self(&s.ty(self.syms));
                    self.operation_variables(s.ty(self.syms).id, m);
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
            if matches!(d.decl().kind, DeclKind::Type(_))
                && let Some(s) = self.own_symbol(d)
            {
                self.check_field_defaults(d, &s);
            }
            if let DeclKind::Interface(i) = &d.decl().kind {
                if i.methods.is_empty() && !self.session.is_source_module(module) {
                    self.type_error(
                        d.pos(),
                        "an interface declares at least one operation; only the standard library declares a property without operations, like `Data`",
                    );
                }
                for method in &i.methods {
                    for param in &method.func.params {
                        let Some(default) = &param.default else {
                            continue;
                        };
                        let old = self.scope.clone();
                        let mut vars = self.sym(i.name).map(|s| s.variables()).unwrap_or_default();
                        if let Some(symbol) = self.sym(i.name) {
                            vars.extend(self.session.operation_variables(&format!(
                                "{}/{}",
                                self.syms.str(symbol.ty(self.syms).id),
                                self.syms.str(method.func.name)
                            )));
                        }
                        self.scope = self.variable_scope(&vars);
                        let typ = self.resolve(param.ty.as_ref());
                        self.expression(default, Some(&typ));
                        let is_none =
                            self.m().default_form(self.syms, default) == DefaultForm::None;
                        // Bundled interfaces are implemented by the runtime, which fills any default.
                        let bundled = self.session.is_source_module(module);
                        if !bundled && (self.syms.str(typ.id) != "@std/Optional" || !is_none) {
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
                        self.check_extern_signature(
                            self.syms.str(d.name()),
                            f,
                            &s.ty(self.syms),
                            d.pos(),
                        );
                    }
                }
                DeclKind::Fn(_) | DeclKind::Const(_) => {
                    if let Some(s) = self.own_symbol(d) {
                        let t = s.ty(self.syms);
                        if d.is_constant() && t.result_ty().is_invalid() {
                            continue;
                        }
                        self.check_function(&FuncRef::of_decl(d.clone()), &t, &s.variables(), None);
                    }
                }
                DeclKind::Test(_) => {
                    self.check_function(
                        &FuncRef::of_decl(d.clone()),
                        &function(self.syms, Vec::new(), self.session.test_outcome()),
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
            && self.syms.str(name) != "_"
            && (self.scope.bindings.borrow().contains_key(&name)
                || self.scope.types.borrow().contains_key(&name))
        {
            self.type_error(
                pos,
                format!(
                    "duplicate local binding {name_t}; this scope already has that name, so choose another name or assign to the existing 'var'"
                , name_t = self.syms.str(name)),
            );
        }
        if report
            && !self.syms.str(name).starts_with('_')
            && self.syms.str(name) != "self"
            && self
                .scope
                .parent
                .as_ref()
                .is_some_and(|outer| outer.binding(name).is_some())
        {
            self.type_error(
                pos,
                format!(
                    "binding {name_t} shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'"
                , name_t = self.syms.str(name)),
            );
        }
        let t = if mutable { required_type(t) } else { t.clone() };
        let id = self.unique("local");
        let b = Rc::new(Binding {
            name,
            id: n(&format!(
                "{id_t}_{name_t}",
                id_t = self.syms.str(id),
                name_t = self.syms.str(name)
            )),
            uid: self.session.next_binding(),
            ty: t,
            mutable,
            decl: pos,
            function: self.function,
        });
        self.scope.bindings.borrow_mut().insert(name, b.clone());
        b
    }

    pub(crate) fn intrinsic_type_parameter(&self, name: Name) -> bool {
        self.sym(name)
            .is_some_and(|s| self.syms.str(s.module).is_empty())
            || matches!(
                self.syms.str(name),
                "Equal" | "Comparable" | "Hashable" | "Clonable"
            )
    }

    pub(crate) fn type_variables(&mut self, params: &[TypeParam]) -> Vec<Ty> {
        let mut vars: Vec<Ty> = Vec::new();
        for p in params {
            let intrinsic = self.intrinsic_type_parameter(p.name)
                || self.scope.types.borrow().contains_key(&p.name);
            if intrinsic {
                self.res_error(
                    p.pos,
                    format!(
                        "duplicate or intrinsic type parameter {}; choose a different type parameter name",
                        self.syms.str(p.name)
                    ),
                );
            }
            let id = self.unique("typevar");
            let v: Ty = Rc::new(Type::new(self.syms, p.name, id, Kind::Variable));
            vars.push(v.clone());
            self.scope.types.borrow_mut().insert(p.name, v);
        }
        vars
    }

    /// Attaches only interface bounds, consistently for declarations and operations.
    pub(crate) fn resolve_type_bounds(&mut self, params: &[TypeParam], vars: &[Ty]) {
        for (i, p) in params.iter().enumerate() {
            for b in &p.bounds {
                // Report the invalid bound kind before any unrelated type-argument errors.
                if let TypeKind::Named { name, .. } = &b.kind
                    && !self.scope.types.borrow().contains_key(name)
                    && let Some(s) = self.sym(*name).filter(|s| s.kind == SymKind::Type)
                    && !matches!(s.ty(self.syms).kind, Kind::Contract | Kind::Variable)
                {
                    self.type_error(
                        b.pos,
                        "a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'",
                    );
                    continue;
                }
                let was = std::mem::replace(&mut self.allow_type_set, true);
                let t = self.resolve(Some(b));
                self.allow_type_set = was;
                if t.kind != Kind::Contract {
                    if t.kind == Kind::Variable {
                        self.type_error(
                            b.pos,
                            format!(
                                "a bound must be an interface, but {} resolves to a type parameter; rename the type parameter or name an interface",
                                b.name(self.syms)
                            ),
                        );
                    } else if !t.is_invalid() {
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
    }

    /// Resolves a written type.
    pub(crate) fn resolve(&mut self, t: Option<&TypeRef>) -> Ty {
        let Some(t) = t else {
            return invalid();
        };
        match &t.kind {
            TypeKind::Fn { params, result } => {
                let mut r = (*self.signature(params, Some(result))).clone();
                for p in &mut r.params {
                    p.positional = true;
                }
                let r: Ty = Rc::new(r);
                self.m().facts_mut().type_refs.insert(t.id, r.clone());
                r
            }
            TypeKind::Named { name, args } => {
                let name = *name;
                if self.scope.binding(name).is_some() {
                    self.res_error(
                        t.pos,
                        format!(
                            "a value shadows type {name_t}; rename the local binding so the type name is usable here"
                        , name_t = self.syms.str(name)),
                    );
                    return invalid();
                }
                if self.scope.typ(name).is_none()
                    && let Some(s) = self.sym(name).filter(|s| s.kind == SymKind::Alias)
                {
                    return self.resolve_alias_use(t, &s, args);
                }
                let base: Ty = if let Some(v) = self.scope.typ(name) {
                    v
                } else if let Some(s) = self.sym(name).filter(|s| s.kind == SymKind::Type) {
                    s.ty(self.syms)
                } else {
                    let msg = self.unknown_type_message(name);
                    self.unknown_error(t.pos, name, msg);
                    self.unknown_type = true;
                    return invalid();
                };
                if self.syms.str(name) == "Self" && args.is_empty() && !base.args.is_empty() {
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
                                self.syms.str(base.name),
                                required,
                                arity,
                                r.args.len(),
                                crate::hints::type_sketch(self.syms.str(base.name), arity)
                            ),
                        );
                    } else {
                        let hint = self.prelude_shadow_hint(base.name);
                        self.type_error(
                            t.pos,
                            format!(
                                "{} requires {} type arguments, found {}; write {}{}",
                                self.syms.str(base.name),
                                arity,
                                r.args.len(),
                                crate::hints::type_sketch(self.syms.str(base.name), arity),
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

    /// An `extern fn` crosses the native ABI of `ms_abi.h`: the types [`crosses_native`]
    /// accepts, `Unit` results, and `Result`s whose error cases carry a code and a message.
    fn check_extern_signature(&mut self, name: &str, f: &ms_syntax::ast::Func, t: &Ty, pos: Pos) {
        // Bundled modules cross any type the runtime defines a convention for; lowering rejects the rest.
        if self
            .module
            .as_ref()
            .is_some_and(|m| self.session.is_source_module(m))
        {
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
        const CROSSES: &str = "sized numbers, Bool, String, Bytes, extern types this program declares, and Lists of them";
        for (p, ty) in f.params.iter().zip(&t.params) {
            if p.mutable {
                self.type_error(
                    p.pos,
                    format!(
                        "extern parameter {} cannot be var; a native borrows its arguments",
                        self.syms.str(p.name)
                    ),
                );
            } else if p.default.is_some() {
                self.type_error(
                    p.pos,
                    format!("extern parameter {} cannot have a default; the native symbol takes every argument", self.syms.str(p.name)),
                );
            } else if ty.ty.kind == Kind::Function {
                if !crosses_callback(self.syms, &ty.ty) {
                    self.type_error(
                        p.pos,
                        format!("extern parameter {} has type {}, which cannot cross the native boundary; a function an extern takes has at most {MAX_CALLBACK_PARAMS} parameters of sized numbers, Bool, String, Bytes or extern types this program declares, and returns a number, Bool, String, Bytes or Unit", self.syms.str(p.name), ty.ty.display(self.syms)),
                    );
                }
            } else if !ty.ty.is_invalid() && !crosses_native(self.syms, &ty.ty) {
                self.type_error(
                    p.pos,
                    format!("extern parameter {} has type {}, which cannot cross the native boundary; an extern takes sized numbers, Bool, String, Bytes, extern types this program declares, Lists of them, and functions of them", self.syms.str(p.name), self.syms.str(ty.ty.name)),
                );
            }
        }
        let result = t.result_ty();
        if result.is_invalid() {
            return;
        }
        if result.is(Builtin::Result) && result.args.len() == 2 {
            let (ok, error) = (&result.args[0], &result.args[1]);
            let cases = cases(error);
            let reported = |c: &Case| {
                c.fields.iter().all(|f| {
                    (self.syms.str(f.name) == EXTERN_ERROR_CODE && f.ty.is(Builtin::Int))
                        || (self.syms.str(f.name) == EXTERN_ERROR_MESSAGE
                            && f.ty.is(Builtin::String))
                })
            };
            if !ok.is(Builtin::Unit) && !crosses_native(self.syms, ok) {
                self.type_error(
                    f.result.pos,
                    format!("extern Result value has type {}, which cannot cross the native boundary; an extern Result holds {CROSSES}, or Unit", self.syms.str(ok.name)),
                );
            } else if cases.is_empty() || !cases.iter().all(reported) {
                self.type_error(
                    f.result.pos,
                    format!("extern error type {} must be an alternative whose cases carry nothing, `code: Int`, `message: String`, or both; the native returns the status 1 + the case index and fills code_out and message_out", self.syms.str(error.name)),
                );
            }
        } else if !result.is(Builtin::Unit) && !crosses_native(self.syms, &result) {
            self.type_error(
                f.result.pos,
                format!("extern result has type {}, which cannot cross the native boundary; an extern returns {CROSSES}, Unit, or a Result of one", self.syms.str(result.name)),
            );
        }
    }

    pub(crate) fn params(&mut self, params: &[ms_syntax::ast::Param]) -> Vec<Param> {
        let mut result = Vec::new();
        let mut seen: HashSet<Name> = HashSet::default();
        for p in params {
            if !seen.insert(p.name) {
                self.type_error(
                    p.pos,
                    format!(
                        "duplicate parameter or field {}; each name may appear once, so rename one",
                        self.syms.str(p.name)
                    ),
                );
            }
            let ty = self.resolve(p.ty.as_ref());
            result.push(Param {
                name: p.name,
                ty,
                mutable: p.mutable,
                positional: false,
            });
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
        let mut defaults: HashSet<Name> = HashSet::default();
        for p in params {
            if p.default.is_some() {
                defaults.insert(p.name);
            }
        }
        let defaults = if defaults.is_empty() {
            None
        } else {
            Some(Rc::new(ParameterDefaults::new(defaults)))
        };
        function_with(self.syms, ps, r, defaults)
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
        // A function returning `Unit` or `Unit!` may end without a `return`: the end returns `unit`
        // or `ok(unit)`.
        let unit_result = result_ty.is(Builtin::Result)
            && result_ty.args.len() == 2
            && self.syms.str(result_ty.args[0].id) == "Unit";
        if fall
            && !is_test
            && !unit_result
            && !result_ty.is(Builtin::Unit)
            && !result_ty.is_invalid()
        {
            self.type_error(
                d.pos(),
                format!(
                    "reachable fallthrough in function returning {rt}; end every path with 'return <{rt}>' (or make the last branch return)",
                    rt = result_ty.display(self.syms)
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
        let fields = d.type_fields();
        if !fields.iter().any(|f| f.default.is_some()) {
            return;
        }
        let old_scope = self.scope.clone();
        let old_result = self.result.clone();
        let old_function = self.function;
        let old_loops = self.loops;
        self.scope = self.variable_scope(&s.variables());
        self.result = Some(s.ty(self.syms));
        self.serial += 1;
        self.function = self.serial;
        self.loops = 0;
        let def_fields = s
            .ty(self.syms)
            .def
            .as_ref()
            .expect("def")
            .fields
            .borrow()
            .clone();
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
        let mut seen: HashSet<Name> = HashSet::default();
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
        let t = factory.ty(self.syms);
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
        let hooks = self.session.test_hooks();
        if !matches!(result.kind, Kind::Type | Kind::Alternative)
            || self.shape_gap_with(&result, &hooks, true).as_deref() != Some("")
        {
            self.type_error(
                decl.pos(),
                "make_fixture must return a concrete type implementing @std/test/test.ms TestHooks; return your fixture type and declare any of fn var Fixture.before_all(), before_each(), after_each() and after_all() with no arguments returning Unit!",
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
        if !m.is_standard(self.syms) {
            for d in &m.decls {
                if matches!(d.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                    continue;
                }
                let name = d.name();
                if matches!(self.syms.str(name), "some" | "none" | "ok" | "error") {
                    self.res_error(
                        d.pos(),
                        format!(
                            "declaration {name_t} reuses a prelude constructor name; rename it, because {name_t} always refers to the prelude case"
                        , name_t = self.syms.str(name)),
                    );
                }
            }
        }
        // `a..b` is parsed as a call of `..`, which is always the standard `range`.
        if let Some(range) = self
            .session
            .standard_module_symbol(n("@std/collections/collections.ms"), n("range"))
        {
            self.names.borrow_mut().insert(n(".."), range);
        }
        for (path, name) in crate::stdlib::STANDARD_PRELUDE_FUNCTIONS {
            let nm = n(name);
            let pn = n(path);
            let explicit = m
                .imports
                .iter()
                .any(|i| i.name == nm && i.path.starts_with("@std/"));
            // Standard modules import it explicitly: resolving the twin from inside one would be a dependency cycle.
            if m.is_standard(self.syms) || explicit {
                continue;
            }
            // The function has a body, so it lives in the module's source twin.
            let import = crate::stdlib::prelude_function_import(path, name);
            let found = self.session.standard_module_symbol(pn, nm).or_else(|| {
                let twin = self.session.import_source(&import)?;
                self.session
                    .ensure_source(&twin)
                    .ok()?
                    .exports
                    .get(&nm)
                    .filter(|s| s.module == twin.file)
                    .cloned()
            });
            if let Some(symbol) = found {
                self.names.borrow_mut().insert(nm, symbol);
            }
        }
        for name in crate::stdlib::STANDARD_PRELUDE_NAMES {
            let nm = n(name);
            let Some(symbol) = self.session.standard_symbol(name) else {
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
    use std::fmt::Write;
    s.bytes()
        .fold(String::with_capacity(s.len() * 2), |mut out, b| {
            let _ = write!(out, "{b:02x}");
            out
        })
}

/// Drops repeats of one message at one position.
pub fn unique_diagnostics(diagnostics: Vec<Diagnostic>) -> Vec<Diagnostic> {
    let mut seen: HashSet<(String, Pos, String)> = HashSet::default();
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
pub fn self_variable(syms: ms_syntax::Names, owner: Name) -> Ty {
    Rc::new(Type::with_builtin(
        n("Self"),
        n(&format!("{owner_t}/Self", owner_t = syms.str(owner))),
        Kind::Variable,
        Some(Builtin::SelfType),
    ))
}

#[cfg(test)]
#[path = "operation_bounds_tests.rs"]
mod operation_bounds_tests;

/// Whether a value of `t` crosses to a user `extern fn` shim (`ms_abi.h`): sized numbers,
/// `Bool`, `String`, `Bytes`, an `extern type` the program declares, or a `List` of those.
pub(crate) fn crosses_native(syms: ms_syntax::Names, t: &Ty) -> bool {
    if t.is(Builtin::List) && t.args.len() == 1 {
        return crosses_element(syms, &t.args[0]);
    }
    crosses_element(syms, t)
}

fn crosses_element(syms: ms_syntax::Names, t: &Ty) -> bool {
    const SCALARS: [&str; 13] = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64", "Float",
        "Float32", "Bool", "String",
    ];
    SCALARS.contains(&syms.str(t.id)) || t.is(Builtin::Bytes) || is_user_extern_type(syms, t)
}

/// The most parameters a function passed to a user extern may take (`ms_call` packs the
/// signature in one word; `ms_rt_abi::CALL_MAX_PARAMS`).
pub(crate) const MAX_CALLBACK_PARAMS: usize = 6;

/// Whether the function type `t` can be passed to a user extern as an `ms_fn`.
fn crosses_callback(syms: ms_syntax::Names, t: &Ty) -> bool {
    let result_ok = t.result.as_ref().is_none_or(|r| {
        r.is(Builtin::Unit) || (crosses_element(syms, r) && !is_user_extern_type(syms, r))
    });
    t.params.len() <= MAX_CALLBACK_PARAMS
        && t.params.iter().all(|p| crosses_element(syms, &p.ty))
        && result_ok
}

/// Whether `t` is an `extern type` declared outside the standard library.
pub(crate) fn is_user_extern_type(syms: ms_syntax::Names, t: &Ty) -> bool {
    t.kind == Kind::Native && t.args.is_empty() && syms.str(t.id).starts_with("extern:")
}

/// Appends every name a written type mentions, including type arguments and function parts.
fn named_types(t: &TypeRef, out: &mut Vec<Name>) {
    match &t.kind {
        TypeKind::Named { name, args } => {
            out.push(*name);
            for arg in args {
                named_types(arg, out);
            }
        }
        TypeKind::Fn { params, result } => {
            for ty in params.iter().filter_map(|p| p.ty.as_ref()) {
                named_types(ty, out);
            }
            named_types(result, out);
        }
    }
}

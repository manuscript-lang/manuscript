//! The bundled standard declarations.
//!
//! `stdlib/*.ms` and `bindings.json` are embedded unchanged. Native
//! modules (declarations without bodies) are declared once per thread; source
//! modules (declarations with bodies) are checked lazily with the ordinary
//! checker and shared by every program.

use crate::checker::{CheckOptions, Checker, Names};
use crate::json;
use crate::receivers::RECEIVER_BINDINGS;
use crate::syntax::*;
use crate::types::Case;
use crate::types::*;
use ms_syntax::ast::Method;
use ms_syntax::ast::*;
use ms_syntax::{Diagnostic, Phase};
use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap, HashSet};
use std::rc::Rc;
use std::sync::Arc;

include!(concat!(env!("OUT_DIR"), "/std_sources.rs"));

/// Source-backed prelude types retain their standard declaration identities.
pub const STANDARD_PRELUDE_NAMES: [&str; 14] = [
    "Equal",
    "Comparable",
    "Hashable",
    "Clonable",
    "Optional",
    "Result",
    "Error",
    "List",
    "Map",
    "Set",
    "CollectionError",
    "ListEntry",
    "MapEntry",
    "MissingValue",
];

/// The built-in types every module sees without an import.
pub const PRIMITIVE_NAMES: [&str; 6] = ["Bool", "Int", "Float", "String", "Unit", "Never"];

/// The result of checking one bundled source module.
pub struct StdResult {
    /// Module-level symbols visible in the module.
    pub symbols: Names,
    /// Symbols the module declares.
    pub exports: HashMap<Name, SymRef>,
    /// Methods the module implements.
    pub methods: Vec<MethodRef>,
}

/// A receiver requirement: the variable and the constraint it must meet.
#[derive(Clone)]
pub struct ReceiverRequirement {
    /// The receiver variable.
    pub variable: Ty,
    /// The contracts or types it may satisfy; any one suffices.
    pub constraints: Vec<Ty>,
}

#[derive(Default)]
struct World {
    state: u8, // 0 unloaded, 1 loading, 2 loaded
    symbols: HashMap<Name, SymRef>,
    modules: HashMap<Name, HashMap<Name, SymRef>>,
    module_order: Vec<Name>,
    sources: Vec<ModRef>,
    source_modules: HashMap<Name, ModRef>,
    intrinsic: HashMap<Name, Ty>,
    implementations: Vec<MethodRef>,
    operation_variables: HashMap<String, Vec<Ty>>,
    receiver_bindings: HashMap<String, Name>,
    receiver_requirements: HashMap<String, Vec<ReceiverRequirement>>,
    runtime_symbols: HashMap<String, String>,
    done: HashMap<Name, Rc<StdResult>>,
    checking: HashSet<Name>,
}

thread_local! {
    static WORLD: RefCell<World> = RefCell::new(World::default());
}

fn world<R>(f: impl FnOnce(&mut World) -> R) -> R {
    WORLD.with(|w| f(&mut w.borrow_mut()))
}

#[derive(Default)]
struct Bindings {
    native_types: HashMap<String, String>,
    function_overrides: HashMap<String, String>,
    intrinsic_receivers: HashMap<String, String>,
    contract_methods: HashMap<String, String>,
    receiver_requirements: HashMap<String, HashMap<String, String>>,
    runtime_symbols: HashMap<String, String>,
}

fn read_bindings() -> Result<Bindings, String> {
    let root = json::parse(BINDINGS)?;
    let entries = root.entries();
    let strings = |key: &str| -> HashMap<String, String> {
        entries
            .get(key)
            .map(|v| {
                v.entries()
                    .into_iter()
                    .map(|(k, v)| (k, v.text().to_string()))
                    .collect()
            })
            .unwrap_or_default()
    };
    let mut requirements: HashMap<String, HashMap<String, String>> = HashMap::new();
    if let Some(v) = entries.get("receiver_requirements") {
        for (key, inner) in v.entries() {
            requirements.insert(
                key,
                inner
                    .entries()
                    .into_iter()
                    .map(|(k, v)| (k, v.text().to_string()))
                    .collect(),
            );
        }
    }
    Ok(Bindings {
        native_types: strings("native_types"),
        function_overrides: strings("function_overrides"),
        intrinsic_receivers: strings("intrinsic_receivers"),
        contract_methods: strings("contract_methods"),
        receiver_requirements: requirements,
        runtime_symbols: strings("runtime_symbols"),
    })
}

// -------------------------------------------------------------------- queries

/// Loads the standard declarations on first use.
pub fn ensure_standard() {
    let state = world(|w| w.state);
    if state != 0 {
        return;
    }
    world(|w| w.state = 1);
    if let Err(e) = load() {
        panic!("standard declarations: {e}");
    }
    world(|w| w.state = 2);
}

/// Every bundled module (native and source) in file-name order, with the
/// original source text, for editors that show standard declarations.
pub fn standard_modules() -> Vec<ModRef> {
    ensure_standard();
    world(|w| w.sources.clone())
}

/// A standard type declared natively or as source, by name.
pub fn standard_symbol(name: &str) -> Option<SymRef> {
    ensure_standard();
    world(|w| w.symbols.get(&n(name)).cloned())
}

/// Whether a symbol is a canonical source-backed prelude declaration.
pub fn is_prelude_symbol(symbol: &SymRef) -> bool {
    if !STANDARD_PRELUDE_NAMES.contains(&symbol.name.as_str()) {
        return false;
    }
    world(|w| {
        w.symbols
            .get(&symbol.name)
            .is_some_and(|s| Rc::ptr_eq(s, symbol))
    })
}

/// Native implementations of contracts for standard types.
pub fn standard_implementations() -> Vec<MethodRef> {
    ensure_standard();
    world(|w| w.implementations.clone())
}

/// The intrinsic declaration for a primitive receiver id.
pub fn intrinsic_operations(id: Name) -> Option<Ty> {
    ensure_standard();
    world(|w| w.intrinsic.get(&id).cloned())
}

/// The native identity of a receiver operation (`Receiver id/name`).
pub fn receiver_binding(key: &str) -> Option<Name> {
    world(|w| w.receiver_bindings.get(key).copied())
}

/// The runtime symbol that implements a native function (`module/name`), as bindings.json names it.
pub fn runtime_symbol(native: &str) -> Option<String> {
    ensure_standard();
    world(|w| w.runtime_symbols.get(native).cloned())
}

/// Requirements a native receiver operation puts on its receiver.
pub fn receiver_requirements(key: &str) -> Vec<ReceiverRequirement> {
    world(|w| {
        w.receiver_requirements
            .get(key)
            .cloned()
            .unwrap_or_default()
    })
}

/// The operation's own type variables (`Receiver id/name`).
pub fn operation_variables(key: &str) -> Vec<Ty> {
    world(|w| w.operation_variables.get(key).cloned().unwrap_or_default())
}

/// Whether a bundled module is a source module (it has bodies).
pub fn is_source_module(module: &ModRef) -> bool {
    world(|w| {
        w.source_modules
            .get(&module.file)
            .is_some_and(|m| Rc::ptr_eq(m, module))
    })
}

/// A bundled source module by path.
pub fn standard_source_module(path: Name) -> Option<ModRef> {
    ensure_standard();
    world(|w| w.source_modules.get(&path).cloned())
}

/// Whether the path names a native bundled module.
pub fn is_native_module(path: Name) -> bool {
    ensure_standard();
    world(|w| w.modules.contains_key(&path))
}

/// A native module's declaration by name.
pub fn standard_module_symbol(path: Name, name: Name) -> Option<SymRef> {
    ensure_standard();
    world(|w| {
        w.modules
            .get(&path)
            .and_then(|m| m.get(&name).cloned())
            // An `extern type` of a source module is canonical from the moment of loading.
            .or_else(|| {
                w.symbols
                    .get(&name)
                    .filter(|s| {
                        s.module == path && s.export && w.source_modules.contains_key(&path)
                    })
                    .cloned()
            })
    })
}

/// Every bundled module path in sorted order.
pub fn standard_module_names() -> Vec<&'static str> {
    ensure_standard();
    let mut names: BTreeSet<&'static str> = BTreeSet::new();
    world(|w| {
        names.extend(w.modules.keys().map(|k| k.as_str()));
        names.extend(w.source_modules.keys().map(|k| k.as_str()));
    });
    names.into_iter().collect()
}

/// A standard module's exported declarations, checking a bundled source
/// module on first use.
pub fn standard_exports(path: &str) -> HashMap<Name, SymRef> {
    let path = n(path);
    if let Some(module) = standard_source_module(path) {
        return ensure_source(&module)
            .exports
            .iter()
            .filter(|(_, s)| s.export)
            .map(|(k, v)| (*k, v.clone()))
            .collect();
    }
    world(|w| {
        w.modules
            .get(&path)
            .map(|m| {
                m.iter()
                    .filter(|(_, s)| s.export)
                    .map(|(k, v)| (*k, v.clone()))
                    .collect()
            })
            .unwrap_or_default()
    })
}

/// The checked result of a bundled source module, if it has been checked.
pub fn done(file: Name) -> Option<Rc<StdResult>> {
    world(|w| w.done.get(&file).cloned())
}

/// Checks a bundled source module and the bundled modules it imports, once.
pub fn ensure_source(module: &ModRef) -> Rc<StdResult> {
    ensure_standard();
    if let Some(r) = done(module.file) {
        return r;
    }
    let cycle = world(|w| !w.checking.insert(module.file));
    if cycle {
        panic!("cyclic standard source dependency at {}", module.file);
    }
    for item in &module.imports {
        if let Some(dep) = standard_source_module(n(&item.path)) {
            ensure_source(&dep);
        }
    }
    let mut checker = Checker::new(&CheckOptions {
        bundled: Some(module.file),
        ..CheckOptions::default()
    });
    checker.id_scope = format!(
        "standard_{}_",
        module
            .file
            .as_str()
            .trim_start_matches("@std/")
            .trim_end_matches(".ms")
    );
    let program = checker.check_modules(vec![module.clone()], Some(module.file));
    if !program.diagnostics.is_empty() {
        let text: Vec<String> = program.diagnostics.iter().map(|d| d.to_string()).collect();
        panic!(
            "invalid standard implementation {}: {}",
            module.file,
            text.join("; ")
        );
    }
    let symbols = program
        .symbols
        .get(&module.file)
        .cloned()
        .expect("module symbols");
    let exports: HashMap<Name, SymRef> = symbols
        .borrow()
        .iter()
        .filter(|(_, s)| s.module == module.file)
        .map(|(k, v)| (*k, v.clone()))
        .collect();
    let methods: Vec<MethodRef> = program
        .methods
        .iter()
        .filter(|m| m.module == module.file)
        .cloned()
        .collect();
    let result = Rc::new(StdResult {
        symbols,
        exports,
        methods,
    });
    world(|w| {
        w.done.insert(module.file, result.clone());
        w.checking.remove(&module.file);
    });
    result
}

/// All bundled source modules, checked.
pub fn ensure_all_sources() {
    ensure_standard();
    let sources: Vec<ModRef> = world(|w| w.sources.clone());
    for m in sources {
        if is_source_module(&m) {
            ensure_source(&m);
        }
    }
}

/// The declaration of a standard type's operation.
pub fn standard_method_declaration(t: &Ty, name: Name) -> Option<FuncRef> {
    let sym = t.def.as_ref()?.symbol()?;
    let decl = sym.decl.clone()?;
    decl.method_named(name)
}

/// Adds reachable bundled implementations to a module list in dependency order.
pub fn source_standard_dependencies(modules: Vec<ModRef>) -> (Vec<ModRef>, Vec<Diagnostic>) {
    let mut ordered: Vec<ModRef> = Vec::new();
    let mut diagnostics: Vec<Diagnostic> = Vec::new();
    let mut state: HashMap<Name, u8> = HashMap::new();
    fn visit(
        module: &ModRef,
        state: &mut HashMap<Name, u8>,
        ordered: &mut Vec<ModRef>,
        diagnostics: &mut Vec<Diagnostic>,
    ) {
        match state.get(&module.file) {
            Some(2) => return,
            Some(1) => {
                diagnostics.push(Diagnostic {
                    file: Arc::from(module.file.as_str()),
                    pos: ms_syntax::Pos::new(0, 1, 1),
                    phase: Phase::Resolution,
                    message: "cyclic standard source dependency".to_string(),
                    end: None,
                    fix: None,
                });
                return;
            }
            _ => {}
        }
        state.insert(module.file, 1);
        for item in &module.imports {
            if let Some(dep) = standard_source_module(n(&item.path)) {
                visit(&dep, state, ordered, diagnostics);
            }
        }
        state.insert(module.file, 2);
        ordered.push(module.clone());
    }
    for m in &modules {
        visit(m, &mut state, &mut ordered, &mut diagnostics);
    }
    (ordered, diagnostics)
}

// --------------------------------------------------------------------- loading

fn decl_name(d: &Decl) -> Name {
    match &d.kind {
        DeclKind::Fn(f) => f.name,
        DeclKind::Const(c) => c.name,
        DeclKind::Record(r) => r.name,
        DeclKind::Alternative(a) => a.name,
        DeclKind::Interface(i) => i.name,
        DeclKind::Impl(_) | DeclKind::Test(_) => n(""),
    }
}

fn decl_type_params(d: &Decl) -> &[TypeParam] {
    match &d.kind {
        DeclKind::Fn(f) => &f.type_params,
        DeclKind::Record(r) => &r.type_params,
        DeclKind::Alternative(a) => &a.type_params,
        DeclKind::Interface(i) => &i.type_params,
        _ => &[],
    }
}

fn fold_inherent_impls(module: &Module) -> Result<Vec<DeclRef>, String> {
    let mut kept: Vec<(Decl, Vec<Method>)> = Vec::new();
    let mut types: HashMap<Name, usize> = HashMap::new();
    for d in &module.decls {
        if matches!(&d.kind, DeclKind::Impl(i) if i.contract.is_none()) {
            continue;
        }
        if !matches!(
            d.kind,
            DeclKind::Impl(_) | DeclKind::Test(_) | DeclKind::Fn(_) | DeclKind::Const(_)
        ) {
            types.insert(decl_name(d), kept.len());
        }
        kept.push((d.clone(), Vec::new()));
    }
    for d in &module.decls {
        let DeclKind::Impl(i) = &d.kind else {
            continue;
        };
        if i.contract.is_some() {
            continue;
        }
        let at = || position_text(n(&module.file), d.pos);
        let idx = match types.get(&n(i.receiver.name())) {
            Some(&idx) if !matches!(kept[idx].0.kind, DeclKind::Interface(_)) => idx,
            _ => {
                return Err(format!(
                    "inherent impl must name a type declared in the same module: {}",
                    at()
                ));
            }
        };
        let params = decl_type_params(&kept[idx].0);
        let args: &[TypeRef] = match &i.receiver.kind {
            TypeKind::Named { args, .. } => args,
            TypeKind::Fn { .. } => &[],
        };
        let repeats = args.len() == params.len()
            && args.iter().zip(params).all(|(a, p)| match &a.kind {
                TypeKind::Named { name, args } => *name == p.name && args.is_empty(),
                TypeKind::Fn { .. } => false,
            });
        if !repeats {
            return Err(format!(
                "inherent impl must repeat the type parameters of {}: {}",
                decl_name(&kept[idx].0),
                at()
            ));
        }
        let methods = i.methods.clone();
        kept[idx].1.extend(methods);
    }
    Ok(kept
        .into_iter()
        .map(|(decl, folded)| DeclRef(Rc::new(DeclNode { decl, folded })))
        .collect())
}

fn has_implementation(d: &DeclRef) -> bool {
    let own = match &d.decl().kind {
        DeclKind::Fn(f) => !f.body.is_empty(),
        DeclKind::Const(_) => true,
        DeclKind::Test(t) => !t.body.is_empty(),
        _ => false,
    };
    own || d.methods().iter().any(|m| !m.func.body.is_empty())
}

/// Whether any inherent `impl Type:` block in `module` has a method with a body.
fn has_inherent_body(module: &Module) -> bool {
    module.decls.iter().any(|d| {
        matches!(&d.kind, DeclKind::Impl(i) if i.contract.is_none()
            && i.methods.iter().any(|m| !m.func.body.is_empty()))
    })
}

fn load() -> Result<(), String> {
    let bindings = read_bindings()?;
    world(|w| w.runtime_symbols = bindings.runtime_symbols.clone());
    let mut modules: Vec<ModRef> = Vec::new();
    for (name, source) in SOURCES {
        let file: Arc<str> = Arc::from(format!("@std/{name}").as_str());
        let parsed =
            ms_syntax::parser::parse(&file, source).map_err(|d| format!("parse {file}: {d}"))?;
        // A module with implementation bodies is checked like user source, so its inherent
        // methods take the same desugaring and become ordinary methods wherever the type is used.
        if has_inherent_body(&parsed) {
            modules.push(crate::load_module(&parsed));
            continue;
        }
        let decls = fold_inherent_impls(&parsed)?;
        let data = ModuleData::new(&parsed, decls, parsed.node_count);
        modules.push(Rc::new(data));
    }
    let mut checker = Checker::new(&CheckOptions::default());
    checker.standard_declarations = true;
    let mut loader = Loader {
        bindings,
        c: &mut checker,
    };
    for module in &modules {
        loader.register(module)?;
    }
    loader.declare_identities();
    loader.resolve_declarations();
    loader.bind_implementations()?;
    loader.bind_receivers()?;
    loader.check_defaults()?;
    Ok(())
}

struct Loader<'a> {
    bindings: Bindings,
    c: &'a mut Checker,
}

fn position_text(file: Name, pos: ms_syntax::Pos) -> String {
    format!("{}:{}:{}", file, pos.line, pos.column)
}

impl Loader<'_> {
    /// The canonical symbol of an `extern type` declared in a bundled source module.
    fn register_extern_type(&mut self, module: &ModRef, d: &DeclRef) -> Result<(), String> {
        let name = d.name();
        if !d.type_params().is_empty() {
            return Err(format!(
                "extern types cannot be generic yet: {}",
                position_text(module.file, d.pos())
            ));
        }
        let id = n(&format!("@std/{name}"));
        let s = Rc::new(Sym {
            name,
            id,
            kind: SymKind::Type,
            module: module.file,
            native: name,
            export: d.decl().export,
            ty: RefCell::new(None),
            variables: RefCell::new(Vec::new()),
            decl: Some(d.clone()),
        });
        let def = Definition::new(&s, Kind::Native);
        let mut t = Type::new(name, id, Kind::Native);
        t.def = Some(def);
        *s.ty.borrow_mut() = Some(Rc::new(t));
        if world(|w| w.symbols.contains_key(&name)) {
            return Err(format!("duplicate standard type {name}"));
        }
        world(|w| w.symbols.insert(name, s));
        Ok(())
    }

    fn register(&mut self, module: &ModRef) -> Result<(), String> {
        world(|w| w.sources.push(module.clone()));
        let source_implementation = module.decls.iter().any(has_implementation);
        if source_implementation {
            for d in &module.decls {
                if matches!(&d.decl().kind, DeclKind::Record(r) if r.external) {
                    self.register_extern_type(module, d)?;
                }
            }
            world(|w| {
                w.source_modules.insert(module.file, module.clone());
            });
            return Ok(());
        }
        let mut symbols: HashMap<Name, SymRef> = HashMap::new();
        for d in &module.decls {
            if let DeclKind::Impl(i) = &d.decl().kind {
                for method in &i.methods {
                    if !method.func.body.is_empty() {
                        return Err(format!(
                            "native implementations must not have bodies: {}",
                            position_text(module.file, method.pos)
                        ));
                    }
                }
                continue;
            }
            if matches!(d.decl().kind, DeclKind::Test(_)) {
                return Err(format!(
                    "standard declarations cannot contain implementation bodies: {}",
                    position_text(module.file, d.pos())
                ));
            }
            if has_implementation(d) {
                return Err(format!(
                    "native declarations must not have bodies: {}",
                    position_text(module.file, d.pos())
                ));
            }
            let name = d.name();
            let (kind, sym_kind) = match &d.decl().kind {
                DeclKind::Fn(_) => (None, SymKind::Fn),
                DeclKind::Record(_) => (Some(Kind::Record), SymKind::Type),
                DeclKind::Alternative(_) => (Some(Kind::Alternative), SymKind::Type),
                DeclKind::Interface(_) => (Some(Kind::Contract), SymKind::Type),
                _ => (None, SymKind::Type),
            };
            let mut id = n(&format!("@std/{name}"));
            let mut native = name;
            if sym_kind == SymKind::Fn {
                // Identities are module/name unless bindings.json overrides them.
                let mut ident = format!(
                    "{}/{}",
                    module
                        .file
                        .as_str()
                        .trim_start_matches("@std/")
                        .trim_end_matches(".ms"),
                    name
                );
                if let Some(o) = self
                    .bindings
                    .function_overrides
                    .get(&format!("{}/{}", module.file, name))
                    .filter(|o| !o.is_empty())
                {
                    ident = o.clone();
                }
                native = n(&ident);
                id = n(&format!("@std/{ident}"));
            }
            let s = Rc::new(Sym {
                name,
                id,
                kind: sym_kind,
                module: module.file,
                native,
                export: d.decl().export,
                ty: RefCell::new(None),
                variables: RefCell::new(Vec::new()),
                decl: Some(d.clone()),
            });
            if let Some(mut kind) = kind {
                if let Some(nk) = self
                    .bindings
                    .native_types
                    .get(&format!("{}/{}", module.file, name))
                    .filter(|k| !k.is_empty())
                {
                    kind = match nk.as_str() {
                        "native" => Kind::Native,
                        "record" => Kind::Record,
                        "alternative" => Kind::Alternative,
                        "contract" => Kind::Contract,
                        other => return Err(format!("unknown native kind {other}")),
                    };
                }
                let def = Definition::new(&s, kind);
                let mut t = Type::new(name, id, kind);
                t.def = Some(def);
                *s.ty.borrow_mut() = Some(Rc::new(t));
                let duplicate = world(|w| w.symbols.contains_key(&name));
                if duplicate {
                    return Err(format!("duplicate standard type {name}"));
                }
                world(|w| w.symbols.insert(name, s.clone()));
            }
            if symbols.contains_key(&name) {
                return Err(format!(
                    "duplicate standard declaration {}",
                    position_text(module.file, d.pos())
                ));
            }
            symbols.insert(name, s);
        }
        world(|w| {
            w.modules.insert(module.file, symbols);
            w.module_order.push(module.file);
        });
        Ok(())
    }

    fn native_sources(&self) -> Vec<ModRef> {
        world(|w| {
            w.sources
                .iter()
                .filter(|m| !w.source_modules.contains_key(&m.file))
                .cloned()
                .collect()
        })
    }

    fn module_symbol(&self, module: &ModRef, d: &DeclRef) -> SymRef {
        world(|w| {
            w.modules
                .get(&module.file)
                .and_then(|m| m.get(&d.name()))
                .cloned()
                .expect("registered symbol")
        })
    }

    /// Opens the declaration scope of a native module: primitives, the
    /// prelude, its imports, and its own declarations.
    fn scope_module(&mut self, module: &ModRef) {
        let c = &mut *self.c;
        c.module = Some(module.clone());
        c.names = Rc::new(RefCell::new(HashMap::new()));
        c.scope = crate::checker::Scope::new(None);
        for name in PRIMITIVE_NAMES {
            let nm = n(name);
            let s = Rc::new(Sym {
                name: nm,
                id: nm,
                kind: SymKind::Type,
                module: n(""),
                native: n(""),
                export: true,
                ty: RefCell::new(Some(primitive(name))),
                variables: RefCell::new(Vec::new()),
                decl: None,
            });
            c.names.borrow_mut().insert(nm, s);
        }
        c.add_standard_prelude();
        for item in &module.imports {
            let found = standard_module_symbol(n(&item.path), item.name);
            let Some(found) = found.filter(|f| f.export) else {
                c.res_error(
                    item.name_pos,
                    format!("standard module does not export {}", item.name),
                );
                continue;
            };
            if is_prelude_symbol(&found) {
                c.redundant_prelude_import(module, item);
            }
            c.add_symbol(item.name, found, item.name_pos);
        }
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_)) {
                continue;
            }
            let s = world(|w| {
                w.modules
                    .get(&module.file)
                    .and_then(|m| m.get(&d.name()))
                    .cloned()
            });
            if let Some(s) = s {
                c.add_symbol(d.name(), s, d.pos());
            }
        }
    }

    /// Declares every native nominal identity before any is resolved.
    fn declare_identities(&mut self) {
        for module in self.native_sources() {
            self.scope_module(&module);
            for d in &module.decls {
                if matches!(d.decl().kind, DeclKind::Impl(_)) {
                    continue;
                }
                let s = self.module_symbol(&module, d);
                self.c.scope = crate::checker::Scope::new(None);
                let mut vars: Vec<Ty> = Vec::new();
                for p in d.type_params() {
                    let v: Ty = Rc::new(Type::new(
                        p.name,
                        n(&format!("{}/{}", s.id, p.name)),
                        Kind::Variable,
                    ));
                    vars.push(v.clone());
                    self.c.scope.types.borrow_mut().insert(p.name, v);
                }
                *s.variables.borrow_mut() = vars.clone();
                if s.kind == SymKind::Type {
                    let t = s.ty();
                    *t.def.as_ref().expect("def").variables.borrow_mut() = vars.clone();
                    *s.ty.borrow_mut() = Some(with_args(&t, vars));
                }
            }
        }
    }

    /// Fills in native type variables, fields, cases, and operation signatures.
    fn resolve_declarations(&mut self) {
        for module in self.native_sources() {
            self.scope_module(&module);
            for d in &module.decls {
                if matches!(d.decl().kind, DeclKind::Impl(_)) {
                    continue;
                }
                let s = self.module_symbol(&module, d);
                let vars = s.variables();
                self.c.scope = self.c.variable_scope(&vars);
                for (i, p) in d.type_params().iter().enumerate() {
                    for bound in &p.bounds {
                        let t = self.c.resolve(Some(bound));
                        vars[i].bounds.borrow_mut().push(t);
                    }
                }
                self.c.type_defaults(d.type_params(), &vars);
                if s.kind == SymKind::Fn {
                    let f = d.func().expect("fn");
                    let t = self.c.signature(&f.params, Some(&f.result));
                    *s.ty.borrow_mut() = Some(t);
                    continue;
                }
                let def = s.ty().def.clone().expect("def");
                let fields = self.c.params(d.record_fields());
                *def.fields.borrow_mut() = fields;
                let mut seen: HashSet<Name> = HashSet::new();
                for cs in d.cases() {
                    if !seen.insert(cs.name) {
                        self.c
                            .type_error(cs.pos, format!("duplicate case {}", cs.name));
                    }
                    let fields = self.c.params(&cs.fields);
                    def.cases.borrow_mut().push(Case {
                        name: cs.name,
                        fields,
                    });
                }
                let mut seen: HashSet<Name> = HashSet::new();
                for (mi, method) in d.methods().iter().enumerate() {
                    if !seen.insert(method.func.name) {
                        self.c.type_error(
                            method.pos,
                            format!("duplicate operation {}", method.func.name),
                        );
                    }
                    self.c.scope = self.c.variable_scope(&vars);
                    let mut variables: Vec<Ty> = Vec::new();
                    for param in &method.func.type_params {
                        if self.c.scope.types.borrow().contains_key(&param.name) {
                            self.c.type_error(
                                param.pos,
                                "native method variable shadows receiver variable",
                            );
                        }
                        let v: Ty = Rc::new(Type::new(
                            param.name,
                            n(&format!("{}/{}/{}", s.id, method.func.name, param.name)),
                            Kind::Variable,
                        ));
                        variables.push(v.clone());
                        self.c.scope.types.borrow_mut().insert(param.name, v);
                    }
                    for (i, param) in method.func.type_params.iter().enumerate() {
                        for bound in &param.bounds {
                            let t = self.c.resolve(Some(bound));
                            variables[i].bounds.borrow_mut().push(t);
                        }
                    }
                    self.c.type_defaults(&method.func.type_params, &variables);
                    world(|w| {
                        w.operation_variables
                            .insert(format!("{}/{}", s.id, method.func.name), variables.clone());
                    });
                    let ty = self
                        .c
                        .signature(&method.func.params, Some(&method.func.result));
                    def.operations.borrow_mut().push(Operation {
                        name: method.func.name,
                        ty,
                        decl: Some(FuncRef {
                            decl: d.clone(),
                            index: Some(mi),
                        }),
                    });
                }
            }
        }
    }

    /// Checks native impl blocks and ties each to its binding.
    fn bind_implementations(&mut self) -> Result<(), String> {
        let mut used: HashSet<String> = HashSet::new();
        for module in self.native_sources() {
            self.scope_module(&module);
            for d in &module.decls {
                let DeclKind::Impl(imp) = &d.decl().kind else {
                    continue;
                };
                let start = self.c.p.methods.len();
                self.c.implementation(d);
                let receiver_name = imp.receiver.name().to_string();
                let contract_name = imp
                    .contract
                    .as_ref()
                    .map(|c| c.name().to_string())
                    .unwrap_or_default();
                for index in start..self.c.p.methods.len() {
                    let mut method = (*self.c.p.methods[index]).clone();
                    let name = method.name().expect("method name");
                    let key = format!(
                        "{}/{}/{}/{}",
                        module.file, receiver_name, contract_name, name
                    );
                    method.id = n(&key);
                    let contract = format!("{contract_name}/{name}");
                    let native = self
                        .bindings
                        .contract_methods
                        .get(&contract)
                        .cloned()
                        .unwrap_or_default();
                    if native.is_empty() {
                        return Err(format!(
                            "missing native implementation binding for {contract}: {}",
                            position_text(module.file, method.decl.as_ref().expect("decl").pos())
                        ));
                    }
                    method.native = n(&native);
                    used.insert(contract);
                    self.c.p.methods[index] = Rc::new(method);
                }
            }
        }
        for contract in self.bindings.contract_methods.keys() {
            if !used.contains(contract) {
                return Err(format!("unused native implementation binding: {contract}"));
            }
        }
        let implementations = self.c.p.methods.clone();
        world(|w| w.implementations = implementations);
        if !self.c.p.diagnostics.is_empty() {
            let text: Vec<String> = self.c.p.diagnostics.iter().map(|d| d.to_string()).collect();
            return Err(format!(
                "invalid standard declarations: {}",
                text.join("; ")
            ));
        }
        for (receiver, name) in &self.bindings.intrinsic_receivers {
            let Some(typ) = world(|w| w.symbols.get(&n(name)).cloned()) else {
                return Err(format!("missing intrinsic receiver declaration {name}"));
            };
            world(|w| w.intrinsic.insert(n(receiver), typ.ty()));
        }
        Ok(())
    }

    /// Attaches native receiver bindings and their requirements.
    fn bind_receivers(&mut self) -> Result<(), String> {
        let intrinsic_names: HashMap<String, String> = self
            .bindings
            .intrinsic_receivers
            .iter()
            .map(|(r, name)| (name.clone(), r.clone()))
            .collect();
        let mut bound: HashSet<String> = HashSet::new();
        let mut requirements = self.bindings.receiver_requirements.clone();
        for module in self.native_sources() {
            self.scope_module(&module);
            for declaration in &module.decls {
                if matches!(declaration.decl().kind, DeclKind::Impl(_)) {
                    continue;
                }
                let symbol = self.module_symbol(&module, declaration);
                let mut receiver = declaration.name().to_string();
                if let Some(name) = intrinsic_names.get(&receiver) {
                    receiver = name.clone();
                }
                for method in declaration.methods() {
                    let mname = method.func.name;
                    let key = format!("{}/{}/{}", module.file, declaration.name(), mname);
                    let sym_key = format!("{}/{}", symbol.id, mname);
                    let native = RECEIVER_BINDINGS
                        .iter()
                        .find(|(r, _)| *r == receiver)
                        .and_then(|(_, ops)| ops.iter().find(|(o, _)| *o == mname.as_str()))
                        .map(|(_, id)| *id);
                    if let Some(native) = native {
                        world(|w| w.receiver_bindings.insert(sym_key.clone(), n(native)));
                        bound.insert(format!("{receiver}.{mname}"));
                    }
                    if let Some(reqs) = requirements.remove(&key) {
                        let mut names: Vec<(String, String)> = reqs.into_iter().collect();
                        names.sort();
                        for (name, constraint) in names {
                            if receiver_binding(&sym_key).is_none() {
                                return Err(format!(
                                    "receiver requirement needs a native binding: {key}"
                                ));
                            }
                            let variable = symbol
                                .variables()
                                .into_iter()
                                .find(|c| c.name.as_str() == name);
                            let Some(variable) = variable else {
                                return Err(format!("unknown receiver variable {name} in {key}"));
                            };
                            let mut constraints = Vec::new();
                            for alternative in constraint.split('|') {
                                let required = self
                                    .c
                                    .sym(n(alternative))
                                    .filter(|r| r.kind == SymKind::Type);
                                let Some(required) = required else {
                                    return Err(format!(
                                        "unknown receiver requirement {constraint} in {key}"
                                    ));
                                };
                                constraints.push(required.ty());
                            }
                            world(|w| {
                                w.receiver_requirements
                                    .entry(sym_key.clone())
                                    .or_default()
                                    .push(ReceiverRequirement {
                                        variable,
                                        constraints,
                                    })
                            });
                        }
                    }
                }
            }
        }
        for (receiver, ops) in RECEIVER_BINDINGS {
            for (name, _) in ops.iter() {
                if !bound.contains(&format!("{receiver}.{name}")) {
                    return Err(format!("unused native receiver binding: {receiver}.{name}"));
                }
            }
        }
        if let Some(key) = requirements.keys().next() {
            return Err(format!("unused native receiver requirement: {key}"));
        }
        Ok(())
    }

    /// Checks native default expressions and folds their constants.
    fn check_defaults(&mut self) -> Result<(), String> {
        let deferred = std::mem::take(&mut self.c.deferred_default_bounds);
        for check in deferred {
            if !self.c.satisfies(&check.resolved, &check.bound) {
                let msg = self.c.unsatisfied_message(
                    &check.resolved,
                    &check.bound,
                    "choose a default that already implements it",
                );
                self.c.module = Some(check.module.clone());
                self.c.type_error(check.pos, msg);
            }
        }
        // Check native default expressions with the ordinary expression checker.
        // Lowering prepares concrete slots before native dispatch; the runtime does
        // not own a second default-expression schema.
        for module in self.native_sources() {
            self.scope_module(&module);
            for declaration in &module.decls {
                if matches!(declaration.decl().kind, DeclKind::Impl(_)) {
                    continue;
                }
                let symbol = self.module_symbol(&module, declaration);
                if symbol.kind == SymKind::Fn {
                    let f = declaration.func().expect("fn");
                    self.c.check_native_defaults(
                        &FuncRef::of_decl(declaration.clone()),
                        &f.params,
                        &symbol.ty(),
                        &symbol.variables(),
                        false,
                    );
                } else {
                    let ctor = constructor_signature(&symbol.ty());
                    self.c.check_native_defaults(
                        &FuncRef::of_decl(declaration.clone()),
                        declaration.record_fields(),
                        &ctor,
                        &symbol.variables(),
                        false,
                    );
                    let operations: Vec<Operation> = symbol
                        .ty()
                        .def
                        .as_ref()
                        .expect("def")
                        .operations
                        .borrow()
                        .clone();
                    for operation in operations {
                        let Some(method) =
                            standard_method_declaration(&symbol.ty(), operation.name)
                        else {
                            continue;
                        };
                        let mut variables = symbol.variables();
                        variables.extend(operation_variables(&format!(
                            "{}/{}",
                            symbol.id, operation.name
                        )));
                        let params = method.func().map(|f| f.params.as_slice()).unwrap_or(&[]);
                        self.c.check_native_defaults(
                            &method,
                            params,
                            &operation.ty,
                            &variables,
                            symbol.ty().kind == Kind::Contract,
                        );
                    }
                }
            }
        }
        let native = self.native_sources();
        crate::passes::finish_modules(&native);
        if !self.c.p.diagnostics.is_empty() {
            let text: Vec<String> = self.c.p.diagnostics.iter().map(|d| d.to_string()).collect();
            return Err(format!("invalid standard defaults: {}", text.join("; ")));
        }
        Ok(())
    }
}

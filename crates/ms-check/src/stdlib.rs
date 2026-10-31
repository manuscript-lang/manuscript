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
pub const PRIMITIVE_NAMES: [&str; 16] = [
    "Bool", "Int", "Float", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32",
    "UInt64", "Float32", "Float64", "String", "Unit", "Never",
];

/// The result of checking one bundled source module.
pub struct StdResult {
    /// Module-level symbols visible in the module.
    pub symbols: Names,
    /// Symbols the module declares.
    pub exports: HashMap<Name, SymRef>,
    /// Methods the module implements.
    pub methods: Vec<MethodRef>,
}

#[derive(Default)]
struct World {
    state: u8, // 0 unloaded, 1 loading, 2 loaded
    symbols: HashMap<Name, SymRef>,
    /// Exported records and alternatives of source modules, declared when the module is registered so
    /// native modules can name them before the source module is checked.
    source_types: HashMap<(Name, Name), SymRef>,
    /// Source modules whose types native modules named while loading; they are checked right after.
    stub_modules: Vec<Name>,
    modules: HashMap<Name, HashMap<Name, SymRef>>,
    module_order: Vec<Name>,
    sources: Vec<ModRef>,
    source_modules: HashMap<Name, ModRef>,
    intrinsic: HashMap<Name, Ty>,
    implementations: Vec<MethodRef>,
    operation_variables: HashMap<String, Vec<Ty>>,
    receiver_bindings: HashMap<String, Name>,
    runtime_symbols: HashMap<String, String>,
    kept_callbacks: HashSet<String>,
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
    runtime_symbols: HashMap<String, String>,
    kept_callbacks: HashMap<String, String>,
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
    Ok(Bindings {
        native_types: strings("native_types"),
        function_overrides: strings("function_overrides"),
        intrinsic_receivers: strings("intrinsic_receivers"),
        contract_methods: strings("contract_methods"),
        runtime_symbols: strings("runtime_symbols"),
        kept_callbacks: strings("kept_callbacks"),
    })
}

// -------------------------------------------------------------------- queries

/// The bundled source modules that extend native standard types (List operations, Bytes codecs, scalar ordering); their
/// methods apply to every program.
const EXTENSION_MODULES: [&str; 3] = [
    "@std/collections.ms+source",
    "@std/bytes.ms+source",
    "@std/ordering.ms",
];

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
    // Types that native modules took from a source module are filled in by checking that module.
    let stubs = world(|w| std::mem::take(&mut w.stub_modules));
    for path in stubs {
        if let Some(module) = standard_source_module(path) {
            ensure_source(&module);
        }
    }
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

/// The native function (`module/name`) that bindings.json binds to a runtime symbol, when exactly one is.
pub fn native_for_symbol(symbol: &str) -> Option<String> {
    ensure_standard();
    world(|w| {
        let mut bound = w
            .runtime_symbols
            .iter()
            .filter(|(_, s)| s.as_str() == symbol)
            .map(|(k, _)| k.clone());
        let first = bound.next()?;
        bound.next().is_none().then_some(first)
    })
}

/// Whether a native function (`module/name`, or `extern:name`) keeps the function values it is given instead of
/// running them before it returns, as bindings.json declares under `kept_callbacks`.
pub fn keeps_callbacks(native: &str) -> bool {
    ensure_standard();
    world(|w| w.kept_callbacks.contains(native))
}

/// The runtime symbol that implements a native function (`module/name`), as bindings.json names it.
pub fn runtime_symbol(native: &str) -> Option<String> {
    ensure_standard();
    world(|w| w.runtime_symbols.get(native).cloned())
}

/// Records the type variables an operation declares for itself (`Receiver id/name`).
pub(crate) fn set_operation_variables(key: String, variables: Vec<Ty>) {
    world(|w| {
        w.operation_variables.insert(key, variables);
    });
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

/// The symbol of a record or alternative declared in a bundled source module, as registered at load.
pub fn source_type(module: Name, name: Name) -> Option<SymRef> {
    ensure_standard();
    world(|w| w.source_types.get(&(module, name)).cloned())
}

/// Declares the symbol of a record or alternative of a bundled source module. The checker of the
/// module reuses it, so native modules and the source module agree on one type.
pub(crate) fn source_type_symbol(module: &ModRef, d: &DeclRef) -> SymRef {
    let name = d.name();
    let kind = match d.decl().kind {
        DeclKind::Alternative(_) => Kind::Alternative,
        DeclKind::Interface(_) => Kind::Contract,
        _ => Kind::Record,
    };
    let stem = module
        .file
        .as_str()
        .trim_start_matches("@std/")
        .trim_end_matches(".ms");
    let s = Rc::new(Sym {
        name,
        id: n(&format!("standard_{stem}_symbol_{name}")),
        kind: SymKind::Type,
        module: module.file,
        native: n(""),
        export: d.decl().export,
        ty: RefCell::new(None),
        variables: RefCell::new(Vec::new()),
        decl: Some(d.clone()),
    });
    let def = Definition::new(&s, kind);
    let mut t = Type::new(
        name,
        n(&format!(
            "module/{}#{}",
            crate::checker::hex(module.file.as_str()),
            name
        )),
        kind,
    );
    t.def = Some(def);
    *s.ty.borrow_mut() = Some(Rc::new(t));
    s
}

/// A native module's declaration by name.
pub fn standard_module_symbol(path: Name, name: Name) -> Option<SymRef> {
    ensure_standard();
    world(|w| {
        w.modules
            .get(&path)
            .and_then(|m| m.get(&name).cloned())
            .or_else(|| {
                let stub = w.source_types.get(&(path, name)).cloned()?;
                if w.state == 1 && !w.stub_modules.contains(&path) {
                    w.stub_modules.push(path);
                }
                Some(stub)
            })
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

fn source_reach(module: &ModRef) -> Vec<ModRef> {
    let mut seen: Vec<ModRef> = Vec::new();
    let mut stack: Vec<ModRef> = vec![module.clone()];
    while let Some(m) = stack.pop() {
        for item in &m.imports {
            if let Some(dep) = standard_source_module(n(&item.path))
                && !seen.iter().any(|s| s.file == dep.file)
            {
                seen.push(dep.clone());
                stack.push(dep);
            }
        }
    }
    seen
}

/// The bundled source modules that import `module`, directly or not, and are imported back by it.
fn source_group(module: &ModRef) -> Vec<ModRef> {
    let mut group = vec![module.clone()];
    for m in source_reach(module) {
        if m.file != module.file && source_reach(&m).iter().any(|r| r.file == module.file) {
            group.push(m);
        }
    }
    group
}

/// Whether `module` is an extension module or one an extension module imports.
fn extension_reach(module: &ModRef) -> bool {
    EXTENSION_MODULES.iter().any(|path| {
        module.file.as_str() == *path
            || standard_source_module(n(path))
                .is_some_and(|ext| source_reach(&ext).iter().any(|m| m.file == module.file))
    })
}

/// Checks a bundled source module and the bundled modules it imports, once.
/// Modules that import each other are checked together.
pub fn ensure_source(module: &ModRef) -> Rc<StdResult> {
    ensure_standard();
    if let Some(r) = done(module.file) {
        return r;
    }
    let group = source_group(module);
    let cycle = world(|w| group.iter().any(|g| !w.checking.insert(g.file)));
    if cycle {
        panic!(
            "cyclic standard source dependency at {} while checking {:?}",
            module.file,
            world(|w| w.checking.clone())
        );
    }
    for g in &group {
        for item in &g.imports {
            if let Some(dep) = standard_source_module(n(&item.path))
                && !group.iter().any(|m| m.file == dep.file)
            {
                ensure_source(&dep);
            }
        }
    }
    // An extension module and what it imports cannot depend on the extensions, so they are not loaded for them.
    let extending = extension_reach(module);
    for path in EXTENSION_MODULES.iter().filter(|_| !extending) {
        if let Some(extension) = standard_source_module(n(path))
            && !group.iter().any(|m| m.file == extension.file)
        {
            ensure_source(&extension);
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
    if group.len() > 1 {
        checker.group = group.clone();
    }
    let program = checker.check_modules(vec![module.clone()], Some(module.file));
    if !program.diagnostics.is_empty() {
        let text: Vec<String> = program.diagnostics.iter().map(|d| d.to_string()).collect();
        panic!(
            "invalid standard implementation {}: {}",
            module.file,
            text.join("; ")
        );
    }
    for g in &group {
        let symbols = program
            .symbols
            .get(&g.file)
            .cloned()
            .expect("module symbols");
        let exports: HashMap<Name, SymRef> = symbols
            .borrow()
            .iter()
            .filter(|(_, s)| s.module == g.file)
            .map(|(k, v)| (*k, v.clone()))
            .collect();
        let methods: Vec<MethodRef> = program
            .methods
            .iter()
            .filter(|m| m.module == g.file)
            .cloned()
            .collect();
        let result = Rc::new(StdResult {
            symbols,
            exports,
            methods,
        });
        world(|w| {
            w.done.insert(g.file, result.clone());
            w.checking.remove(&g.file);
        });
    }
    done(module.file).expect("checked")
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
            Some(1) if is_source_module(module) => return,
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
    // The operations written in Manuscript on native types apply to every program.
    // An extension module and what it imports do not depend on the extensions.
    let extending = modules.iter().any(extension_reach);
    for path in EXTENSION_MODULES.iter().filter(|_| !extending) {
        if let Some(extension) = standard_source_module(n(path)) {
            visit(&extension, &mut state, &mut ordered, &mut diagnostics);
        }
    }
    // A `bench` block runs under the driver in `@std/bench.ms`, which its module need not import.
    let benching = modules.iter().any(|m| {
        m.decls
            .iter()
            .any(|d| matches!(&d.decl().kind, DeclKind::Test(t) if t.bench))
    });
    if benching && let Some(driver) = standard_source_module(n("@std/bench.ms")) {
        visit(&driver, &mut state, &mut ordered, &mut diagnostics);
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
        DeclKind::Fn(f) => !f.body.is_empty() || f.external,
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

/// Whether a top-level declaration carries an implementation body.
fn decl_has_body(d: &Decl) -> bool {
    match &d.kind {
        DeclKind::Fn(f) => !f.body.is_empty() || f.external,
        DeclKind::Const(_) => true,
        DeclKind::Test(t) => !t.body.is_empty(),
        DeclKind::Impl(i) => i.methods.iter().any(|m| !m.func.body.is_empty()),
        DeclKind::Record(_) | DeclKind::Alternative(_) | DeclKind::Interface(_) => false,
    }
}

fn fresh(ids: &mut u32) -> NodeId {
    *ids += 1;
    NodeId(*ids - 1)
}

fn renumber_type(t: &TypeRef, ids: &mut u32) -> Result<TypeRef, String> {
    let kind = match &t.kind {
        TypeKind::Named { name, args } => TypeKind::Named {
            name: *name,
            args: args
                .iter()
                .map(|a| renumber_type(a, ids))
                .collect::<Result<_, _>>()?,
        },
        TypeKind::Fn { params, result } => TypeKind::Fn {
            params: params
                .iter()
                .map(|p| renumber_param(p, ids))
                .collect::<Result<_, _>>()?,
            result: Box::new(renumber_type(result, ids)?),
        },
    };
    Ok(TypeRef {
        id: fresh(ids),
        pos: t.pos,
        kind,
    })
}

fn renumber_param(
    p: &ms_syntax::ast::Param,
    ids: &mut u32,
) -> Result<ms_syntax::ast::Param, String> {
    if p.default.is_some() {
        return Err(format!(
            "a source method on a native type cannot have a default argument; declare it through an interface: {}",
            position_text(n(""), p.pos)
        ));
    }
    let ty = match &p.ty {
        Some(t) => Some(renumber_type(t, ids)?),
        None => None,
    };
    Ok(ms_syntax::ast::Param {
        id: fresh(ids),
        pos: p.pos,
        name: p.name,
        ty,
        default: None,
        mutable: p.mutable,
        by_ref: p.by_ref,
    })
}

/// The interface and contract `impl` a bodied inherent `impl Receiver[T]:` becomes in the source
/// half: `impl Receiver[T]:` cannot declare operations on a type the half does not own, so its
/// methods are declared by a generated unexported interface that the receiver implements.
fn interface_for_inherent(
    parsed: &Module,
    d: &Decl,
    i: &ImplDecl,
    ids: &mut u32,
    used: &mut Vec<String>,
) -> Result<(Decl, Decl), String> {
    let at = || position_text(n(&parsed.file), d.pos);
    let TypeKind::Named { name, args } = &i.receiver.kind else {
        return Err(format!("an inherent impl must name a type: {}", at()));
    };
    let mut params = Vec::new();
    for a in args {
        let TypeKind::Named { name, args } = &a.kind else {
            return Err(format!(
                "inherent impl must repeat the type parameters: {}",
                at()
            ));
        };
        if !args.is_empty() {
            return Err(format!(
                "inherent impl must repeat the type parameters: {}",
                at()
            ));
        }
        params.push(TypeParam {
            id: fresh(ids),
            pos: a.pos,
            name: *name,
            bounds: Vec::new(),
            default: None,
        });
    }
    let base = format!("{}SourceMethods", name.as_str().replace('.', "_"));
    let mut interface_name = base.clone();
    while used.contains(&interface_name) {
        interface_name = format!("{base}{}", used.len());
    }
    used.push(interface_name.clone());
    let interface_name = ms_syntax::Symbol::intern(&interface_name);
    let mut methods = Vec::new();
    for m in &i.methods {
        let mut type_params = Vec::new();
        for t in &m.func.type_params {
            type_params.push(TypeParam {
                id: fresh(ids),
                pos: t.pos,
                name: t.name,
                bounds: t
                    .bounds
                    .iter()
                    .map(|b| renumber_type(b, ids))
                    .collect::<Result<_, _>>()?,
                default: match &t.default {
                    Some(t) => Some(renumber_type(t, ids)?),
                    None => None,
                },
            });
        }
        let func = Func {
            name: m.func.name,
            type_params,
            params: m
                .func
                .params
                .iter()
                .map(|p| renumber_param(p, ids))
                .collect::<Result<_, _>>()?,
            result: renumber_type(&m.func.result, ids)?,
            result_ref: m.func.result_ref,
            body: Vec::new(),
            external: false,
        };
        methods.push(Method {
            id: fresh(ids),
            pos: m.pos,
            func,
            mutating: m.mutating,
        });
    }
    let contract = TypeRef {
        id: fresh(ids),
        pos: i.receiver.pos,
        kind: TypeKind::Named {
            name: interface_name,
            args: args
                .iter()
                .map(|a| renumber_type(a, ids))
                .collect::<Result<_, _>>()?,
        },
    };
    let interface = Decl {
        id: fresh(ids),
        pos: d.pos,
        export: false,
        synthetic: false,
        kind: DeclKind::Interface(InterfaceDecl {
            name: interface_name,
            type_params: params,
            methods,
        }),
    };
    let implementation = Decl {
        id: fresh(ids),
        pos: d.pos,
        export: false,
        synthetic: false,
        kind: DeclKind::Impl(ImplDecl {
            contract: Some(contract),
            receiver: i.receiver.clone(),
            methods: i.methods.clone(),
        }),
    };
    Ok((interface, implementation))
}

/// Splits a file that has both native operations (an inherent `impl` with bodyless methods) and
/// bodies into a native module and a source module named `<file>+source`. The source half takes
/// the bodied declarations and the interfaces only they implement; the rest stays native. Source
/// methods on a native type are written through an interface, so a bodied inherent method is an
/// error. Returns `None` for any other file.
fn split_mixed(parsed: &Module) -> Result<Option<(Module, Module)>, String> {
    let bodyless_inherent = |d: &Decl| {
        matches!(&d.kind, DeclKind::Impl(i) if i.contract.is_none()
            && i.methods.iter().any(|m| m.func.body.is_empty()))
    };
    if !parsed.decls.iter().any(bodyless_inherent) || !parsed.decls.iter().any(decl_has_body) {
        return Ok(None);
    }
    let implements = |d: &Decl, name: Name| matches!(&d.kind, DeclKind::Impl(i) if i.contract.as_ref().is_some_and(|c| n(c.name()) == name));
    let mut native = Vec::new();
    let mut source = Vec::new();
    let mut ids = parsed.node_count;
    let mut used: Vec<String> = Vec::new();
    for d in &parsed.decls {
        let to_source = match &d.kind {
            DeclKind::Impl(i) if i.contract.is_none() && decl_has_body(d) => {
                let (interface, implementation) =
                    interface_for_inherent(parsed, d, i, &mut ids, &mut used)?;
                source.push(interface);
                source.push(implementation);
                continue;
            }
            DeclKind::Interface(i) => {
                let name = i.name;
                parsed.decls.iter().any(|x| implements(x, name))
                    && parsed
                        .decls
                        .iter()
                        .filter(|x| implements(x, name))
                        .all(decl_has_body)
            }
            _ => decl_has_body(d),
        };
        if to_source {
            source.push(d.clone());
        } else {
            native.push(d.clone());
        }
    }
    // The source half sees the native half's exports as if it imported its own file; the file
    // does not spell that import out.
    let mut own_imports: Vec<Import> = Vec::new();
    for d in native.iter().filter(|d| d.export) {
        let name = match &d.kind {
            DeclKind::Fn(f) => f.name,
            DeclKind::Const(c) => c.name,
            DeclKind::Record(r) => r.name,
            DeclKind::Alternative(a) => a.name,
            DeclKind::Interface(i) => i.name,
            DeclKind::Impl(_) | DeclKind::Test(_) => continue,
        };
        if STANDARD_PRELUDE_NAMES.contains(&name.as_str()) {
            continue;
        }
        ids += 1;
        own_imports.push(Import {
            id: NodeId(ids - 1),
            pos: d.pos,
            name_pos: d.pos,
            name,
            path: parsed.file.as_ref().into(),
        });
    }
    let half = |file: Arc<str>, decls: Vec<Decl>, own: bool| Module {
        imports: parsed
            .imports
            .iter()
            .cloned()
            .chain(own.then(|| own_imports.clone()).into_iter().flatten())
            .collect(),
        file,
        source: parsed.source.clone(),
        decls,
        omitted: parsed.omitted.clone(),
        recovered: parsed.recovered.clone(),
        node_count: parsed.node_count,
    };
    let mut source_half = half(
        Arc::from(format!("{}+source", parsed.file).as_str()),
        source,
        true,
    );
    source_half.node_count = ids;
    Ok(Some((
        half(parsed.file.clone(), native, false),
        source_half,
    )))
}

fn load() -> Result<(), String> {
    let bindings = read_bindings()?;
    world(|w| {
        w.runtime_symbols = bindings.runtime_symbols.clone();
        w.kept_callbacks = bindings.kept_callbacks.keys().cloned().collect();
    });
    let mut modules: Vec<ModRef> = Vec::new();
    for (name, source) in SOURCES {
        let file: Arc<str> = Arc::from(format!("@std/{name}").as_str());
        let parsed =
            ms_syntax::parser::parse(&file, source).map_err(|d| format!("parse {file}: {d}"))?;
        // A file that declares native operations and also has bodies keeps the native declarations
        // under its own name and checks the bodies as a source module named `<file>+source`.
        if let Some((native, source)) = split_mixed(&parsed)? {
            let decls = fold_inherent_impls(&native)?;
            modules.push(Rc::new(ModuleData::new(&native, decls, native.node_count)));
            modules.push(crate::load_module(&source));
            continue;
        }
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
                match &d.decl().kind {
                    DeclKind::Record(r) if r.external => self.register_extern_type(module, d)?,
                    DeclKind::Record(_) | DeclKind::Alternative(_) | DeclKind::Interface(_)
                        if d.decl().export =>
                    {
                        let stub = source_type_symbol(module, d);
                        world(|w| w.source_types.insert((module.file, d.name()), stub));
                    }
                    _ => {}
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
                id: n(primitive_id(name)),
                kind: SymKind::Type,
                module: n(""),
                native: n(""),
                export: true,
                ty: RefCell::new(Some(primitive(primitive_id(name)))),
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
                    self.c.declare_self(&s.ty());
                    self.c.operation_variables(s.id, method);
                    let ty = self
                        .c
                        .signature(&method.func.params, Some(&method.func.result));
                    self.c.check_self_use(&ty, method.pos);
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
                    // A property without operations has no method to bind.
                    let Some(name) = method.name() else {
                        continue;
                    };
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

#[cfg(test)]
mod tests {
    use super::*;

    fn halves(text: &str) -> Result<Option<(Module, Module)>, String> {
        let file: Arc<str> = Arc::from("@std/t.ms");
        split_mixed(&ms_syntax::parser::parse(&file, text).expect("parses"))
    }

    #[test]
    fn a_bodied_inherent_impl_becomes_an_interface_and_a_contract_impl() {
        let text = "export type Box[T]: ...\n\nimpl Box[T]:\n    fn native() Int: ...\n\nimpl Box[T]:\n    fn size() Int:\n        return 1\n";
        let (native, source) = halves(text).unwrap().expect("mixed");
        assert_eq!(native.file.as_ref(), "@std/t.ms");
        assert_eq!(source.file.as_ref(), "@std/t.ms+source");
        assert_eq!(native.decls.len(), 2);
        let kinds: Vec<&str> = source
            .decls
            .iter()
            .map(|d| match &d.kind {
                DeclKind::Interface(_) => "interface",
                DeclKind::Impl(i) if i.contract.is_some() => "contract impl",
                _ => "other",
            })
            .collect();
        assert_eq!(kinds, ["interface", "contract impl"]);
    }

    #[test]
    fn a_default_argument_on_a_source_method_is_rejected() {
        let text = "export type Box: ...\n\nimpl Box:\n    fn native() Int: ...\n\nimpl Box:\n    fn size(n: Int = 1) Int:\n        return n\n";
        let error = halves(text).unwrap_err();
        assert!(error.contains("default argument"), "{error}");
    }

    #[test]
    fn a_file_without_bodies_is_not_split() {
        let text = "export type Box: ...\n\nimpl Box:\n    fn native() Int: ...\n";
        assert!(halves(text).unwrap().is_none());
    }
}

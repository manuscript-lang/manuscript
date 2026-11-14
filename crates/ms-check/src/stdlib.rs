//! The bundled standard declarations.
//!
//! `stdlib/*.ms` is embedded unchanged. Native
//! modules (declarations without bodies) are declared once per thread; source
//! modules (declarations with bodies) are checked lazily with the ordinary
//! checker and shared by every program.

pub use crate::bundled::EXTENSION_MODULES;
use crate::bundled::{decl_has_body, is_mixed, is_pure_source};
use crate::checker::{CheckOptions, Checker, Names};
use crate::fxmap::{HashMap, HashSet};
use crate::syntax::*;
use crate::types::Case;
use crate::types::*;
use ms_syntax::ast::Method;
use ms_syntax::ast::*;
use ms_syntax::{Diagnostic, Phase};
use std::cell::RefCell;
use std::collections::BTreeSet;
use std::rc::Rc;
use std::sync::Arc;

include!(concat!(env!("OUT_DIR"), "/std_sources.rs"));

/// Source-backed prelude types retain their standard declaration identities.
pub const STANDARD_PRELUDE_NAMES: [&str; 12] = [
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
    "ListEntry",
    "MapEntry",
];

/// Source-backed prelude functions as (module path, name); every module of user code sees them without an import.
pub const STANDARD_PRELUDE_FUNCTIONS: [(&str, &str); 1] = [("@std/core.ms", "print")];

/// The implicit import that gives user code a prelude function.
pub fn prelude_function_import(path: &str, name: &str) -> Import {
    Import {
        id: ms_syntax::NodeId(0),
        pos: ms_syntax::Pos::default(),
        clause: ms_syntax::Pos::default(),
        name_pos: ms_syntax::Pos::default(),
        name: n(name),
        path: path.into(),
    }
}

/// The built-in types every module sees without an import.
pub const PRIMITIVE_NAMES: [&str; 16] = [
    "Bool", "Int", "Float", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32",
    "UInt64", "Float32", "Float64", "String", "Unit", "Never",
];

/// Generic interfaces in `intrinsics.ms` that primitives share, with the primitives that have them.
/// `T` is the receiver, so a family states each of its operations once.
const SHARED_OPERATIONS: [(&str, &[&str]); 2] = [
    (
        "IntegerOperations",
        &[
            "Int", "Int8", "Int16", "Int32", "UInt8", "UInt16", "UInt32", "UInt64",
        ],
    ),
    (
        "SignedIntegerOperations",
        &["Int", "Int8", "Int16", "Int32"],
    ),
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
pub(crate) struct World {
    state: u8, // 0 unloaded, 1 loading, 2 loaded
    symbols: HashMap<Name, SymRef>,
    /// Exported types and alternatives of source modules, declared when the module is registered so
    /// native modules can name them before the source module is checked.
    source_types: HashMap<(Name, Name), SymRef>,
    /// Source modules whose types native modules named while loading; they are checked right after.
    stub_modules: Vec<Name>,
    modules: HashMap<Name, HashMap<Name, SymRef>>,
    module_order: Vec<Name>,
    sources: Vec<ModRef>,
    source_modules: HashMap<Name, ModRef>,
    /// Pure source modules not yet parsed; each loads when first looked up.
    deferred: HashMap<Name, &'static str>,
    intrinsic: HashMap<Name, Vec<Ty>>,
    implementations: Vec<MethodRef>,
    operation_variables: HashMap<String, Vec<Ty>>,
    receiver_natives: HashSet<String>,
    done: HashMap<Name, Rc<StdResult>>,
    checking: HashSet<Name>,
    /// The bundled module of each declared function or method, by the address of its syntax;
    /// built on first use once the library is loaded.
    func_modules: Option<HashMap<usize, ModRef>>,
}

/// The compiler session: the standard-library world and the binding counter. A checker, the
/// standard-module checkers it starts, and the `Program` it returns share one session. It holds
/// `Rc` types whose primitives are thread-local (`types.rs`), so a session stays on one thread.
#[derive(Default)]
pub struct Session {
    syms: ms_syntax::Names,
    world: RefCell<World>,
    /// Source of `Binding::uid`, shared by the program and the standard modules it checks.
    bindings: std::cell::Cell<usize>,
}

impl Session {
    /// A new session with an unloaded standard library.
    pub fn new() -> Rc<Session> {
        Rc::new(Session::default())
    }

    /// The next binding identity.
    pub(crate) fn next_binding(&self) -> usize {
        let next = self.bindings.get() + 1;
        self.bindings.set(next);
        next
    }

    pub(crate) fn world<R>(&self, f: impl FnOnce(&mut World) -> R) -> R {
        f(&mut self.world.borrow_mut())
    }
}

/// Whether the runtime function `symbol` takes ownership of its argument `param` (it moves into
/// the runtime), as its `// ms: takes:<param>` declares.
pub fn takes_argument(symbol: &str, param: &str) -> bool {
    RUNTIME_TAKES.contains(&(symbol, param))
}

/// Whether the runtime function `symbol` keeps the function values it is given instead of running
/// them before it returns, as its `// ms: keeps:<param>` declares.
pub fn keeps_callbacks(symbol: &str) -> bool {
    RUNTIME_KEEPS.contains(&symbol)
}

/// Native types that declare fields, so they cannot be written `extern type`. A type in a native
/// module is otherwise an ordinary type (`Error`), so the runtime's own `List` is named here.
const NATIVE_WITH_FIELDS: &[&str] = &["List"];

// -------------------------------------------------------------------- queries

/// The directories that group bundled modules into packages; a module's native identifiers use its file stem without them.
const PACKAGES: [&str; 7] = [
    "collections",
    "concurrency",
    "data",
    "io",
    "math",
    "net",
    "os",
];

/// A bundled module's path without `@std/`, its package directory, and `.ms`: `@std/net/http.ms` is `http`.
pub fn module_stem(file: &str) -> &str {
    let path = file.trim_start_matches("@std/").trim_end_matches(".ms");
    match path {
        "test/test" => return "test",
        "test/bench" => return "bench",
        _ => {}
    }
    match path.split_once('/') {
        Some((package, rest)) if PACKAGES.contains(&package) => rest,
        _ => path,
    }
}

/// Declares the symbol of a type or alternative of a bundled source module. The checker of the
/// module reuses it, so native modules and the source module agree on one type.
pub(crate) fn source_type_symbol(syms: ms_syntax::Names, module: &ModRef, d: &DeclRef) -> SymRef {
    let name = d.name();
    let kind = match d.decl().kind {
        DeclKind::Alternative(_) => Kind::Alternative,
        DeclKind::Interface(_) => Kind::Contract,
        _ => Kind::Type,
    };
    let stem = module_stem(syms.str(module.file));
    let s = Rc::new(Sym {
        name,
        id: n(&format!(
            "standard_{stem}_symbol_{name_t}",
            name_t = syms.str(name)
        )),
        kind: SymKind::Type,
        module: module.file,
        native: Native::Source,
        export: d.decl().export,
        ty: RefCell::new(None),
        variables: RefCell::new(Vec::new()),
        decl: Some(d.clone()),
    });
    let def = Definition::new(&s, kind);
    let mut t = Type::new(
        syms,
        name,
        n(&format!(
            "module/{}#{}",
            crate::checker::hex(syms.str(module.file)),
            syms.str(name)
        )),
        kind,
    );
    t.builtin = Builtin::source(syms.str(module.file), syms.str(name));
    t.def = Some(def);
    *s.ty.borrow_mut() = Some(Rc::new(t));
    s
}

/// Whether a module file is standard-library source: a bundled `@std/` module, or a checkout's
/// `stdlib/` file opened from disk (an editor on the repository).
pub fn is_bundled_source(file: &str) -> bool {
    file.starts_with("@std/")
        || std::path::Path::new(file).ancestors().any(|dir| {
            dir.file_name().is_some_and(|n| n == "stdlib")
                && dir.join("internal/promises.ms").is_file()
        })
}

/// Whether a bundled module is internal: it holds the native declarations of the public modules and is not importable by programs.
pub fn is_internal(path: &str) -> bool {
    path.starts_with("@std/internal/")
}

/// The declaration of a standard type's operation.
pub fn standard_method_declaration(t: &Ty, name: Name) -> Option<FuncRef> {
    let sym = t.def.as_ref()?.symbol()?;
    let decl = sym.decl.clone()?;
    decl.method_named(name)
}

// --------------------------------------------------------------------- loading

fn decl_name(d: &Decl) -> Name {
    match &d.kind {
        DeclKind::Fn(f) => f.name,
        DeclKind::Const(c) => c.name,
        DeclKind::Type(r) => r.name,
        DeclKind::Alternative(a) => a.name,
        DeclKind::Alias(a) => a.name,
        DeclKind::Interface(i) => i.name,
        DeclKind::Impl(_) | DeclKind::Test(_) => n(""),
    }
}

fn decl_type_params(d: &Decl) -> &[TypeParam] {
    match &d.kind {
        DeclKind::Fn(f) => &f.type_params,
        DeclKind::Type(r) => &r.type_params,
        DeclKind::Alternative(a) => &a.type_params,
        DeclKind::Alias(a) => &a.type_params,
        DeclKind::Interface(i) => &i.type_params,
        _ => &[],
    }
}

fn fold_inherent_impls(
    syms: ms_syntax::Names,
    module: &Module,
) -> Result<(Vec<DeclRef>, u32), String> {
    let mut kept: Vec<(Decl, Vec<Method>)> = Vec::new();
    let mut next_id = module.node_count;
    let mut types: HashMap<Name, usize> = HashMap::default();
    let mut specials: Vec<Decl> = Vec::new();
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
        for marker in crate::passes::marker_decls(module, d, &mut next_id) {
            kept.push((marker, Vec::new()));
        }
    }
    for d in &module.decls {
        let DeclKind::Impl(i) = &d.kind else {
            continue;
        };
        if i.contract.is_some() {
            continue;
        }
        let at = || position_text(syms, n(&module.file), d.pos);
        let idx = match types.get(&n(i.receiver.name(syms))) {
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
        if !repeats || !i.bounds.is_empty() {
            // A bounded or specialized receiver keeps its requirements in a generated interface.
            specials.push(d.clone());
            continue;
        }
        let methods = i.methods.clone();
        kept[idx].1.extend(methods);
    }
    if !specials.is_empty() {
        let sub = Module {
            file: module.file.clone(),
            source: module.source.clone(),
            imports: module.imports.clone(),
            decls: module
                .decls
                .iter()
                .filter(|d| {
                    !matches!(
                        d.kind,
                        DeclKind::Impl(_)
                            | DeclKind::Fn(_)
                            | DeclKind::Const(_)
                            | DeclKind::Test(_)
                    )
                })
                .cloned()
                .chain(specials)
                .collect(),
            omitted: Vec::new(),
            recovered: Vec::new(),
            node_count: next_id,
        };
        let (made, errors, count) = crate::passes::desugar_inherent_impls(syms, &sub, &[]);
        if let Some(e) = errors.first() {
            return Err(e.message.clone());
        }
        next_id = count;
        for d in made {
            let generated = match &d.kind {
                DeclKind::Interface(i) => {
                    syms.str(i.name).ends_with(crate::passes::INHERENT_SUFFIX)
                }
                DeclKind::Impl(i) => i
                    .contract
                    .as_ref()
                    .is_some_and(|c| c.name(syms).ends_with(crate::passes::INHERENT_SUFFIX)),
                _ => false,
            };
            if generated {
                kept.push((d, Vec::new()));
            }
        }
    }
    let decls = kept
        .into_iter()
        .map(|(decl, folded)| DeclRef(Rc::new(DeclNode { decl, folded })))
        .collect();
    Ok((decls, next_id))
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

/// Splits a file that has both native operations (an inherent `impl` with bodyless methods) and
/// bodies into a native module and a source module named `<file>+source`. The source half takes
/// the bodied declarations and the interfaces only they implement; the rest stays native. Source
/// methods on a native type are written through an interface, so a bodied inherent method is an
/// error. Returns `None` for any other file.
/// The native half, the `+source` half, and the type declarations the source half's receiver methods name.
type Halves = (Module, Module, Vec<Decl>);

fn split_mixed(syms: ms_syntax::Names, parsed: &Module) -> Result<Option<Halves>, String> {
    if !is_mixed(parsed) {
        return Ok(None);
    }
    let implements = |d: &Decl, name: Name| matches!(&d.kind, DeclKind::Impl(i) if i.contract.as_ref().is_some_and(|c| n(c.name(syms)) == name));
    let mut native = Vec::new();
    let mut source = Vec::new();
    let mut ids = parsed.node_count;
    for d in &parsed.decls {
        let to_source = match &d.kind {
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
            DeclKind::Type(r) => r.name,
            DeclKind::Alternative(a) => a.name,
            DeclKind::Alias(a) => a.name,
            DeclKind::Interface(i) => i.name,
            DeclKind::Impl(_) | DeclKind::Test(_) => continue,
        };
        if STANDARD_PRELUDE_NAMES.contains(&syms.str(name)) {
            continue;
        }
        ids += 1;
        own_imports.push(Import {
            id: NodeId(ids - 1),
            pos: d.pos,
            clause: d.pos,
            name_pos: d.pos,
            name,
            path: parsed.file.as_ref().into(),
        });
    }
    let half = |file: Arc<str>, decls: Vec<Decl>, own: bool| Module {
        imports: parsed
            .imports
            .iter()
            // The native half has no bodies, so it needs none of the internal externs the bodies call.
            .filter(|i| own || !is_internal(&i.path))
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
    let foreign: Vec<Decl> = parsed
        .decls
        .iter()
        .filter(|d| matches!(d.kind, DeclKind::Type(_) | DeclKind::Alternative(_)))
        .cloned()
        .collect();
    Ok(Some((
        half(parsed.file.clone(), native, false),
        source_half,
        foreign,
    )))
}

fn parse_bundled(file: &str, source: &str) -> Result<Module, String> {
    let file: Arc<str> = Arc::from(file);
    ms_syntax::parser::parse(&file, source).map_err(|d| format!("parse {file}: {d}"))
}

/// Splits a parsed bundled file into its modules: one, or a native half and a `+source` half.
fn bundled_modules(syms: ms_syntax::Names, parsed: &Module) -> Result<Vec<ModRef>, String> {
    // A file that declares native operations and also has bodies keeps the native declarations
    // under its own name and checks the bodies as a source module named `<file>+source`.
    if let Some((native, source, foreign)) = split_mixed(syms, parsed)? {
        let (decls, node_count) = fold_inherent_impls(syms, &native)?;
        return Ok(vec![
            Rc::new(ModuleData::new(&native, decls, node_count)),
            crate::load_module_with(syms, &source, &foreign),
        ]);
    }
    // A module with implementation bodies is checked like user source, so its inherent
    // methods take the same desugaring and become ordinary methods wherever the type is used.
    if has_inherent_body(parsed) {
        return Ok(vec![crate::load_module(syms, parsed)]);
    }
    let (decls, node_count) = fold_inherent_impls(syms, parsed)?;
    Ok(vec![Rc::new(ModuleData::new(parsed, decls, node_count))])
}

struct Loader<'a> {
    c: &'a mut Checker,
}

fn position_text(syms: ms_syntax::Names, file: Name, pos: ms_syntax::Pos) -> String {
    format!("{}:{}:{}", syms.str(file), pos.line, pos.column)
}

impl Loader<'_> {
    /// The canonical symbol of an `extern type` declared in a bundled source module.
    fn register_extern_type(
        &mut self,
        syms: ms_syntax::Names,
        module: &ModRef,
        d: &DeclRef,
    ) -> Result<(), String> {
        let name = d.name();
        if !d.type_params().is_empty() {
            return Err(format!(
                "extern types cannot be generic yet: {}",
                position_text(syms, module.file, d.pos())
            ));
        }
        let id = n(&format!("@std/{name_t}", name_t = syms.str(name)));
        let s = Rc::new(Sym {
            name,
            id,
            kind: SymKind::Type,
            module: module.file,
            native: Native::Builtin(name),
            export: d.decl().export,
            ty: RefCell::new(None),
            variables: RefCell::new(Vec::new()),
            decl: Some(d.clone()),
        });
        let def = Definition::new(&s, Kind::Native);
        let mut t = Type::new(syms, name, id, Kind::Native);
        t.def = Some(def);
        *s.ty.borrow_mut() = Some(Rc::new(t));
        if self.c.session.world(|w| w.symbols.contains_key(&name)) {
            return Err(format!(
                "duplicate standard type {name_t}",
                name_t = syms.str(name)
            ));
        }
        self.c.session.world(|w| w.symbols.insert(name, s));
        Ok(())
    }

    fn register(&mut self, syms: ms_syntax::Names, module: &ModRef) -> Result<(), String> {
        self.c.session.world(|w| {
            w.sources.push(module.clone());
            w.func_modules = None;
        });
        let source_implementation = module.decls.iter().any(has_implementation);
        if source_implementation {
            for d in &module.decls {
                if let DeclKind::Type(r) = &d.decl().kind
                    && r.external
                {
                    self.register_extern_type(syms, module, d)?;
                }
            }
            self.c.session.register_source(module);
            return Ok(());
        }
        let mut symbols: HashMap<Name, SymRef> = HashMap::default();
        for d in &module.decls {
            if let DeclKind::Impl(i) = &d.decl().kind {
                for method in &i.methods {
                    if !method.func.body.is_empty() {
                        return Err(format!(
                            "native implementations must not have bodies: {}",
                            position_text(syms, module.file, method.pos)
                        ));
                    }
                }
                continue;
            }
            if matches!(d.decl().kind, DeclKind::Test(_)) {
                return Err(format!(
                    "standard declarations cannot contain implementation bodies: {}",
                    position_text(syms, module.file, d.pos())
                ));
            }
            if has_implementation(d) {
                return Err(format!(
                    "native declarations must not have bodies: {}",
                    position_text(syms, module.file, d.pos())
                ));
            }
            let name = d.name();
            let (kind, sym_kind) = match &d.decl().kind {
                DeclKind::Fn(_) => (None, SymKind::Fn),
                DeclKind::Type(_) => (Some(Kind::Type), SymKind::Type),
                DeclKind::Alternative(_) => (Some(Kind::Alternative), SymKind::Type),
                DeclKind::Interface(_) => (Some(Kind::Contract), SymKind::Type),
                _ => (None, SymKind::Type),
            };
            let mut id = n(&format!("@std/{name_t}", name_t = syms.str(name)));
            let mut native = Native::Builtin(name);
            if sym_kind == SymKind::Fn {
                // Identities are module/name.
                let ident = format!("{}/{}", module_stem(syms.str(module.file)), syms.str(name));
                native = Native::Builtin(n(&ident));
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
                // `extern type` declares an opaque runtime value; `List` also carries a constructor field.
                let external = matches!(&d.decl().kind, DeclKind::Type(r) if r.external);
                if external || NATIVE_WITH_FIELDS.contains(&syms.str(name)) {
                    kind = Kind::Native;
                }
                let def = Definition::new(&s, kind);
                let mut t = Type::new(syms, name, id, kind);
                t.def = Some(def);
                *s.ty.borrow_mut() = Some(Rc::new(t));
                let duplicate = self.c.session.world(|w| w.symbols.contains_key(&name));
                if duplicate {
                    return Err(format!(
                        "duplicate standard type {name_t}",
                        name_t = syms.str(name)
                    ));
                }
                self.c.session.world(|w| w.symbols.insert(name, s.clone()));
            }
            if symbols.contains_key(&name) {
                return Err(format!(
                    "duplicate standard declaration {}",
                    position_text(syms, module.file, d.pos())
                ));
            }
            symbols.insert(name, s);
        }
        self.c.session.world(|w| {
            w.modules.insert(module.file, symbols);
            w.module_order.push(module.file);
        });
        Ok(())
    }

    fn native_sources(&self) -> Vec<ModRef> {
        self.c.session.world(|w| {
            w.sources
                .iter()
                .filter(|m| !w.source_modules.contains_key(&m.file))
                .cloned()
                .collect()
        })
    }

    fn module_symbol(&self, module: &ModRef, d: &DeclRef) -> SymRef {
        self.c.session.world(|w| {
            w.modules
                .get(&module.file)
                .and_then(|m| m.get(&d.name()))
                .cloned()
                .expect("registered symbol")
        })
    }

    /// Opens the declaration scope of a native module: primitives, the
    /// prelude, its imports, and its own declarations.
    fn scope_module(&mut self, syms: ms_syntax::Names, module: &ModRef) {
        let c = &mut *self.c;
        c.module = Some(module.clone());
        c.names = Rc::new(RefCell::new(HashMap::default()));
        c.scope = crate::checker::Scope::new(None);
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
            c.names.borrow_mut().insert(nm, s);
        }
        c.add_standard_prelude();
        for item in &module.imports {
            let found = c.session.standard_module_symbol(n(&item.path), item.name);
            let Some(found) = found.filter(|f| f.export) else {
                c.res_error(
                    item.name_pos,
                    format!("standard module does not export {}", syms.str(item.name)),
                );
                continue;
            };
            if c.session.is_prelude_symbol(&found) {
                c.redundant_prelude_import(module, item);
            }
            c.add_symbol(item.name, found, item.name_pos);
        }
        for d in &module.decls {
            if matches!(d.decl().kind, DeclKind::Impl(_)) {
                continue;
            }
            let s = c.session.world(|w| {
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
    fn declare_identities(&mut self, syms: ms_syntax::Names) {
        for module in self.native_sources() {
            self.scope_module(syms, &module);
            for d in &module.decls {
                if matches!(d.decl().kind, DeclKind::Impl(_)) {
                    continue;
                }
                let s = self.module_symbol(&module, d);
                self.c.scope = crate::checker::Scope::new(None);
                let mut vars: Vec<Ty> = Vec::new();
                for p in d.type_params() {
                    let v: Ty = Rc::new(Type::new(
                        syms,
                        p.name,
                        n(&format!("{}/{}", syms.str(s.id), syms.str(p.name))),
                        Kind::Variable,
                    ));
                    vars.push(v.clone());
                    self.c.scope.types.borrow_mut().insert(p.name, v);
                }
                *s.variables.borrow_mut() = vars.clone();
                if s.kind == SymKind::Type {
                    let t = s.ty(syms);
                    *t.def.as_ref().expect("def").variables.borrow_mut() = vars.clone();
                    *s.ty.borrow_mut() = Some(with_args(&t, vars));
                }
            }
        }
    }

    /// Fills in native type variables, fields, cases, and operation signatures.
    fn resolve_declarations(&mut self, syms: ms_syntax::Names) {
        for module in self.native_sources() {
            self.scope_module(syms, &module);
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
                let def = s.ty(syms).def.clone().expect("def");
                let fields = self.c.params(d.type_fields());
                *def.fields.borrow_mut() = fields;
                def.clear_cases();
                let mut seen: HashSet<Name> = HashSet::default();
                for cs in d.cases() {
                    if !seen.insert(cs.name) {
                        self.c
                            .type_error(cs.pos, format!("duplicate case {}", syms.str(cs.name)));
                    }
                    let fields = self.c.params(&cs.fields);
                    def.push_case(Case {
                        name: cs.name,
                        fields,
                    });
                }
                let mut seen: HashSet<Name> = HashSet::default();
                for (mi, method) in d.methods().iter().enumerate() {
                    if !seen.insert(method.func.name) {
                        self.c.type_error(
                            method.pos,
                            format!("duplicate operation {}", syms.str(method.func.name)),
                        );
                    }
                    self.c.scope = self.c.variable_scope(&vars);
                    self.c.declare_self(&s.ty(syms));
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
    fn bind_implementations(&mut self, syms: ms_syntax::Names) -> Result<(), String> {
        for module in self.native_sources() {
            self.scope_module(syms, &module);
            for d in &module.decls {
                let DeclKind::Impl(imp) = &d.decl().kind else {
                    continue;
                };
                let start = self.c.p.methods.len();
                self.c.implementation(d);
                let receiver_name = imp.receiver.name(syms).to_string();
                let contract_name = imp
                    .contract
                    .as_ref()
                    .map(|c| c.name(syms).to_string())
                    .unwrap_or_default();
                for index in start..self.c.p.methods.len() {
                    let mut method = (*self.c.p.methods[index]).clone();
                    // A property without operations has no method to bind.
                    let Some(name) = method.name() else {
                        continue;
                    };
                    let key = format!(
                        "{}/{}/{}/{}",
                        syms.str(module.file),
                        receiver_name,
                        contract_name,
                        syms.str(name)
                    );
                    method.id = n(&key);
                    // A native contract method is the contract module's function of that name (`core/message`).
                    let contract_module = self
                        .c
                        .session
                        .world(|w| w.symbols.get(&n(&contract_name)).map(|c| c.module));
                    let native = format!(
                        "{}/{}",
                        module_stem(syms.str(contract_module.unwrap_or(module.file))),
                        syms.str(name)
                    );
                    method.native = Native::Builtin(n(&native));
                    self.c.p.methods[index] = Rc::new(method);
                }
            }
        }
        let implementations = self.c.p.methods.clone();
        self.c
            .session
            .world(|w| w.implementations = implementations);
        if !self.c.p.diagnostics.is_empty() {
            let text: Vec<String> = self.c.p.diagnostics.iter().map(|d| d.to_string()).collect();
            return Err(format!(
                "invalid standard declarations: {}",
                text.join("; ")
            ));
        }
        // A primitive type's operations are the `<Type>Operations` interface `intrinsics.ms` declares,
        // followed by the generic interfaces shared by its family, applied to the primitive itself.
        for receiver in PRIMITIVE_NAMES {
            let mut interfaces = Vec::new();
            let shared = SHARED_OPERATIONS
                .iter()
                .filter(|(_, members)| members.contains(&receiver))
                .map(|(name, _)| (*name).to_string());
            let own = std::iter::once(format!("{receiver}Operations"));
            for name in own.chain(shared) {
                let Some(typ) = self.c.session.world(|w| w.symbols.get(&n(&name)).cloned()) else {
                    continue;
                };
                let ty = typ.ty(syms);
                if ty
                    .def
                    .as_ref()
                    .is_some_and(|d| !d.variables.borrow().is_empty())
                {
                    interfaces.push(with_args(&ty, vec![primitive(primitive_id(receiver))]));
                } else {
                    interfaces.push(ty);
                }
            }
            if !interfaces.is_empty() {
                self.c
                    .session
                    .world(|w| w.intrinsic.insert(n(receiver), interfaces));
            }
        }
        Ok(())
    }

    /// Records the native operations of standard receivers: every bodiless inherent method.
    fn bind_receivers(&mut self, syms: ms_syntax::Names) -> Result<(), String> {
        for module in self.native_sources() {
            self.scope_module(syms, &module);
            for declaration in &module.decls {
                if matches!(declaration.decl().kind, DeclKind::Impl(_)) {
                    continue;
                }
                let symbol = self.module_symbol(&module, declaration);
                if symbol.kind != SymKind::Type || symbol.ty(syms).kind == Kind::Contract {
                    continue;
                }
                for method in declaration.methods() {
                    if method.func.body.is_empty() {
                        let key = format!("{}/{}", syms.str(symbol.id), syms.str(method.func.name));
                        self.c.session.world(|w| w.receiver_natives.insert(key));
                    }
                }
            }
        }
        Ok(())
    }

    /// Checks native default expressions and folds their constants.
    fn check_defaults(&mut self, syms: ms_syntax::Names) -> Result<(), String> {
        self.c.check_type_defaults();
        // Check native default expressions with the ordinary expression checker.
        // Lowering prepares concrete slots before native dispatch; the runtime does
        // not own a second default-expression schema.
        for module in self.native_sources() {
            self.scope_module(syms, &module);
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
                        &symbol.ty(syms),
                        &symbol.variables(),
                        false,
                    );
                } else {
                    let ctor = constructor_signature(syms, &self.c.session, &symbol.ty(syms));
                    self.c.check_native_defaults(
                        &FuncRef::of_decl(declaration.clone()),
                        declaration.type_fields(),
                        &ctor,
                        &symbol.variables(),
                        false,
                    );
                    let operations: Vec<Operation> = symbol
                        .ty(syms)
                        .def
                        .as_ref()
                        .expect("def")
                        .operations
                        .borrow()
                        .clone();
                    for operation in operations {
                        let Some(method) =
                            standard_method_declaration(&symbol.ty(syms), operation.name)
                        else {
                            continue;
                        };
                        let mut variables = symbol.variables();
                        variables.extend(self.c.session.operation_variables(&format!(
                            "{}/{}",
                            syms.str(symbol.id),
                            syms.str(operation.name)
                        )));
                        let params = method.func().map(|f| f.params.as_slice()).unwrap_or(&[]);
                        self.c.check_native_defaults(
                            &method,
                            params,
                            &operation.ty,
                            &variables,
                            symbol.ty(syms).kind == Kind::Contract,
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

// ------------------------------------------------------------------ session

impl Session {
    /// Loads the standard declarations on first use.
    pub fn ensure_standard(self: &Rc<Self>) {
        let state = self.world(|w| w.state);
        if state != 0 {
            return;
        }
        self.world(|w| w.state = 1);
        if let Err(e) = self.load() {
            panic!("standard declarations: {e}");
        }
        self.world(|w| w.state = 2);
        // Types that native modules took from a source module are filled in by checking that module.
        let stubs = self.world(|w| std::mem::take(&mut w.stub_modules));
        for path in stubs {
            if let Some(module) = self.standard_source_module(path) {
                // An invalid module is reported where a program imports it.
                let _ = self.ensure_source(&module);
            }
        }
    }

    /// Every bundled module (native and source) in file-name order, with the
    /// original source text, for editors that show standard declarations.
    pub fn standard_modules(self: &Rc<Self>) -> Vec<ModRef> {
        self.load_deferred_all();
        self.world(|w| w.sources.clone())
    }

    /// A standard type declared natively or as source, by name.
    pub fn standard_symbol(self: &Rc<Self>, name: &str) -> Option<SymRef> {
        self.ensure_standard();
        self.world(|w| w.symbols.get(&n(name)).cloned())
    }

    /// Whether a symbol is a canonical source-backed prelude declaration.
    pub fn is_prelude_symbol(self: &Rc<Self>, symbol: &SymRef) -> bool {
        if STANDARD_PRELUDE_FUNCTIONS
            .iter()
            .any(|(path, name)| symbol.name == n(name) && symbol.module == n(path))
        {
            return true;
        }
        if !STANDARD_PRELUDE_NAMES.contains(&self.syms.str(symbol.name)) {
            return false;
        }
        self.world(|w| {
            w.symbols
                .get(&symbol.name)
                .is_some_and(|s| Rc::ptr_eq(s, symbol))
        })
    }

    /// Native implementations of contracts for standard types.
    pub fn standard_implementations(self: &Rc<Self>) -> Vec<MethodRef> {
        self.ensure_standard();
        self.world(|w| w.implementations.clone())
    }

    /// The intrinsic declaration for a primitive receiver id.
    pub fn intrinsic_operations(self: &Rc<Self>, id: Name) -> Vec<Ty> {
        self.ensure_standard();
        self.world(|w| w.intrinsic.get(&id).cloned().unwrap_or_default())
    }

    /// Whether `Receiver id/name` is a native operation of a standard receiver: an inherent method the
    /// standard source declares without a body. Its native identity is the method's name; lowering tells
    /// receivers apart by type.
    pub fn is_receiver_native(self: &Rc<Self>, key: &str) -> bool {
        self.world(|w| w.receiver_natives.contains(key))
    }

    /// Records the type variables an operation declares for itself (`Receiver id/name`).
    pub(crate) fn set_operation_variables(self: &Rc<Self>, key: String, variables: Vec<Ty>) {
        self.world(|w| {
            w.operation_variables.insert(key, variables);
        });
    }

    /// The operation's own type variables (`Receiver id/name`).
    pub fn operation_variables(self: &Rc<Self>, key: &str) -> Vec<Ty> {
        self.world(|w| w.operation_variables.get(key).cloned().unwrap_or_default())
    }

    /// The bundled module that declares the function or method `f`.
    pub fn func_module(self: &Rc<Self>, f: &ms_syntax::ast::Func) -> Option<ModRef> {
        self.world(|w| {
            if w.func_modules.is_none() {
                let mut map = HashMap::default();
                for m in &w.sources {
                    for d in &m.decls {
                        if let Some(f) = d.func() {
                            map.insert(f as *const _ as usize, m.clone());
                        }
                        for method in d.methods() {
                            map.insert(&method.func as *const _ as usize, m.clone());
                        }
                    }
                }
                w.func_modules = Some(map);
            }
            w.func_modules
                .as_ref()?
                .get(&(f as *const _ as usize))
                .cloned()
        })
    }

    /// The bundled module checked from `file`, if the standard library has one.
    pub fn bundled_module(self: &Rc<Self>, file: Name) -> Option<ModRef> {
        self.world(|w| w.sources.iter().find(|m| m.file == file).cloned())
    }

    pub fn is_source_module(self: &Rc<Self>, module: &ModRef) -> bool {
        self.world(|w| {
            w.source_modules
                .get(&module.file)
                .is_some_and(|m| Rc::ptr_eq(m, module))
        })
    }

    /// A bundled source module by path.
    pub fn standard_source_module(self: &Rc<Self>, path: Name) -> Option<ModRef> {
        self.ensure_standard();
        self.load_deferred(path);
        self.world(|w| w.source_modules.get(&path).cloned())
    }

    /// The bundled source module an import reads from: the module itself, or for a name that only the source half of a mixed
    /// native file declares, that file's `+source` twin.
    pub fn import_source(self: &Rc<Self>, item: &Import) -> Option<ModRef> {
        let path = n(&item.path);
        if let Some(module) = self.standard_source_module(path) {
            return Some(module);
        }
        if self.standard_module_symbol(path, item.name).is_some() {
            return None;
        }
        self.standard_source_module(n(&format!("{}+source", item.path)))
    }

    /// Whether the path names a native bundled module.
    pub fn is_native_module(self: &Rc<Self>, path: Name) -> bool {
        self.ensure_standard();
        self.world(|w| w.modules.contains_key(&path))
    }

    /// The symbol of a type or alternative declared in a bundled source module, as registered at load.
    pub fn source_type(self: &Rc<Self>, module: Name, name: Name) -> Option<SymRef> {
        self.ensure_standard();
        self.load_deferred(module);
        self.world(|w| w.source_types.get(&(module, name)).cloned())
    }

    /// A native module's declaration by name.
    pub fn standard_module_symbol(self: &Rc<Self>, path: Name, name: Name) -> Option<SymRef> {
        self.ensure_standard();
        self.load_deferred(path);
        self.world(|w| {
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

    /// Every public bundled module path in sorted order.
    pub fn standard_module_names(self: &Rc<Self>) -> Vec<&'static str> {
        self.load_deferred_all();
        let mut names: BTreeSet<&'static str> = BTreeSet::new();
        self.world(|w| {
            names.extend(w.modules.keys().map(|k| self.syms.str(k)));
            names.extend(w.source_modules.keys().map(|k| self.syms.str(k)));
        });
        names
            .into_iter()
            .filter(|path| !is_internal(path) && !path.ends_with("+source"))
            .collect()
    }

    /// A standard module's exported declarations, checking a bundled source
    /// module on first use.
    pub fn standard_exports(self: &Rc<Self>, path: &str) -> HashMap<Name, SymRef> {
        let path = n(path);
        if let Some(module) = self.standard_source_module(path) {
            // An invalid module is reported where a program imports it.
            let Ok(checked) = self.ensure_source(&module) else {
                return HashMap::default();
            };
            return checked
                .exports
                .iter()
                .filter(|(_, s)| s.export)
                .map(|(k, v)| (*k, v.clone()))
                .collect();
        }
        let mut exports: HashMap<Name, SymRef> = self.world(|w| {
            w.modules
                .get(&path)
                .map(|m| {
                    m.iter()
                        .filter(|(_, s)| s.export)
                        .map(|(k, v)| (*k, v.clone()))
                        .collect()
                })
                .unwrap_or_default()
        });
        // The bodies of a mixed file export under the file's own name too.
        if let Some(twin) = self
            .standard_source_module(n(&format!("{path_t}+source", path_t = self.syms.str(path))))
        {
            for (name, symbol) in self.standard_exports(self.syms.str(twin.file)) {
                if symbol.module == twin.file {
                    exports.entry(name).or_insert(symbol);
                }
            }
        }
        exports
    }

    /// Whether a bundled source module is being checked right now. Queries that visit every
    /// module (import hints) must not run then: they would re-enter modules of the open group
    /// and replace the real diagnostic with a cyclic-dependency panic.
    pub fn checking_sources(self: &Rc<Self>) -> bool {
        self.world(|w| !w.checking.is_empty())
    }

    /// The checked result of a bundled source module, if it has been checked.
    pub fn done(self: &Rc<Self>, file: Name) -> Option<Rc<StdResult>> {
        self.world(|w| w.done.get(&file).cloned())
    }

    fn source_reach(self: &Rc<Self>, module: &ModRef) -> Vec<ModRef> {
        let mut seen: Vec<ModRef> = Vec::new();
        let mut stack: Vec<ModRef> = vec![module.clone()];
        while let Some(m) = stack.pop() {
            for item in &m.imports {
                if let Some(dep) = self.import_source(item)
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
    fn source_group(self: &Rc<Self>, module: &ModRef) -> Vec<ModRef> {
        let mut group = vec![module.clone()];
        for m in self.source_reach(module) {
            if m.file != module.file && self.source_reach(&m).iter().any(|r| r.file == module.file)
            {
                group.push(m);
            }
        }
        group
    }

    /// Whether `module` is an extension module or one an extension module imports.
    fn extension_reach(self: &Rc<Self>, module: &ModRef) -> bool {
        EXTENSION_MODULES.iter().any(|path| {
            self.syms.str(module.file) == *path
                || self.standard_source_module(n(path)).is_some_and(|ext| {
                    self.source_reach(&ext)
                        .iter()
                        .any(|m| m.file == module.file)
                })
        })
    }

    /// Checks a bundled source module and the bundled modules it imports, once.
    /// Modules that import each other are checked together.
    /// A module that does not check is a defect in the bundled library, reported as an error
    /// naming the module rather than a panic.
    pub fn ensure_source(self: &Rc<Self>, module: &ModRef) -> Result<Rc<StdResult>, String> {
        self.ensure_standard();
        if let Some(r) = self.done(module.file) {
            return Ok(r);
        }
        let group = self.source_group(module);
        let cycle = self.world(|w| group.iter().any(|g| !w.checking.insert(g.file)));
        if cycle {
            panic!(
                "cyclic standard source dependency at {} while checking {:?}",
                self.syms.str(module.file),
                self.world(|w| w.checking.clone())
            );
        }
        let result = self.check_group_sources(module, &group);
        if result.is_err() {
            self.world(|w| {
                for g in &group {
                    w.checking.remove(&g.file);
                }
            });
        }
        result
    }

    fn check_group_sources(
        self: &Rc<Self>,
        module: &ModRef,
        group: &[ModRef],
    ) -> Result<Rc<StdResult>, String> {
        for g in group {
            for item in &g.imports {
                if let Some(dep) = self.import_source(item)
                    && !group.iter().any(|m| m.file == dep.file)
                {
                    self.ensure_source(&dep)?;
                }
            }
        }
        // An extension module and what it imports cannot depend on the extensions, so they are not loaded for them.
        let extending = self.extension_reach(module);
        for path in EXTENSION_MODULES.iter().filter(|_| !extending) {
            if let Some(extension) = self.standard_source_module(n(path))
                && !group.iter().any(|m| m.file == extension.file)
            {
                self.ensure_source(&extension)?;
            }
        }
        let mut checker = Checker::new(
            self,
            &CheckOptions {
                bundled: Some(module.file),
                ..CheckOptions::default()
            },
        );
        checker.id_scope = format!("standard_{}_", module_stem(self.syms.str(module.file)));
        if group.len() > 1 {
            checker.group = group.to_vec();
        }
        let program = checker.check_modules(vec![module.clone()], Some(module.file));
        if !program.diagnostics.is_empty() {
            let text: Vec<String> = program.diagnostics.iter().map(|d| d.to_string()).collect();
            return Err(format!(
                "invalid standard implementation {}: {}",
                self.syms.str(module.file),
                text.join("; ")
            ));
        }
        for g in group {
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
            self.world(|w| {
                w.done.insert(g.file, result.clone());
                w.checking.remove(&g.file);
            });
        }
        Ok(self.done(module.file).expect("checked"))
    }

    /// Checks every bundled source module and returns the error of each one that is invalid.
    pub fn check_all_sources(self: &Rc<Self>) -> Vec<String> {
        self.load_deferred_all();
        let sources: Vec<ModRef> = self.world(|w| w.sources.clone());
        sources
            .iter()
            .filter(|m| self.is_source_module(m))
            .filter_map(|m| self.ensure_source(m).err())
            .collect()
    }

    /// All bundled source modules, checked; panics if one is invalid.
    pub fn ensure_all_sources(self: &Rc<Self>) {
        let errors = self.check_all_sources();
        assert!(errors.is_empty(), "{}", errors.join("\n"));
    }

    /// Adds reachable bundled implementations to a module list in dependency order.
    pub fn source_standard_dependencies(
        self: &Rc<Self>,
        modules: Vec<ModRef>,
    ) -> (Vec<ModRef>, Vec<Diagnostic>) {
        let mut ordered: Vec<ModRef> = Vec::new();
        let mut diagnostics: Vec<Diagnostic> = Vec::new();
        let mut state: HashMap<Name, u8> = HashMap::default();
        fn visit(
            syms: ms_syntax::Names,
            session: &Rc<Session>,
            module: &ModRef,
            state: &mut HashMap<Name, u8>,
            ordered: &mut Vec<ModRef>,
            diagnostics: &mut Vec<Diagnostic>,
        ) {
            match state.get(&module.file) {
                Some(2) => return,
                Some(1) if session.is_source_module(module) => return,
                Some(1) => {
                    diagnostics.push(Diagnostic {
                        cause: Default::default(),
                        opener_line: 0,
                        file: Arc::from(syms.str(module.file)),
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
                if let Some(dep) = session.import_source(item) {
                    visit(syms, session, &dep, state, ordered, diagnostics);
                }
            }
            state.insert(module.file, 2);
            ordered.push(module.clone());
        }
        // The operations written in Manuscript on native types apply to every program.
        // An extension module and what it imports do not depend on the extensions.
        let extending = modules.iter().any(|m| self.extension_reach(m));
        for path in EXTENSION_MODULES.iter().filter(|_| !extending) {
            if let Some(extension) = self.standard_source_module(n(path)) {
                visit(
                    self.syms,
                    self,
                    &extension,
                    &mut state,
                    &mut ordered,
                    &mut diagnostics,
                );
            }
        }
        // A `bench` block runs under the driver in `@std/test/bench.ms`, which its module need not import.
        let benching = modules.iter().any(|m| {
            m.decls
                .iter()
                .any(|d| matches!(&d.decl().kind, DeclKind::Test(t) if t.bench))
        });
        if benching && let Some(driver) = self.standard_source_module(n("@std/test/bench.ms")) {
            visit(
                self.syms,
                self,
                &driver,
                &mut state,
                &mut ordered,
                &mut diagnostics,
            );
        }
        // Test blocks run under the promise harness in `@std/test/runner.ms`.
        let testing = modules.iter().any(|m| {
            m.decls
                .iter()
                .any(|d| matches!(&d.decl().kind, DeclKind::Test(t) if !t.bench))
        });
        if testing && let Some(runner) = self.standard_source_module(n("@std/test/runner.ms")) {
            visit(
                self.syms,
                self,
                &runner,
                &mut state,
                &mut ordered,
                &mut diagnostics,
            );
        }
        // Prelude functions reach user code without an import, so their modules come with any program of its own.
        if modules.iter().any(|m| !m.is_standard(self.syms)) {
            for (path, name) in STANDARD_PRELUDE_FUNCTIONS {
                if let Some(dep) = self.import_source(&prelude_function_import(path, name)) {
                    visit(
                        self.syms,
                        self,
                        &dep,
                        &mut state,
                        &mut ordered,
                        &mut diagnostics,
                    );
                }
            }
        }
        for m in &modules {
            visit(
                self.syms,
                self,
                m,
                &mut state,
                &mut ordered,
                &mut diagnostics,
            );
        }
        (ordered, diagnostics)
    }

    /// Parses and registers a deferred pure source module, if `path` names one that has not loaded yet.
    fn load_deferred(self: &Rc<Self>, path: Name) {
        let Some(source) = self.world(|w| w.deferred.remove(&path)) else {
            return;
        };
        let modules = parse_bundled(self.syms.str(path), source)
            .and_then(|parsed| {
                if !is_pure_source(&parsed) {
                    return Err(format!(
                        "{path_t} is not pure source; build.rs must load it eagerly",
                        path_t = self.syms.str(path)
                    ));
                }
                bundled_modules(self.syms, &parsed)
            })
            .unwrap_or_else(|e| panic!("standard declarations: {e}"));
        for module in modules {
            self.register_source(&module);
            self.world(|w| {
                w.sources.push(module);
                // A module loaded later declares functions the index has not seen.
                w.func_modules = None;
            });
        }
        self.world(|w| {
            w.sources
                .sort_by(|a, b| self.syms.str(a.file).cmp(self.syms.str(b.file)))
        });
    }

    /// Loads every deferred module, for callers that list or check the whole standard library.
    fn load_deferred_all(self: &Rc<Self>) {
        self.ensure_standard();
        let mut paths: Vec<Name> = self.world(|w| w.deferred.keys().copied().collect());
        paths.sort_by(|a, b| self.syms.str(a).cmp(self.syms.str(b)));
        for path in paths {
            self.load_deferred(path);
        }
    }

    fn load(self: &Rc<Self>) -> Result<(), String> {
        let mut modules: Vec<ModRef> = Vec::new();
        for (name, source, eager) in SOURCES {
            let file = format!("@std/{name}");
            if *eager {
                modules.extend(bundled_modules(self.syms, &parse_bundled(&file, source)?)?);
            } else {
                self.world(|w| w.deferred.insert(n(&file), source));
            }
        }
        let mut checker = Checker::new(self, &CheckOptions::default());
        checker.standard_declarations = true;
        let mut loader = Loader { c: &mut checker };
        for module in &modules {
            loader.register(self.syms, module)?;
        }
        loader.declare_identities(self.syms);
        loader.resolve_declarations(self.syms);
        loader.bind_implementations(self.syms)?;
        loader.bind_receivers(self.syms)?;
        loader.check_defaults(self.syms)?;
        Ok(())
    }

    /// Registers a source module: the exported types native modules can name before it is checked. The loader
    /// registers its `extern type`s; a deferred module has none, since `extern` anywhere in it keeps it eager.
    fn register_source(self: &Rc<Self>, module: &ModRef) {
        for d in &module.decls {
            match &d.decl().kind {
                DeclKind::Type(r) if r.external => {}
                DeclKind::Type(_) | DeclKind::Alternative(_) | DeclKind::Interface(_)
                    if d.decl().export =>
                {
                    let stub = source_type_symbol(self.syms, module, d);
                    self.world(|w| w.source_types.insert((module.file, d.name()), stub));
                }
                _ => {}
            }
        }
        self.world(|w| {
            w.source_modules.insert(module.file, module.clone());
        });
    }

    /// A standard declaration by name, applied to `args`.
    pub fn standard(self: &Rc<Self>, name: &str, args: Vec<Ty>) -> Ty {
        let sym = self
            .standard_symbol(name)
            .unwrap_or_else(|| panic!("standard type {name}"));
        with_args(&sym.ty(self.syms), args)
    }

    /// The name of the one operation of the single-operation interface `name` declared in the bundled
    /// source module `module` (`to_json` for `JsonEncode`), read from its declaration. `None` while
    /// the module is not loaded: nothing can implement an interface its program never imported.
    pub fn sole_operation(self: &Rc<Self>, module: &str, name: &str) -> Option<Name> {
        let sym = self
            .standard_symbol(name)
            .filter(|s| self.syms.str(s.module) == module)
            .or_else(|| self.world(|w| w.source_types.get(&(n(module), n(name))).cloned()))?;
        let contract = sym.ty(self.syms);
        let ops = contract.def.as_ref()?.operations.borrow();
        match ops.as_slice() {
            [op] => Some(op.name),
            _ => None,
        }
    }

    /// `Duration`, `Instant` or `Timestamp`, the types of `@std/time.ms`.
    pub fn time_type(self: &Rc<Self>, name: &str) -> Ty {
        // The module is checked on first use; its types have no fields before that.
        self.standard_exports("@std/time.ms");
        let sym = self
            .source_type(n("@std/time.ms"), n(name))
            .unwrap_or_else(|| panic!("standard time type {name}"));
        sym.ty(self.syms)
    }

    /// `TestHooks`, the interface of `@std/test/test.ms`, which a program loads only when it has a fixture.
    pub fn test_hooks(self: &Rc<Self>) -> Ty {
        self.standard_exports("@std/test/test.ms");
        let sym = self
            .source_type(n("@std/test/test.ms"), n("TestHooks"))
            .unwrap_or_else(|| panic!("standard type TestHooks"));
        sym.ty(self.syms)
    }

    /// `TestOutcome`: the implicit `Result[Unit, Error]` of a test block.
    pub fn test_outcome(self: &Rc<Self>) -> Ty {
        self.standard("Result", vec![unit(), self.standard("Error", vec![])])
    }
}

/// A definition's fields, cases and operations hold types that name the definition again, so
/// dropping the world alone leaves each cycle allocated. The session owns every definition it
/// loaded, and a `Program` keeps the session alive for as long as its types are used, so the
/// contents are released when the last owner of the session goes.
impl Drop for Session {
    fn drop(&mut self) {
        let world = self.world.borrow();
        let tables = world.modules.values().flat_map(HashMap::values);
        let defs: Vec<Rc<Definition>> = tables
            .chain(world.symbols.values())
            .filter_map(|sym| sym.ty.borrow().as_ref().and_then(|t| t.def.clone()))
            .collect();
        drop(world);
        for d in defs {
            d.variables.borrow_mut().clear();
            d.fields.borrow_mut().clear();
            d.cases.borrow_mut().clear();
            d.operations.borrow_mut().clear();
        }
    }
}

/// Constructor inputs and omission permissions.
pub fn constructor_signature(
    syms: ms_syntax::Names,
    session: &Rc<crate::stdlib::Session>,
    t: &Ty,
) -> Ty {
    let mut params = fields(t);
    if t.is(Builtin::Bytes) {
        params = vec![crate::types::Param::new(
            n("values"),
            session.standard("List", vec![primitive("UInt8")]),
        )];
    }
    if t.is(Builtin::Set) && t.args.len() == 1 {
        params = vec![crate::types::Param::new(
            n("values"),
            session.standard("List", vec![t.args[0].clone()]),
        )];
    }
    let mut defaults: HashSet<Name> = HashSet::default();
    if let Some(sym) = t.symbol()
        && let Some(decl) = &sym.decl
    {
        for f in decl.type_fields() {
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
    function_with(syms, params, t.clone(), defaults)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn halves(syms: ms_syntax::Names, text: &str) -> Result<Option<Halves>, String> {
        let file: Arc<str> = Arc::from("@std/t.ms");
        split_mixed(
            syms,
            &ms_syntax::parser::parse(&file, text).expect("parses"),
        )
    }

    #[test]
    fn every_embedded_module_type_checks() {
        let errors = Session::new().check_all_sources();
        assert!(errors.is_empty(), "{}", errors.join("\n"));
    }

    #[test]
    fn dropping_a_session_releases_its_definitions() {
        let session = Session::new();
        let list = session.standard_symbol("List").unwrap();
        let def = Rc::downgrade(list.ty.borrow().as_ref().unwrap().def.as_ref().unwrap());
        drop(list);
        drop(session);
        assert!(
            def.upgrade().is_none(),
            "the definition cycle outlived its session"
        );
    }

    #[test]
    fn sessions_on_one_thread_are_independent() {
        let (a, b) = (Session::new(), Session::new());
        let (la, lb) = (
            a.standard_symbol("List").unwrap(),
            b.standard_symbol("List").unwrap(),
        );
        assert!(!Rc::ptr_eq(&la, &lb), "each session loads its own world");
        assert!(a.is_prelude_symbol(&la) && !a.is_prelude_symbol(&lb));
        let (a1, b1) = (a.next_binding(), b.next_binding());
        assert_eq!(a.next_binding(), a1 + 1);
        assert_eq!(b.next_binding(), b1 + 1, "counters are per session");
    }

    #[test]
    fn pure_source_modules_load_on_first_lookup() {
        let syms = ms_syntax::Names::global();
        let session = Session::new();
        session.ensure_standard();
        let yaml = n("@std/data/yaml.ms");
        assert!(session.world(|w| w.deferred.contains_key(&yaml)));
        let module = session
            .standard_source_module(yaml)
            .expect("yaml loads on lookup");
        assert!(session.world(|w| !w.deferred.contains_key(&yaml)));
        assert!(!session.ensure_source(&module).unwrap().exports.is_empty());
        let sources = session.standard_modules();
        assert!(session.world(|w| w.deferred.is_empty()));
        assert_eq!(
            sources.len(),
            session.world(|w| w.source_modules.len() + w.modules.len())
        );
        assert!(
            sources
                .windows(2)
                .all(|p| syms.str(p[0].file) < syms.str(p[1].file))
        );
    }

    #[test]
    fn a_bodied_receiver_method_goes_to_the_source_half() {
        let syms = ms_syntax::Names::global();
        let text = "export type Box[T]: ...\n\nfn Box[T].native() Int: ...\n\nfn Box[T].size() Int:\n    return 1\n";
        let (native, source, foreign) = halves(syms, text).unwrap().expect("mixed");
        assert_eq!(native.file.as_ref(), "@std/t.ms");
        assert_eq!(source.file.as_ref(), "@std/t.ms+source");
        assert_eq!(native.decls.len(), 2);
        let kinds: Vec<&str> = source
            .decls
            .iter()
            .map(|d| match &d.kind {
                DeclKind::Impl(i) if i.contract.is_none() => "receiver method",
                _ => "other",
            })
            .collect();
        assert_eq!(kinds, ["receiver method"]);
        // The source half names the native half's type through its declaration.
        assert_eq!(foreign.len(), 1);
    }

    #[test]
    fn a_file_without_bodies_is_not_split() {
        let syms = ms_syntax::Names::global();
        let text = "export type Box: ...\n\nfn Box.native() Int: ...\n";
        assert!(halves(syms, text).unwrap().is_none());
    }
}

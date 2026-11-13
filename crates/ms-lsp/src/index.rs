//! The occurrence index: every resolved declaration and use in the checked
//! modules, keyed so that references, rename and highlights group by identity
//! across files .

use crate::analysis::Analysis;
use ms_check::api::syntax::{DeclRef, FuncRef, Info, ModRef};
use ms_check::api::types::{BindingRef, Kind, Method, MethodRef, Name, SymRef, Ty, fields};
use ms_syntax::Symbol;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// What the checker knows about a resolved occurrence.
#[derive(Clone, Default)]
pub struct OccInfo {
    /// Type.
    pub ty: Option<Ty>,
    /// Resolved module symbol.
    pub symbol: Option<SymRef>,
    /// Resolved local binding.
    pub binding: Option<BindingRef>,
    /// Resolved method.
    pub method: Option<MethodRef>,
    /// Constructed type.
    pub constructor: Option<Ty>,
    /// Constructed case.
    pub case: Option<Name>,
}

impl OccInfo {
    /// Narrows checker facts to what navigation uses.
    pub fn of(info: &Info) -> OccInfo {
        OccInfo {
            ty: info.ty.clone(),
            symbol: info.symbol.clone(),
            binding: info.binding.clone(),
            method: info.method.clone(),
            constructor: info.constructor.clone(),
            case: info.case,
        }
    }
}

/// Recovery facts can retain types for a rejected opaque representation access.
/// Editors must not advertise those fields, cases or constructor parameters.
pub(crate) fn hidden_structure(
    module: &ModRef,
    e: &Expr,
    info: &Info,
    cache: &mut HashMap<NodeId, bool>,
) -> bool {
    fn receiver(e: &Expr) -> Option<&Expr> {
        match &e.kind {
            ExprKind::Member { left, .. }
            | ExprKind::Apply { left, .. }
            | ExprKind::Index { left, .. } => Some(left),
            ExprKind::Call { callee, .. } => Some(callee),
            ExprKind::Probe(target)
            | ExprKind::Unary {
                operand: target, ..
            } => Some(target),
            _ => None,
        }
    }
    let hidden_type = |ty: &Ty| ty.opaque_module().is_some_and(|file| file != module.file);
    let facts = module.facts();
    let (mut expression, mut current) = (e, info);
    let hidden = loop {
        if let Some(hidden) = cache.get(&expression.id) {
            break *hidden;
        }
        if current.constructor.as_ref().is_some_and(hidden_type) {
            break true;
        }
        let Some(next) = receiver(expression) else {
            break false;
        };
        let Some(next_info) = facts.info(next.id) else {
            break false;
        };
        if matches!(expression.kind, ExprKind::Member { .. })
            && current.method.is_none()
            && next_info.ty.as_ref().is_some_and(hidden_type)
        {
            break true;
        }
        (expression, current) = (next, next_info);
    };
    // Cache the inspected prefix with a second walk, without allocating a path
    // vector for every short member access. Later queries reuse the suffix.
    let stop = expression.id;
    let mut expression = e;
    while expression.id != stop {
        cache.insert(expression.id, hidden);
        let Some(next) = receiver(expression) else {
            break;
        };
        expression = next;
    }
    hidden
}

/// One occurrence of an identity in source.
#[derive(Clone)]
pub struct Occurrence {
    /// Identity: equal keys name the same declaration across files.
    pub key: String,
    /// The written name.
    pub name: String,
    /// Logical module file.
    pub file: Name,
    /// Start byte.
    pub offset: usize,
    /// End byte (exclusive).
    pub end: usize,
    /// Whether this is the declaration.
    pub declaration: bool,
    /// Whether the occurrence is assigned.
    pub write: bool,
    /// Checked facts.
    pub info: Option<Rc<OccInfo>>,
}

/// A module's identity across analyses with different source roots. Bundled
/// declarations keep their virtual identity; project paths are already canonical
/// in the loader and must not be compared as graph-relative names.
fn source_key(syms: ms_syntax::Names, root: &str, file: Name) -> String {
    if syms.str(file).starts_with("@std/") {
        syms.str(file).to_string()
    } else {
        ms_driver::project::pathops::join(&[root, syms.str(file)])
    }
}

/// Lowered suffixes and omitted arguments have checked facts but no name token.
fn written_name(source: &str, offset: usize, name: &str) -> bool {
    let end = offset + name.len();
    source.get(offset..end) == Some(name)
        && source
            .as_bytes()
            .get(end)
            .is_none_or(|byte| !crate::text::identifier(*byte))
}

/// The key of a module symbol.
pub fn symbol_key(syms: ms_syntax::Names, root: &str, s: Option<&SymRef>) -> String {
    match s {
        None => String::new(),
        Some(s) => match &s.decl {
            Some(decl) => format!(
                "symbol:{}:{}",
                source_key(syms, root, s.module),
                decl.pos().offset
            ),
            None => format!("native:{}", syms.str(s.id)),
        },
    }
}

/// The identity of a method: contract operations group a contract and all its
/// implementations; other methods are keyed by declaration.
pub fn method_key(syms: ms_syntax::Names, root: &str, files: &DeclFiles, m: &Method) -> String {
    if let (Some(decl), Some(contract)) = (&m.decl, &m.contract)
        && let Some(symbol) = contract.symbol()
        && let Some(contract_decl) = &symbol.decl
    {
        return format!(
            "operation:{}:{}:{}",
            source_key(syms, root, symbol.module),
            contract_decl.pos().offset,
            syms.str(decl.name())
        );
    }
    match &m.decl {
        Some(decl) => format!(
            "method:{}:{}",
            source_key(syms, root, files.file(decl, m.module)),
            decl.pos().offset
        ),
        None => String::new(),
    }
}

/// The module each declaration was parsed in.
pub struct DeclFiles {
    files: HashMap<usize, Name>,
}

impl DeclFiles {
    /// Indexes the declarations of `modules`.
    pub fn new(modules: &[ModRef]) -> DeclFiles {
        let mut files = HashMap::new();
        for m in modules {
            for d in &m.decls {
                files.insert(Rc::as_ptr(&d.0) as usize, m.file);
            }
        }
        DeclFiles { files }
    }

    /// The module of a declaration, or `fallback`.
    pub fn file(&self, decl: &FuncRef, fallback: Name) -> Name {
        self.of_decl(&decl.decl).unwrap_or(fallback)
    }

    /// The module of a declaration.
    pub fn of_decl(&self, decl: &DeclRef) -> Option<Name> {
        self.files.get(&(Rc::as_ptr(&decl.0) as usize)).copied()
    }
}

/// The text a syntax expression is addressed by (Go `Expression.Text`).
pub fn expr_text(syms: ms_syntax::Names, e: &Expr) -> Option<&'static str> {
    match &e.kind {
        ExprKind::Name(s) | ExprKind::Number(s) => Some(syms.str(s)),
        ExprKind::Member { name, .. } => Some(syms.str(name)),
        ExprKind::Bool(true) => Some("true"),
        ExprKind::Bool(false) => Some("false"),
        ExprKind::Unit => Some("unit"),
        ExprKind::List(_) => Some("["),
        ExprKind::Map(_) => Some("{"),
        ExprKind::Match { .. } => Some("match"),
        ExprKind::Unary { op, .. } => Some(op.as_str()),
        ExprKind::Binary { op, .. } => Some(op.as_str()),
        _ => None,
    }
}

struct Builder {
    root: String,
    files: DeclFiles,
    by_file: HashMap<Name, ModRef>,
    binding_keys: HashMap<usize, String>,
    seen: HashSet<(Name, usize, String)>,
    out: Vec<Occurrence>,
}

fn binding_ptr(b: &BindingRef) -> usize {
    Rc::as_ptr(b) as usize
}

impl Builder {
    #[allow(clippy::too_many_arguments)]
    fn add(
        &mut self,
        key: String,
        name: &str,
        file: Name,
        offset: usize,
        declaration: bool,
        write: bool,
        info: OccInfo,
    ) {
        if key.is_empty()
            || name.is_empty()
            || !written_name(&self.by_file[&file].source, offset, name)
        {
            return;
        }
        if !self.seen.insert((file, offset, key.clone())) {
            return;
        }
        self.out.push(Occurrence {
            key,
            name: name.to_string(),
            file,
            offset,
            end: offset + name.len(),
            declaration,
            write,
            info: Some(Rc::new(info)),
        });
    }

    fn local_key(&self, syms: ms_syntax::Names, b: &BindingRef) -> String {
        self.binding_keys
            .get(&binding_ptr(b))
            .cloned()
            .unwrap_or_else(|| format!("binding:{}", syms.str(b.id)))
    }

    fn header(&self, file: Name, pos: usize, name: &str) -> usize {
        crate::text::header(&self.by_file[&file].source, pos, name).unwrap_or(pos)
    }
}

/// Builds the sorted occurrence index of all modules the analysis can show.
pub fn source_index(syms: ms_syntax::Names, analysis: &Analysis) -> Vec<Occurrence> {
    build_index(syms, analysis, true)
}

/// Builds the sorted occurrence index of the project's modules, and of the bundled standard
/// modules when `standard` is set.
pub fn build_index(syms: ms_syntax::Names, analysis: &Analysis, standard: bool) -> Vec<Occurrence> {
    let Some(program) = &analysis.program else {
        return Vec::new();
    };
    let modules = if standard {
        analysis.source_modules(syms)
    } else {
        analysis.project_modules(syms)
    };
    let mut b = Builder {
        root: analysis.module_path(""),
        files: DeclFiles::new(&modules),
        by_file: modules.iter().map(|m| (m.file, m.clone())).collect(),
        binding_keys: HashMap::new(),
        seen: HashSet::new(),
        out: Vec::new(),
    };
    // Checked facts exist only for modules this program contains; bundled
    // modules it never imports contribute declarations but no uses.
    let checked: HashSet<Name> = program.modules.iter().map(|m| m.file).collect();

    // Parameter bindings first: calls and records name them by key.
    for m in modules.iter().filter(|m| checked.contains(&m.file)) {
        for d in &m.decls {
            for func in callables(d) {
                let facts = m.facts();
                let Some(decl_facts) = facts.decls.get(&func.id()) else {
                    continue;
                };
                for (index, binding) in decl_facts.parameters.iter().enumerate() {
                    let mut key = format!(
                        "parameter:{}:{}:{}",
                        source_key(syms, &b.root, m.file),
                        func.pos().offset,
                        index
                    );
                    if matches!(d.decl().kind, DeclKind::Type(_)) && func.index.is_none() {
                        let symbol = program
                            .symbols
                            .get(&m.file)
                            .and_then(|names| names.borrow().get(&d.name()).cloned());
                        if let Some(symbol) = symbol {
                            key = format!(
                                "field:{}:{}",
                                symbol_key(syms, &b.root, Some(&symbol)),
                                syms.str(binding.name)
                            );
                        }
                    }
                    b.binding_keys.insert(binding_ptr(binding), key);
                }
            }
        }
    }

    for m in &modules {
        let symbols = module_symbols(syms, analysis, m);
        for d in &m.decls {
            if d.0.decl.synthetic && matches!(d.decl().kind, DeclKind::Interface(_)) {
                continue;
            }
            if let Some(symbol) = symbols.get(&d.name())
                && symbol.decl.as_ref().is_some_and(|sd| sd.same(d))
            {
                let at = b.header(m.file, d.pos().offset as usize, syms.str(symbol.name));
                b.add(
                    symbol_key(syms, &b.root, Some(symbol)),
                    syms.str(symbol.name),
                    m.file,
                    at,
                    true,
                    false,
                    OccInfo {
                        ty: symbol.ty_opt(),
                        symbol: Some(symbol.clone()),
                        ..OccInfo::default()
                    },
                );
            }
        }
        for d in &m.decls {
            let symbol = symbols.get(&d.name());
            let Some(symbol) = symbol else { continue };
            if d.0.decl.synthetic && matches!(d.decl().kind, DeclKind::Interface(_))
                || !symbol.decl.as_ref().is_some_and(|sd| sd.same(d))
            {
                continue;
            }
            let Some(ty) = symbol.ty_opt() else { continue };
            let Some(def) = ty.def.clone() else { continue };
            let skey = symbol_key(syms, &b.root, Some(symbol));
            let typed_fields = fields(&ty);
            for field in d.type_fields() {
                for typed in &typed_fields {
                    if typed.name == field.name {
                        b.add(
                            format!("field:{skey}:{}", syms.str(field.name)),
                            syms.str(field.name),
                            m.file,
                            field.pos.offset as usize,
                            true,
                            false,
                            OccInfo {
                                ty: Some(typed.ty.clone()),
                                ..OccInfo::default()
                            },
                        );
                    }
                }
            }
            for case in d.cases() {
                b.add(
                    format!("case:{skey}:{}", syms.str(case.name)),
                    syms.str(case.name),
                    m.file,
                    case.pos.offset as usize,
                    true,
                    false,
                    OccInfo {
                        ty: Some(ty.clone()),
                        constructor: Some(ty.clone()),
                        case: Some(case.name),
                        ..OccInfo::default()
                    },
                );
            }
            let contract = ty.kind == Kind::Contract;
            if contract || syms.str(m.file).starts_with("@std/") {
                let operations = def.operations.borrow().clone();
                for (index, method) in d.methods().iter().enumerate() {
                    for op in &operations {
                        if method.func.name != op.name {
                            continue;
                        }
                        let checked = Method {
                            id: syms.intern(""),
                            module: m.file,
                            local: false,
                            receiver: ty.clone(),
                            contract: contract.then(|| ty.clone()),
                            ty: op.ty.clone(),
                            variables: Vec::new(),
                            decl: Some(FuncRef {
                                decl: d.clone(),
                                index: Some(index),
                            }),
                            native: if contract {
                                ms_check::api::types::Native::Contract
                            } else {
                                ms_check::api::types::Native::Source
                            },
                        };
                        let at = b.header(
                            m.file,
                            method.pos.offset as usize,
                            syms.str(method.func.name),
                        );
                        let key = method_key(syms, &b.root, &b.files, &checked);
                        b.add(
                            key,
                            syms.str(method.func.name),
                            m.file,
                            at,
                            true,
                            false,
                            OccInfo {
                                ty: Some(op.ty.clone()),
                                method: Some(Rc::new(checked)),
                                ..OccInfo::default()
                            },
                        );
                    }
                }
            }
        }
        for imp in &m.imports {
            let imported = if syms.str(m.file).starts_with("@std/") {
                analysis.session.standard_exports(&imp.path)
            } else {
                symbols.clone()
            };
            if let Some(symbol) = imported.get(&imp.name) {
                b.add(
                    symbol_key(syms, &b.root, Some(symbol)),
                    syms.str(imp.name),
                    m.file,
                    imp.name_pos.offset as usize,
                    false,
                    false,
                    OccInfo {
                        ty: symbol.ty_opt(),
                        symbol: Some(symbol.clone()),
                        ..OccInfo::default()
                    },
                );
            }
        }
    }

    // Bindings: patterns, parameters, lambda parameters, loops and arms.
    for m in modules.iter().filter(|m| checked.contains(&m.file)) {
        let mut walker = BindingWalker {
            syms,
            b: &mut b,
            module: m,
        };
        for d in &m.decls {
            for func in callables(d) {
                walker.parameters(syms, &func);
            }
            visit::walk_decl(&mut walker, d.decl());
        }
    }

    for method in &program.methods {
        let Some(decl) = &method.decl else { continue };
        let Some(file) = b.files.of_decl(&decl.decl) else {
            continue;
        };
        let at = b.header(file, decl.pos().offset as usize, syms.str(decl.name()));
        let key = method_key(syms, &b.root, &b.files, method);
        b.add(
            key,
            syms.str(decl.name()),
            file,
            at,
            true,
            false,
            OccInfo {
                ty: Some(method.ty.clone()),
                method: Some(method.clone()),
                ..OccInfo::default()
            },
        );
    }

    // Written type references (bundled signatures are always resolved).
    for m in &modules {
        let facts = m.facts();
        for site in type_references(m) {
            let Some(resolved) = facts.type_refs.get(&site.id) else {
                continue;
            };
            let (Some(symbol), Some(name)) = (resolved.symbol(), site.name) else {
                continue;
            };
            b.add(
                symbol_key(syms, &b.root, Some(&symbol)),
                syms.str(name),
                m.file,
                site.pos.offset as usize,
                false,
                false,
                OccInfo {
                    ty: Some(resolved.clone()),
                    symbol: Some(symbol.clone()),
                    ..OccInfo::default()
                },
            );
        }
    }

    for m in modules.iter().filter(|m| checked.contains(&m.file)) {
        let mut walker = UseWalker {
            syms,
            b: &mut b,
            module: m,
            hidden: HashMap::new(),
        };
        for d in &m.decls {
            visit::walk_decl(&mut walker, d.decl());
        }
    }

    let mut out = b.out;
    out.sort_by(|x, y| {
        syms.str(x.file)
            .cmp(syms.str(y.file))
            .then(x.offset.cmp(&y.offset))
            .then_with(|| x.key.cmp(&y.key))
    });
    out
}

/// The symbols a module declares or sees.
fn module_symbols(
    syms: ms_syntax::Names,
    analysis: &Analysis,
    m: &ModRef,
) -> HashMap<Name, SymRef> {
    if syms.str(m.file).starts_with("@std/") {
        return analysis.session.standard_exports(syms.str(m.file));
    }
    analysis
        .program
        .as_ref()
        .and_then(|p| p.symbols.get(&m.file))
        .map(|names| names.borrow().clone())
        .unwrap_or_default()
}

/// Function-like parts of a declaration: itself and its methods.
pub(crate) fn callables(d: &DeclRef) -> impl Iterator<Item = FuncRef> + '_ {
    std::iter::once(FuncRef::of_decl(d.clone())).chain((0..d.methods().len()).map(|index| {
        FuncRef {
            decl: d.clone(),
            index: Some(index),
        }
    }))
}

struct BindingWalker<'a> {
    syms: ms_syntax::Names,
    b: &'a mut Builder,
    module: &'a ModRef,
}

impl BindingWalker<'_> {
    fn parameters(&mut self, syms: ms_syntax::Names, func: &FuncRef) {
        let params: &[Param] = match func.func() {
            Some(f) => &f.params,
            None => &[],
        };
        let bindings = self
            .module
            .facts()
            .decls
            .get(&func.id())
            .map(|f| f.parameters.clone())
            .unwrap_or_default();
        for (i, binding) in bindings.iter().enumerate() {
            if let Some(param) = params.get(i) {
                let key = self.b.local_key(syms, binding);
                self.b.add(
                    key,
                    syms.str(binding.name),
                    self.module.file,
                    param.pos.offset as usize,
                    true,
                    false,
                    OccInfo {
                        ty: Some(binding.ty.clone()),
                        binding: Some(binding.clone()),
                        ..OccInfo::default()
                    },
                );
            }
        }
    }

    fn declare(&mut self, syms: ms_syntax::Names, binding: &BindingRef, offset: usize) {
        let key = self.b.local_key(syms, binding);
        self.b.add(
            key,
            syms.str(binding.name),
            self.module.file,
            offset,
            true,
            false,
            OccInfo {
                ty: Some(binding.ty.clone()),
                binding: Some(binding.clone()),
                ..OccInfo::default()
            },
        );
    }

    fn pattern(&mut self, syms: ms_syntax::Names, p: &Pattern) {
        let found = self.module.facts().patterns.get(&p.id).cloned();
        if let Some(binding) = found {
            self.declare(syms, &binding, p.pos.offset as usize);
        }
        match &p.kind {
            PatternKind::Name(_) => {}
            PatternKind::List(items) => items.iter().for_each(|x| self.pattern(syms, x)),
            PatternKind::Type(fields) => fields.iter().for_each(|f| self.pattern(syms, &f.pattern)),
        }
    }
}

impl Visitor for BindingWalker<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let syms = self.syms;
        let loop_binding = self
            .module
            .facts()
            .stmts
            .get(&s.id)
            .and_then(|f| f.loop_binding.clone());
        match &s.kind {
            StmtKind::Bind { pattern, .. } => self.pattern(syms, pattern),
            StmtKind::If {
                binding: Some(pattern),
                ..
            } => self.pattern(syms, pattern),
            StmtKind::For { .. } => {
                let expanded = self.module.facts().stmts.get(&s.id).and_then(|f| {
                    let StmtKind::While { body, .. } = &f.expansion.as_ref()?.last()?.kind else {
                        return None;
                    };
                    let StmtKind::If {
                        binding: Some(pattern),
                        ..
                    } = &body.first()?.kind
                    else {
                        return None;
                    };
                    self.module.facts().patterns.get(&pattern.id).cloned()
                });
                if let Some(binding) = loop_binding.or(expanded) {
                    let at = self.b.header(
                        self.module.file,
                        s.pos.offset as usize,
                        syms.str(binding.name),
                    );
                    self.declare(syms, &binding, at);
                }
            }
            _ => {}
        }
    }

    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        match &e.kind {
            ExprKind::Lambda(l) => {
                let bindings = self
                    .module
                    .facts()
                    .lambda_params
                    .get(&e.id)
                    .cloned()
                    .unwrap_or_default();
                for (i, binding) in bindings.iter().enumerate() {
                    if let Some(param) = l.params.get(i) {
                        self.declare(syms, binding, param.pos.offset as usize);
                    }
                }
            }
            ExprKind::Match { arms, .. } => {
                for arm in arms {
                    let bindings = self
                        .module
                        .facts()
                        .arms
                        .get(&arm.id)
                        .map(|a| a.bindings.clone())
                        .unwrap_or_default();
                    for binding in bindings.iter().flatten() {
                        let at = self.b.header(
                            self.module.file,
                            arm.pos.offset as usize,
                            syms.str(binding.name),
                        );
                        self.declare(syms, binding, at);
                    }
                }
            }
            _ => {}
        }
    }
}

/// Uses: names, members, constructors, labels and assignments.
struct UseWalker<'a> {
    syms: ms_syntax::Names,
    b: &'a mut Builder,
    module: &'a ModRef,
    hidden: HashMap<NodeId, bool>,
}

fn peel_apply(mut e: &Expr) -> &Expr {
    while let ExprKind::Apply { left, .. } = &e.kind {
        e = left;
    }
    e
}

impl UseWalker<'_> {
    fn info_of(&self, e: &Expr) -> Option<Info> {
        self.module.facts().info(e.id).cloned()
    }

    fn add(&mut self, key: String, name: &str, offset: usize, write: bool, info: OccInfo) {
        let file = self.module.file;
        self.b.add(key, name, file, offset, false, write, info);
    }

    /// Match paths bypass expression inference. Resolve their case identity
    /// from the checked scrutinee, rather than treating a bare arm as a name
    /// lookup (different alternatives may declare the same case spelling).
    fn match_case(&mut self, syms: ms_syntax::Names, scrutinee: &Expr, path: &Expr) {
        let Some(ty) = self.info_of(scrutinee).and_then(|info| info.ty) else {
            return;
        };
        if ty.kind != Kind::Alternative {
            return;
        }
        let Some(parent) = ty.symbol() else { return };
        let name = match &path.kind {
            ExprKind::Name(name) => *name,
            ExprKind::Member { left, name } => {
                let qualifier = self.info_of(peel_apply(left)).and_then(|info| info.symbol);
                if qualifier
                    .as_ref()
                    .is_none_or(|symbol| symbol.id != parent.id)
                {
                    return;
                }
                *name
            }
            _ => return,
        };
        let Some(def) = &ty.def else { return };
        if !def.cases.borrow().iter().any(|case| case.name == name) {
            return;
        }
        self.add(
            format!(
                "case:{}:{}",
                symbol_key(syms, &self.b.root, Some(&parent)),
                syms.str(name)
            ),
            syms.str(name),
            path.pos.offset as usize,
            false,
            OccInfo {
                ty: Some(ty.clone()),
                constructor: Some(ty),
                case: Some(name),
                ..OccInfo::default()
            },
        );
    }

    fn expression(&mut self, syms: ms_syntax::Names, e: &Expr) {
        let Some(info) = self.info_of(e) else { return };
        if hidden_structure(self.module, e, &info, &mut self.hidden) {
            return;
        }
        let occ = OccInfo::of(&info);
        match &e.kind {
            ExprKind::Name(name) => {
                let key = if let Some(binding) = &info.binding {
                    Some(self.b.local_key(syms, binding))
                } else {
                    info.symbol
                        .as_ref()
                        .map(|s| symbol_key(syms, &self.b.root, Some(s)))
                };
                if let Some(key) = key {
                    self.add(
                        key,
                        syms.str(name),
                        e.pos.offset as usize,
                        info.write,
                        occ.clone(),
                    );
                }
            }
            ExprKind::Member { left, name } => {
                if info.method.is_none() {
                    let receiver = self.info_of(left).and_then(|i| i.ty);
                    if let Some(receiver) = receiver
                        && receiver.kind == Kind::Type
                        && let Some(def) = &receiver.def
                    {
                        let parent = def.symbol();
                        self.add(
                            format!(
                                "field:{}:{}",
                                symbol_key(syms, &self.b.root, parent.as_ref()),
                                syms.str(name)
                            ),
                            syms.str(name),
                            e.pos.offset as usize,
                            info.write,
                            occ.clone(),
                        );
                    }
                }
                if let Some(method) = &info.method {
                    let key = method_key(syms, &self.b.root, &self.b.files, method);
                    self.add(
                        key,
                        syms.str(name),
                        e.pos.offset as usize,
                        info.write,
                        occ.clone(),
                    );
                }
            }
            _ => {}
        }
        if let (Some(constructor), Some(case)) = (&info.constructor, info.case)
            && let Some(parent) = constructor.symbol()
        {
            let left = match &e.kind {
                ExprKind::Call { callee, .. } => callee,
                _ => e,
            };
            self.add(
                format!(
                    "case:{}:{}",
                    symbol_key(syms, &self.b.root, Some(&parent)),
                    syms.str(case)
                ),
                syms.str(case),
                left.pos.offset as usize,
                false,
                occ.clone(),
            );
            if let ExprKind::Member { left: receiver, .. } = &left.kind {
                let root = peel_apply(receiver);
                if let ExprKind::Name(root_name) = &root.kind {
                    self.add(
                        symbol_key(syms, &self.b.root, Some(&parent)),
                        syms.str(root_name),
                        root.pos.offset as usize,
                        false,
                        OccInfo {
                            ty: Some(constructor.clone()),
                            symbol: Some(parent.clone()),
                            ..OccInfo::default()
                        },
                    );
                }
            }
        }
        if let ExprKind::Call { callee, args } = &e.kind {
            if let Some(constructor) = &info.constructor
                && constructor.kind == Kind::Type
                && let Some(def) = &constructor.def
            {
                let parent = def.symbol();
                let typed_fields = fields(constructor);
                for arg in args {
                    let Some(label) = arg.name else { continue };
                    for field in &typed_fields {
                        if field.name == label {
                            self.add(
                                format!(
                                    "field:{}:{}",
                                    symbol_key(syms, &self.b.root, parent.as_ref()),
                                    syms.str(field.name)
                                ),
                                syms.str(field.name),
                                arg.pos.offset as usize,
                                false,
                                OccInfo {
                                    ty: Some(field.ty.clone()),
                                    ..OccInfo::default()
                                },
                            );
                        }
                    }
                }
            }
            if let Some(constructor) = &info.constructor
                && let Some(def) = &constructor.def
            {
                let left = peel_apply(callee);
                if let ExprKind::Name(left_name) = &left.kind {
                    let symbol = def.symbol();
                    self.add(
                        symbol_key(syms, &self.b.root, symbol.as_ref()),
                        syms.str(left_name),
                        left.pos.offset as usize,
                        false,
                        OccInfo {
                            ty: Some(constructor.clone()),
                            symbol,
                            ..OccInfo::default()
                        },
                    );
                }
            }
            self.labels(syms, callee, args);
        }
    }

    /// Argument labels resolve to the callee's parameter bindings.
    fn labels(&mut self, syms: ms_syntax::Names, callee: &Expr, args: &[Argument]) {
        let Some(called) = self.info_of(callee) else {
            return;
        };
        let mut target: Option<FuncRef> = called
            .symbol
            .as_ref()
            .and_then(|s| s.decl.clone())
            .map(FuncRef::of_decl);
        if let Some(method) = &called.method {
            target = method.decl.clone();
        }
        let Some(target) = target else { return };
        let Some(func) = target.func() else { return };
        let Some(file) = self.b.files.of_decl(&target.decl) else {
            return;
        };
        let Some(owner) = self.b.by_file.get(&file).cloned() else {
            return;
        };
        let bindings = owner
            .facts()
            .decls
            .get(&target.id())
            .map(|f| f.parameters.clone())
            .unwrap_or_default();
        for arg in args {
            let Some(label) = arg.name else { continue };
            for (i, param) in func.params.iter().enumerate() {
                if param.name == label && i < bindings.len() {
                    let binding = bindings[i].clone();
                    let key = self.b.local_key(syms, &binding);
                    self.add(
                        key,
                        syms.str(binding.name),
                        arg.pos.offset as usize,
                        false,
                        OccInfo {
                            ty: Some(binding.ty.clone()),
                            binding: Some(binding),
                            ..OccInfo::default()
                        },
                    );
                }
            }
        }
    }
}

impl Visitor for UseWalker<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let syms = self.syms;
        if let StmtKind::Assign {
            target: AssignTarget::Name(name),
            value,
            ..
        } = &s.kind
        {
            let assigned = self.module.facts().assigned.get(&value.id).cloned();
            if let Some(binding) = assigned {
                let key = self.b.local_key(syms, &binding);
                self.add(
                    key,
                    syms.str(name),
                    s.pos.offset as usize,
                    true,
                    OccInfo {
                        ty: Some(binding.ty.clone()),
                        binding: Some(binding),
                        ..OccInfo::default()
                    },
                );
            }
        }
    }

    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        self.expression(syms, e);
        if let ExprKind::Match { scrutinee, arms } = &e.kind {
            for arm in arms {
                let optional_binding = arm.bare
                    && self
                        .info_of(scrutinee)
                        .and_then(|info| info.ty)
                        .is_some_and(|ty| ty.is(ms_check::api::types::Builtin::Optional));
                if !optional_binding && !arm.chain && !arm.from_if {
                    self.match_case(syms, scrutinee, &arm.path);
                }
                visit_arm_path(syms, self, &arm.path);
            }
        }
    }
}

fn visit_arm_path(syms: ms_syntax::Names, w: &mut UseWalker<'_>, path: &Expr) {
    w.expression(syms, path);
    match &path.kind {
        ExprKind::Member { left, .. } | ExprKind::Apply { left, .. } => {
            visit_arm_path(syms, w, left)
        }
        _ => {}
    }
}

/// One written type reference.
pub struct TypeSite {
    /// Node id.
    pub id: NodeId,
    /// Position of the written name.
    pub pos: ms_syntax::Pos,
    /// The written name; `None` for a function type.
    pub name: Option<Symbol>,
}

fn collect_type(t: &TypeRef, out: &mut Vec<TypeSite>) {
    out.push(TypeSite {
        id: t.id,
        pos: t.pos,
        name: match &t.kind {
            TypeKind::Named { name, .. } => Some(*name),
            TypeKind::Fn { .. } => None,
        },
    });
    match &t.kind {
        TypeKind::Named { args, .. } => args.iter().for_each(|a| collect_type(a, out)),
        TypeKind::Fn { params, result } => {
            params
                .iter()
                .filter_map(|p| p.ty.as_ref())
                .for_each(|t| collect_type(t, out));
            collect_type(result, out);
        }
    }
}

fn collect_params(ps: &[Param], out: &mut Vec<TypeSite>) {
    for p in ps {
        if let Some(t) = &p.ty {
            collect_type(t, out);
        }
    }
}

fn collect_type_params(ps: &[TypeParam], out: &mut Vec<TypeSite>) {
    for p in ps {
        p.bounds.iter().for_each(|t| collect_type(t, out));
        if let Some(t) = &p.default {
            collect_type(t, out);
        }
    }
}

fn collect_func(f: &Func, out: &mut Vec<TypeSite>) {
    collect_type_params(&f.type_params, out);
    collect_params(&f.params, out);
    collect_type(&f.result, out);
}

/// Annotations and type applications inside executable code.
struct BodyTypes<'a> {
    out: &'a mut Vec<TypeSite>,
}

impl Visitor for BodyTypes<'_> {
    fn stmt(&mut self, s: &Stmt) {
        if let StmtKind::Bind { ty: Some(t), .. } = &s.kind {
            collect_type(t, self.out);
        }
    }

    fn expr(&mut self, e: &Expr) {
        match &e.kind {
            ExprKind::Apply { types, .. } => types.iter().for_each(|t| collect_type(t, self.out)),
            ExprKind::Lambda(l) => {
                collect_params(&l.params, self.out);
                if let Some(t) = &l.result {
                    collect_type(t, self.out);
                }
            }
            ExprKind::Match { arms, .. } => {
                for arm in arms {
                    path_types(&arm.path, self.out);
                }
            }
            _ => {}
        }
    }
}

fn path_types(path: &Expr, out: &mut Vec<TypeSite>) {
    match &path.kind {
        ExprKind::Apply { left, types, .. } => {
            types.iter().for_each(|t| collect_type(t, out));
            path_types(left, out);
        }
        ExprKind::Member { left, .. } => path_types(left, out),
        _ => {}
    }
}

/// Every written type reference of a module: signatures, annotations and
/// type applications.
pub fn type_references(m: &ModRef) -> Vec<TypeSite> {
    let mut out = Vec::new();
    for d in &m.decls {
        match &d.decl().kind {
            DeclKind::Fn(f) => collect_func(f, &mut out),
            DeclKind::Const(c) => {
                if let Some(t) = &c.ty {
                    collect_type(t, &mut out);
                }
            }
            DeclKind::Type(r) => {
                collect_type_params(&r.type_params, &mut out);
                collect_params(&r.fields, &mut out);
            }
            DeclKind::Alternative(a) => {
                collect_type_params(&a.type_params, &mut out);
                a.cases
                    .iter()
                    .for_each(|c| collect_params(&c.fields, &mut out));
            }
            DeclKind::Alias(a) => {
                collect_type_params(&a.type_params, &mut out);
                a.targets.iter().for_each(|t| collect_type(t, &mut out));
            }
            DeclKind::Interface(i) => {
                collect_type_params(&i.type_params, &mut out);
                i.methods
                    .iter()
                    .for_each(|m| collect_func(&m.func, &mut out));
            }
            DeclKind::Impl(i) => {
                if let Some(c) = &i.contract {
                    collect_type(c, &mut out);
                }
                collect_type(&i.receiver, &mut out);
                i.methods
                    .iter()
                    .for_each(|m| collect_func(&m.func, &mut out));
            }
            DeclKind::Test(_) => {}
        }
        d.0.folded
            .iter()
            .for_each(|m| collect_func(&m.func, &mut out));
        visit::walk_decl(&mut BodyTypes { out: &mut out }, d.decl());
    }
    out
}

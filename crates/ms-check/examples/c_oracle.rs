//! Prints the checker's standard-library tables in a canonical text form, so the C checker in
//! `compiler/` can be compared with it byte for byte (`make c-compiler-test`).
//! Temporary tooling for the C rewrite: delete it with the Rust checker.

use ms_check::Session;
use ms_check::api::types::{Native, SymKind};
use ms_syntax::Names;
use std::fmt::Write;

/// The diagnostic families the C checker implements so far; the scope mode prints only these.
const SCOPE_FAMILIES: [&str; 5] = [
    "reuses a prelude",
    "collides with another",
    "duplicate or intrinsic name ",
    "module does not export ",
    "unknown standard module ",
];

/// Diagnostics about declared types. Only those at a declaration-level position are compared:
/// the bodies of functions and implementations are checked by later passes.
const TYPE_FAMILIES: [&str; 12] = [
    "duplicate or intrinsic type parameter ",
    "needs a default because an earlier parameter has one",
    "a bound must be an interface",
    "unknown type ",
    "type arguments, found ",
    "refers to itself",
    "a type set holds concrete types",
    "is a type set, which constrains",
    "duplicate parameter or field ",
    "duplicate case ",
    "alias ",
    "requires ",
];

use ms_check::api::ast::{
    Decl, DeclKind, Expr, ExprKind, NodeId, Param, Stmt, StmtKind, TextPart, TypeKind, TypeParam,
    TypeRef,
};
use std::collections::BTreeSet;

/// The positions and node ids of the written types of the declarations the C checker resolves.
#[derive(Default)]
struct Declared {
    positions: BTreeSet<(u32, u32)>,
    refs: BTreeSet<u32>,
}

impl Declared {
    fn at(&mut self, pos: ms_syntax::Pos) {
        self.positions.insert((pos.line, pos.column));
    }

    fn type_ref(&mut self, t: &TypeRef) {
        self.at(t.pos);
        self.refs.insert(t.id.index() as u32);
        match &t.kind {
            TypeKind::Named { args, .. } => args.iter().for_each(|a| self.type_ref(a)),
            TypeKind::Fn { params, result } => {
                self.params(params);
                self.type_ref(result);
            }
        }
    }

    fn params(&mut self, params: &[Param]) {
        for p in params {
            self.at(p.pos);
            if let Some(t) = &p.ty {
                self.type_ref(t);
            }
        }
    }

    /// Bounds and defaults are resolved again for the operations of a desugared `impl`, with the
    /// same node ids, so their `type_refs` entries are not the declaration pass's. Their
    /// positions still count.
    fn type_params(&mut self, params: &[TypeParam]) {
        for p in params {
            self.at(p.pos);
            let kept = std::mem::take(&mut self.refs);
            p.bounds.iter().for_each(|b| self.type_ref(b));
            if let Some(d) = &p.default {
                self.type_ref(d);
            }
            self.refs = kept;
        }
    }

    fn decl(&mut self, d: &Decl) {
        self.at(d.pos);
        match &d.kind {
            DeclKind::Fn(f) => {
                self.type_params(&f.type_params);
                self.params(&f.params);
                self.type_ref(&f.result);
            }
            DeclKind::Type(t) => {
                self.type_params(&t.type_params);
                self.params(&t.fields);
            }
            DeclKind::Alternative(e) => {
                self.type_params(&e.type_params);
                for c in &e.cases {
                    self.at(c.pos);
                    self.params(&c.fields);
                }
            }
            DeclKind::Alias(a) => {
                self.type_params(&a.type_params);
                a.targets.iter().for_each(|t| self.type_ref(t));
            }
            DeclKind::Interface(i) => self.type_params(&i.type_params),
            DeclKind::Const(_) | DeclKind::Impl(_) | DeclKind::Test(_) => {}
        }
    }
}

fn show(syms: Names, t: &ms_check::api::types::Ty) -> String {
    t.display(syms).to_string()
}

fn show_param(syms: Names, p: &ms_check::api::types::Param) -> String {
    format!(
        "{}: {}{}{}",
        syms.str(p.name),
        if p.mutable { "var " } else { "" },
        if p.moving { "move " } else { "" },
        show(syms, &p.ty)
    )
}

/// The declared types of the module in the form `ms_dump_module_types` prints.
fn module_types(
    syms: Names,
    program: &ms_check::Program,
    module: &ms_check::ModRef,
    declared: &Declared,
) -> String {
    let mut out = String::new();
    let Some(names) = program.symbols.get(&module.file) else {
        return "unchecked\n".to_string();
    };
    for d in &module.decls {
        let name = d.name();
        let text = syms.str(name);
        if matches!(
            d.decl().kind,
            DeclKind::Impl(_) | DeclKind::Test(_) | DeclKind::Const(_)
        ) || text.contains('$')
        {
            continue;
        }
        let Some(s) = names
            .borrow()
            .get(&name)
            .filter(|s| s.decl.as_ref().is_some_and(|sd| sd.same(d)))
            .cloned()
        else {
            continue;
        };
        let ty = s.ty.borrow().clone();
        let shown = ty.as_ref().map_or("-".to_string(), |t| show(syms, t));
        let _ = writeln!(out, "sym {text}: {shown}");
        for v in s.variables() {
            let default = v.default_ty().map_or("-".to_string(), |t| show(syms, &t));
            let bounds: Vec<String> = v.bounds().iter().map(|b| show(syms, b)).collect();
            let _ = writeln!(
                out,
                "  var {} default={default} bounds={}",
                syms.str(v.name),
                bounds.join(",")
            );
        }
        let def = ty.as_ref().and_then(|t| t.def.clone());
        // An alias's type is its target, whose fields and cases are not the alias's.
        if let (Some(def), SymKind::Type) = (def, s.kind) {
            for f in def.fields.borrow().iter() {
                let _ = writeln!(out, "  field {}", show_param(syms, f));
            }
            for c in def.cases.borrow().iter() {
                let fields: Vec<String> = c.fields.iter().map(|f| show_param(syms, f)).collect();
                let _ = writeln!(out, "  case {}({})", syms.str(c.name), fields.join(", "));
            }
        }
    }
    let facts = module.facts();
    let mut refs: Vec<_> = facts
        .type_refs
        .iter()
        .filter(|(id, _)| declared.refs.contains(&(id.index() as u32)))
        .collect();
    refs.sort_by_key(|(id, _)| id.index());
    for (id, t) in refs {
        let _ = writeln!(out, "typeref {} {}", id.index(), show(syms, t));
    }
    out
}

/// `c_oracle --scope FILE...`: the name-resolution diagnostics of each file, one per line.
fn scope_diagnostics(files: &[String]) {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in files {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: std::sync::Arc<str> = "main.ms".into();
        let Ok(module) = ms_syntax::parser::parse(&file, &source) else {
            continue;
        };
        if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
            continue;
        }
        println!("== {path}");
        let mut declared = Declared::default();
        module.decls.iter().for_each(|d| declared.decl(d));
        let loaded = ms_check::load_module(syms, &module);
        let program = ms_check::check_in(
            syms,
            &session,
            vec![loaded.clone()],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        for d in &program.diagnostics {
            let scope = SCOPE_FAMILIES.iter().any(|f| d.message.contains(f));
            let typed = TYPE_FAMILIES.iter().any(|f| d.message.contains(f))
                && declared.positions.contains(&(d.pos.line, d.pos.column));
            if scope && d.phase == ms_syntax::Phase::Resolution
                || typed
                    && matches!(
                        d.phase,
                        ms_syntax::Phase::Resolution | ms_syntax::Phase::Type
                    )
            {
                println!("{}:{}: {}", d.pos.line, d.pos.column, d.message);
            }
        }
        println!("--");
        print!("{}", module_types(syms, &program, &loaded, &declared));
    }
}

/// The ids of the expressions of the shapes the C body checker supports, in tree order.
fn body_exprs(e: &Expr, out: &mut Vec<NodeId>) {
    out.push(e.id);
    match &e.kind {
        ExprKind::Text(parts) => parts.iter().for_each(|p| {
            if let TextPart::Interp(x) = p {
                body_exprs(x, out);
            }
        }),
        ExprKind::Unary { operand, .. } => body_exprs(operand, out),
        ExprKind::Member { left, .. } => body_exprs(left, out),
        ExprKind::Binary { left, right, .. } => {
            body_exprs(left, out);
            body_exprs(right, out);
        }
        ExprKind::Call { args, .. } => args.iter().for_each(|a| body_exprs(&a.value, out)),
        ExprKind::Match { scrutinee, arms } => {
            body_exprs(scrutinee, out);
            for arm in arms {
                out.push(arm.path.id); // a pattern: its parts are not expressions
                if let Some(value) = &arm.value {
                    body_exprs(value, out);
                }
            }
        }
        _ => {}
    }
}

fn body_stmts(body: &[Stmt], out: &mut Vec<NodeId>) {
    for s in body {
        match &s.kind {
            StmtKind::Bind { value, .. } => body_exprs(value, out),
            StmtKind::Assign { value, .. } => body_exprs(value, out),
            StmtKind::Return(Some(v)) | StmtKind::Call(v) => body_exprs(v, out),
            StmtKind::If {
                cond,
                body,
                else_body,
                ..
            } => {
                body_exprs(cond, out);
                body_stmts(body, out);
                body_stmts(else_body, out);
            }
            StmtKind::While { cond, body } => {
                body_exprs(cond, out);
                body_stmts(body, out);
            }
            StmtKind::For { iter, body, .. } => {
                // The C checker leaves the range call untyped; its bounds are compared.
                if let ExprKind::Call { args, .. } = &iter.kind {
                    args.iter().for_each(|a| body_exprs(&a.value, out));
                }
                body_stmts(body, out);
            }
            _ => {}
        }
    }
}

/// `c_oracle --bodies FILE...`: per top-level function, whether the checker reported anything
/// inside it and the type of each expression of its body.
/// Each method an impl of `module` writes, with the lines it owns: from its name to the next
/// method of the impl, or to the next declaration.
fn module_methods(module: &ms_syntax::ast::Module) -> Vec<(&ms_syntax::ast::Method, u32, u32)> {
    let mut out = Vec::new();
    for (i, d) in module.decls.iter().enumerate() {
        let DeclKind::Impl(im) = &d.kind else {
            continue;
        };
        for (k, m) in im.methods.iter().enumerate() {
            let end = im.methods.get(k + 1).map_or_else(
                || module.decls.get(i + 1).map_or(u32::MAX, |n| n.pos.line),
                |n| n.pos.line,
            );
            out.push((m, m.pos.line, end));
        }
    }
    out
}

fn body_facts(files: &[String]) {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in files {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: std::sync::Arc<str> = "main.ms".into();
        let Ok(module) = ms_syntax::parser::parse(&file, &source) else {
            continue;
        };
        if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
            continue;
        }
        println!("== {path}");
        let loaded = ms_check::load_module(syms, &module);
        let program = ms_check::check_in(
            syms,
            &session,
            vec![loaded.clone()],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        if !program.symbols.contains_key(&loaded.file) {
            println!("unchecked");
            continue;
        }
        print_body_facts(syms, &module, &program, &loaded);
    }
}

/// The functions of `module` with the diagnostics inside each and the type of each expression.
fn print_body_facts(
    syms: Names,
    module: &ms_syntax::ast::Module,
    program: &ms_check::Program,
    loaded: &ms_check::ModRef,
) {
    let facts = loaded.facts();
    for (i, d) in module.decls.iter().enumerate() {
        let (word, mut ids) = match &d.kind {
            DeclKind::Fn(f) if !f.external => {
                let mut ids = Vec::new();
                body_stmts(&f.body, &mut ids);
                ("fn", ids)
            }
            DeclKind::Const(k) => {
                let mut ids = Vec::new();
                body_exprs(&k.value, &mut ids);
                ("const", ids)
            }
            _ => continue,
        };
        let end = module.decls.get(i + 1).map_or(u32::MAX, |n| n.pos.line);
        println!("{word} {}:{}", d.pos.line, d.pos.column);
        for x in &program.diagnostics {
            if x.pos.line >= d.pos.line && x.pos.line < end {
                println!("diag {}:{}: {}", x.pos.line, x.pos.column, x.message);
            }
        }
        for id in ids.drain(..) {
            let ty = facts
                .info(id)
                .and_then(|i| i.ty.as_ref())
                .map_or("-".to_string(), |t| show(syms, t));
            println!("expr {} {ty}", id.index());
        }
    }
    for (m, first, end) in module_methods(module) {
        if m.func.external {
            continue;
        }
        let mut ids = Vec::new();
        body_stmts(&m.func.body, &mut ids);
        println!("fn {}:{}", m.pos.line, m.pos.column);
        for x in &program.diagnostics {
            if x.pos.line >= first && x.pos.line < end {
                println!("diag {}:{}: {}", x.pos.line, x.pos.column, x.message);
            }
        }
        for id in ids.drain(..) {
            let ty = facts
                .info(id)
                .and_then(|i| i.ty.as_ref())
                .map_or("-".to_string(), |t| show(syms, t));
            println!("expr {} {ty}", id.index());
        }
    }
}

/// The modules a file imports, depth first (imports before the importer), each with the parsed
/// syntax. Local imports resolve relative to the importing file, as the C project loader does for
/// a standalone file.
fn load_project(
    path: &std::path::Path,
    seen: &mut Vec<(std::path::PathBuf, ms_check::ModRef, ms_syntax::ast::Module)>,
    imports: &mut Vec<(ms_check::ModRef, ms_syntax::ast::NodeId, std::path::PathBuf)>,
    entry: bool,
) -> Option<ms_check::ModRef> {
    let syms = Names::global();
    let canonical = std::fs::canonicalize(path).ok()?;
    if let Some((_, loaded, _)) = seen.iter().find(|(p, _, _)| *p == canonical) {
        return Some(loaded.clone());
    }
    let source = std::fs::read_to_string(&canonical).ok()?;
    let name: std::sync::Arc<str> = if entry {
        "main.ms".into()
    } else {
        canonical.to_string_lossy().as_ref().into()
    };
    let module = ms_syntax::parser::parse(&name, &source).ok()?;
    let mut targets = Vec::new();
    for i in &module.imports {
        if i.path.starts_with("@std/") {
            continue;
        }
        let target = canonical.parent()?.join(&*i.path);
        let loaded = load_project(&target, seen, imports, false)?;
        targets.push((i.id, std::fs::canonicalize(target).ok()?, loaded));
    }
    let loaded = ms_check::load_module(syms, &module);
    for (id, target, _) in targets {
        imports.push((loaded.clone(), id, target));
    }
    seen.push((canonical, loaded.clone(), module));
    Some(loaded)
}

/// `c_oracle --project FILE...`: the bodies mode for files that import project modules, plus the
/// resolution diagnostics of the entry file (`import L:C: message`).
fn project_facts(files: &[String]) {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in files {
        let mut seen = Vec::new();
        let mut imports = Vec::new();
        let Some(loaded) = load_project(std::path::Path::new(path), &mut seen, &mut imports, true)
        else {
            continue;
        };
        if seen.len() < 2 {
            continue;
        }
        let mut map = ms_check::ImportMap::default();
        for (importer, id, target) in &imports {
            if let Some((_, t, _)) = seen.iter().find(|(p, _, _)| p == target) {
                map.insert(importer.file, *id, t.file);
            }
        }
        println!("== {path}");
        let modules: Vec<_> = seen.iter().map(|(_, m, _)| m.clone()).collect();
        let program = ms_check::check_in(
            syms,
            &session,
            modules,
            map,
            ms_check::CheckOptions::default(),
        );
        let module = &seen
            .iter()
            .find(|(_, m, _)| m.file == loaded.file)
            .expect("entry")
            .2;
        for d in &program.diagnostics {
            if &*d.file == "main.ms" && d.phase == ms_syntax::Phase::Resolution {
                println!("import {}:{}: {}", d.pos.line, d.pos.column, d.message);
            }
        }
        print_body_facts(syms, module, &program, &loaded);
    }
}

/// `c_oracle --ownership FILE...`: per top-level function, every diagnostic inside it, one per line.
fn ownership_diagnostics(files: &[String]) {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in files {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: std::sync::Arc<str> = "main.ms".into();
        let Ok(module) = ms_syntax::parser::parse(&file, &source) else {
            continue;
        };
        if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
            continue;
        }
        println!("== {path}");
        let loaded = ms_check::load_module(syms, &module);
        let program = ms_check::check_in(
            syms,
            &session,
            vec![loaded.clone()],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        for (i, d) in module.decls.iter().enumerate() {
            if !matches!(&d.kind, DeclKind::Fn(f) if !f.external) {
                continue;
            }
            let end = module.decls.get(i + 1).map_or(u32::MAX, |n| n.pos.line);
            println!("fn {}:{}", d.pos.line, d.pos.column);
            for x in &program.diagnostics {
                if x.pos.line >= d.pos.line && x.pos.line < end {
                    println!("diag {}:{}: {}", x.pos.line, x.pos.column, x.message);
                }
            }
        }
        for (m, first, end) in module_methods(&module) {
            if m.func.external {
                continue;
            }
            println!("fn {}:{}", m.pos.line, m.pos.column);
            for x in &program.diagnostics {
                if x.pos.line >= first && x.pos.line < end {
                    println!("diag {}:{}: {}", x.pos.line, x.pos.column, x.message);
                }
            }
        }
    }
}

/// `c_oracle --effects FILE...`: per top-level function and constant, the callables its body
/// references (first reference of each, in source order).
fn effect_edges(files: &[String]) {
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in files {
        let Ok(source) = std::fs::read_to_string(path) else {
            continue;
        };
        let file: std::sync::Arc<str> = "main.ms".into();
        let Ok(module) = ms_syntax::parser::parse(&file, &source) else {
            continue;
        };
        if module.imports.iter().any(|i| !i.path.starts_with("@std/")) {
            continue;
        }
        println!("== {path}");
        let loaded = ms_check::load_module(syms, &module);
        let program = ms_check::check_in(
            syms,
            &session,
            vec![loaded.clone()],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        // The effect scan runs only on a program the checker accepts.
        let Some(names) = program
            .symbols
            .get(&loaded.file)
            .filter(|_| program.diagnostics.is_empty())
        else {
            println!("unchecked");
            continue;
        };
        let by_id: std::collections::HashMap<_, _> = names
            .borrow()
            .iter()
            .map(|(name, symbol)| (symbol.id, syms.str(*name).to_string()))
            .collect();
        for d in &loaded.decls {
            let word = match &d.decl().kind {
                DeclKind::Fn(f) if !f.external => "fn",
                DeclKind::Const(_) => "const",
                _ => continue,
            };
            let Some(symbol) = names.borrow().get(&d.name()).cloned() else {
                continue;
            };
            println!("{word} {}:{}", d.decl().pos.line, d.decl().pos.column);
            for (callee, pos) in program.effect_edges_of(symbol.id) {
                let shown = by_id
                    .get(&callee)
                    .cloned()
                    .unwrap_or_else(|| syms.str(callee).to_string());
                println!("edge {shown} {}:{}", pos.line, pos.column);
            }
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|a| a == "--effects") {
        effect_edges(&args[1..]);
        return;
    }
    if args.first().is_some_and(|a| a == "--ownership") {
        ownership_diagnostics(&args[1..]);
        return;
    }
    if args.first().is_some_and(|a| a == "--project") {
        project_facts(&args[1..]);
        return;
    }
    if args.first().is_some_and(|a| a == "--bodies") {
        body_facts(&args[1..]);
        return;
    }
    if args.first().is_some_and(|a| a == "--scope") {
        scope_diagnostics(&args[1..]);
        return;
    }
    let syms = Names::global();
    let session = Session::new();
    session.ensure_standard();
    let mut out = String::new();
    // `extern type`s of bundled source modules, by the module that declares them.
    for module in session.standard_modules() {
        for d in &module.decls {
            if matches!(&d.decl().kind, ms_check::api::ast::DeclKind::Type(r) if r.external) {
                let s = session
                    .standard_symbol(syms.str(d.name()))
                    .expect("extern type");
                let _ = writeln!(
                    out,
                    "extern {} {} id={} export={} vars={}",
                    syms.str(module.file),
                    syms.str(d.name()),
                    syms.str(s.id),
                    s.export,
                    s.variables().len()
                );
            }
        }
    }
    for module in session.standard_modules() {
        let file = syms.str(module.file);
        if session.standard_source_module(module.file).is_some() {
            continue;
        }
        let _ = writeln!(out, "module {file}");
        let mut rows: Vec<_> = session.standard_exports(file).into_iter().collect();
        rows.sort_by_key(|(name, _)| syms.str(*name).to_string());
        for (name, s) in rows {
            if matches!(s.native, Native::Source) {
                // The `+source` twin's exports are checked symbols, numbered in checking order.
                continue;
            }
            let kind = match s.kind {
                SymKind::Type => "type",
                SymKind::Fn => "fn",
                SymKind::Alias => "alias",
            };
            let native = match s.native {
                Native::Source => "source".to_string(),
                Native::Contract => "contract".to_string(),
                Native::Extern { symbol, bundled } => {
                    format!("extern:{}:{bundled}", syms.str(symbol))
                }
                Native::Builtin(b) => format!("builtin:{}", syms.str(b)),
            };
            let _ = writeln!(
                out,
                "  {} {kind} export={} id={} native={native} vars={}",
                syms.str(name),
                s.export,
                syms.str(s.id),
                s.variables().len()
            );
        }
    }
    print!("{out}");
}

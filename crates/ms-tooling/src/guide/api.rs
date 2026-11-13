//! Detached documentation snapshots of importable modules
//! of the bundled standard library, or the
//! exports of a checked program.

use crate::guide::render;
use crate::guide::source::{Source, declared_effect_lines, leading_comment};
use ms_check::api::checker::Names;
use ms_check::api::stdlib;
use ms_check::api::syntax::{DeclRef, FuncRef};
use ms_check::api::types::{
    Definition, MethodRef, Name, SymKind, SymRef, Ty, n, same, sub, substitution,
};
use ms_check::{Program, Session};
use ms_syntax::{DeclKind, Func};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::rc::Rc;
use std::sync::{Arc, OnceLock};

/// A detached documentation snapshot of an importable module.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiModule {
    /// Import path (`@std/data/json.ms`, `prelude`, or a program file).
    pub path: String,
    /// Exported declarations sorted by name.
    pub declarations: Vec<ApiDeclaration>,
}

/// One exported declaration.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ApiDeclaration {
    /// A source-syntax excerpt for human documentation; absent from JSON.
    pub declaration: String,
    /// Declared name.
    pub name: String,
    /// Leading comment text.
    pub doc: String,
    /// Effects the function declares with `// ms: effect NAME` lines (`std.fs.read`).
    pub effects: Vec<String>,
    /// `fn`, `alternative`, `interface`, `native`, `constant`, `type`, `alias`.
    pub kind: String,
    /// Whether the representation is inaccessible outside its declaring module.
    pub opaque: bool,
    /// The checked type, spelled as the checker prints it.
    pub ty: String,
    /// Type parameters with bounds.
    pub parameters: Vec<String>,
    /// Record fields as `name: Type`.
    pub fields: Vec<String>,
    /// Alternative cases.
    pub cases: Vec<String>,
    /// Receiver and contract operations as `name: signature`.
    pub operations: Vec<String>,
    /// Documented members.
    pub members: Vec<ApiMember>,
    /// Contracts the type implements.
    pub implements: Vec<String>,
    /// `impl` excerpts; absent from JSON.
    pub implementation_declarations: Vec<String>,
}

/// A field, case or operation with its source description.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ApiMember {
    /// Member name (operations carry their type parameters).
    pub name: String,
    /// `field`, `case` or `operation`.
    pub kind: String,
    /// Source-syntax signature.
    pub signature: String,
    /// Leading comment text; empty when undocumented.
    pub doc: String,
    /// Implemented contract, for contract operations.
    pub contract: String,
    /// Previous compiler-only contract spelling, used only for invisible site anchors.
    pub legacy_contract: String,
}

/// These public entries have no `.ms` declaration to attach a source comment
/// to; their semantic descriptions live beside the checker's primitives.
fn primitive_documentation(id: &str) -> &'static str {
    match id {
        "Bool" => "Boolean truth values true and false; conditions require this type.",
        "Int" => {
            "Signed whole numbers with checked arithmetic; overflow and division by zero fault."
        }
        "Float" => "Binary floating-point values, including signed zero, infinities and NaN.",
        "Int8" => {
            "Signed 8-bit whole numbers (-128 to 127); arithmetic faults when the result leaves the range."
        }
        "Int16" => {
            "Signed 16-bit whole numbers (-32768 to 32767); arithmetic faults when the result leaves the range."
        }
        "Int32" => {
            "Signed 32-bit whole numbers (-2147483648 to 2147483647); arithmetic faults when the result leaves the range."
        }
        "Int64" => "Signed 64-bit whole numbers; the same type as Int while Int is 64 bits wide.",
        "UInt8" => {
            "Unsigned 8-bit whole numbers (0 to 255); arithmetic faults when the result leaves the range."
        }
        "UInt16" => {
            "Unsigned 16-bit whole numbers (0 to 65535); arithmetic faults when the result leaves the range."
        }
        "UInt32" => {
            "Unsigned 32-bit whole numbers (0 to 4294967295); arithmetic faults when the result leaves the range."
        }
        "UInt64" => {
            "Unsigned 64-bit whole numbers (0 to 18446744073709551615); arithmetic faults when the result leaves the range."
        }
        "Float32" => {
            "Binary32 floating-point values; each operation rounds to binary32, and literals need a Float32 type to adopt it."
        }
        "Float64" => "Binary64 floating-point values; the same type as Float.",
        "String" => {
            "UTF-8 text indexed by Unicode scalar values; byte_length counts encoded bytes instead."
        }
        "Unit" => "The single value unit, used when an operation returns no useful payload.",
        "Never" => "The return type of computations that cannot return a value, such as panic.",
        _ => "",
    }
}

/// Source text by module file.
struct Sources(HashMap<Name, Source>);

impl Sources {
    fn of(&self, module: Name) -> Option<&Source> {
        self.0.get(&module)
    }
}

/// The bundled standard library sorted by import path (`prelude` sorts after
/// the `@std/` modules). Checks every bundled source module on first use.
pub fn standard_library(syms: ms_syntax::Names) -> &'static [ApiModule] {
    static CACHE: OnceLock<Vec<ApiModule>> = OnceLock::new();
    CACHE.get_or_init(|| compute_standard_library(syms))
}

fn compute_standard_library(syms: ms_syntax::Names) -> Vec<ApiModule> {
    let session = Session::new();
    session.ensure_all_sources();
    let mut sources = HashMap::new();
    for (name, text, _) in stdlib::SOURCES {
        let file = n(&format!("@std/{name}"));
        // The source half of a mixed module shares its file's text.
        sources.insert(
            n(&format!("{file_t}+source", file_t = syms.str(file))),
            Source::new(Arc::from(*text)),
        );
        sources.insert(file, Source::new(Arc::from(*text)));
    }
    let sources = Sources(sources);
    let mut methods = session.standard_implementations();
    // Mixed native/source files keep their checked implementations under
    // `<path>+source`, which the public module list deliberately omits.
    let source_files: BTreeSet<_> = sources.0.keys().copied().collect();
    for path in source_files {
        if let Some(done) = session.done(path) {
            methods.extend(done.methods.iter().cloned());
        }
    }
    let mut modules: BTreeMap<String, Vec<SymRef>> = BTreeMap::new();
    for path in session.standard_module_names() {
        for symbol in session.standard_exports(path).into_values() {
            if symbol.export {
                modules.entry(path.to_string()).or_default().push(symbol);
            }
        }
    }
    let prelude = modules.entry("prelude".to_string()).or_default();
    for name in stdlib::PRIMITIVE_NAMES {
        prelude.push(primitive_symbol(name));
    }
    for name in stdlib::STANDARD_PRELUDE_NAMES {
        if let Some(symbol) = session.standard_symbol(name) {
            prelude.push(symbol);
        }
    }
    modules
        .into_iter()
        .map(|(path, mut symbols)| {
            symbols.sort_by(|a, b| syms.str(a.name).cmp(syms.str(b.name)));
            let declarations = symbols
                .iter()
                .map(|symbol| {
                    let mut d = document_symbol(syms, &session, symbol, &sources);
                    document_implementations(syms, &mut d, symbol, &methods, &sources);
                    d
                })
                .collect();
            ApiModule { path, declarations }
        })
        .collect::<Vec<_>>()
        .tap_shape_interfaces()
}

/// Lists, under `implements`, each plain interface whose operations a type has among its own
/// methods: a type satisfies an interface by shape, with no `impl` naming it.
trait ShapeInterfaces {
    fn tap_shape_interfaces(self) -> Self;
}

impl ShapeInterfaces for Vec<ApiModule> {
    fn tap_shape_interfaces(mut self) -> Self {
        // A generic interface or one with a type parameter of its own has no exact operation text.
        let interfaces: Vec<(String, BTreeSet<String>)> = self
            .iter()
            .flat_map(|m| &m.declarations)
            .filter(|d| {
                d.kind == "interface" && d.parameters.is_empty() && !d.operations.is_empty()
            })
            .map(|d| (d.name.clone(), d.operations.iter().cloned().collect()))
            .collect();
        for d in self.iter_mut().flat_map(|m| &mut m.declarations) {
            if d.kind == "interface" || d.operations.is_empty() {
                continue;
            }
            let own: BTreeSet<&String> = d.operations.iter().collect();
            for (name, ops) in &interfaces {
                if !d.implements.contains(name) && ops.iter().all(|op| own.contains(op)) {
                    d.implements.push(name.clone());
                }
            }
            d.implements.sort();
        }
        self
    }
}

fn primitive_symbol(name: &str) -> SymRef {
    let nm = n(name);
    Rc::new(ms_check::api::types::Sym {
        name: nm,
        id: nm,
        kind: SymKind::Type,
        module: n(""),
        native: ms_check::api::types::Native::Source,
        export: true,
        ty: std::cell::RefCell::new(Some(ms_check::api::types::primitive(name))),
        variables: std::cell::RefCell::new(Vec::new()),
        decl: None,
    })
}

/// The exports declared by each checked source module. Imported symbols and
/// private declarations do not become public documentation.
pub fn module_documentation(syms: ms_syntax::Names, program: &Program) -> Vec<ApiModule> {
    let mut sources = HashMap::new();
    for module in &program.modules {
        sources.insert(module.file, Source::new(module.source.clone()));
    }
    let sources = Sources(sources);
    let mut modules = Vec::new();
    for module in &program.modules {
        let symbols: Option<&Names> = program.symbols.get(&module.file);
        let mut declarations = Vec::new();
        for decl in &module.decls {
            if !decl.decl().export
                || matches!(decl.decl().kind, DeclKind::Impl(_) | DeclKind::Test(_))
            {
                continue;
            }
            let Some(symbol) = symbols.and_then(|s| s.borrow().get(&decl.name()).cloned()) else {
                continue;
            };
            if !symbol.decl.as_ref().is_some_and(|d| d.same(decl)) {
                continue;
            }
            let mut d = document_symbol(syms, &program.session, &symbol, &sources);
            document_implementations(syms, &mut d, &symbol, &program.methods, &sources);
            declarations.push(d);
        }
        declarations.sort_by(|a, b| a.name.cmp(&b.name));
        modules.push(ApiModule {
            path: syms.str(module.file).to_string(),
            declarations,
        });
    }
    modules.sort_by(|a, b| a.path.cmp(&b.path));
    modules.tap_shape_interfaces()
}

fn variable_text(syms: ms_syntax::Names, v: &Ty) -> String {
    let mut parameter = syms.str(v.name).to_string();
    for (i, b) in v.bounds().iter().enumerate() {
        parameter += if i == 0 { ": " } else { " & " };
        parameter += &b.display(syms).to_string();
    }
    parameter
}

fn document_operation_name(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    receiver: &Ty,
    name: &str,
) -> String {
    let variables = session.operation_variables(&format!("{}/{}", syms.str(receiver.id), name));
    if variables.is_empty() {
        return name.to_string();
    }
    let params: Vec<String> = variables.iter().map(|a| variable_text(syms, a)).collect();
    format!("{name}[{}]", params.join(", "))
}

fn fn_declaration(
    syms: ms_syntax::Names,
    name: &str,
    f: &Func,
    mutating: bool,
    source: Option<&Source>,
) -> String {
    format!(
        "{}{name}{}{} {}:\n",
        if mutating { "var fn " } else { "fn " },
        render::type_parameters(syms, &f.type_params),
        render::parameters(syms, &f.params, source),
        render::type_text(syms, &f.result)
    )
}

/// A method declared on `receiver`: `fn var Receiver.name(...)` when it changes `self`.
fn receiver_declaration(
    syms: ms_syntax::Names,
    receiver: &str,
    name: &str,
    f: &Func,
    mutating: bool,
    source: Option<&Source>,
) -> String {
    format!(
        "fn {}{receiver}.{name}{}{} {}:\n",
        if mutating { "var " } else { "" },
        render::type_parameters(syms, &f.type_params),
        render::parameters(syms, &f.params, source),
        render::type_text(syms, &f.result)
    )
}

/// Keeps source names and declaration order, omitting function bodies.
fn document_declaration(
    syms: ms_syntax::Names,
    decl: &DeclRef,
    keyword: &str,
    name: &str,
    source: Option<&Source>,
    opaque: bool,
) -> String {
    if let Some(f) = decl.func() {
        return fn_declaration(syms, name, f, false, source);
    }
    let prefix = if opaque { "opaque " } else { "" };
    let mut b = format!(
        "{prefix}{keyword} {name}{}:\n",
        render::type_parameters(syms, decl.type_params())
    );
    for field in decl.type_fields().iter().filter(|_| !opaque) {
        b += &format!(
            "    {}: {}",
            syms.str(field.name),
            field
                .ty
                .as_ref()
                .map_or(String::new(), |a| render::type_text(syms, a))
        );
        if field.default.is_some() {
            b += &format!(" = {}", render::default_text(syms, field, source));
        }
        b.push('\n');
    }
    for c in decl.cases().iter().filter(|_| !opaque) {
        b += &format!("    {}", syms.str(c.name));
        if !c.fields.is_empty() {
            b += &render::parameters(syms, &c.fields, source);
        }
        b.push('\n');
    }
    let receiver = format!("{name}{}", render::type_arguments(syms, decl.type_params()));
    if matches!(keyword, "type" | "enum") && !decl.methods().is_empty() {
        b.push('\n');
    }
    for method in decl.methods() {
        if keyword == "interface" {
            let header = fn_declaration(
                syms,
                syms.str(method.func.name),
                &method.func,
                method.mutating,
                source,
            );
            b += &format!("    {}\n", header.strip_suffix(":\n").unwrap_or(&header));
        } else {
            b += &receiver_declaration(
                syms,
                &receiver,
                syms.str(method.func.name),
                &method.func,
                method.mutating,
                source,
            );
        }
    }
    b
}

fn is_interface(decl: &DeclRef) -> bool {
    matches!(decl.decl().kind, DeclKind::Interface(_))
}

fn sort_members(members: &mut [ApiMember]) {
    members.sort_by(|a, b| {
        (a.kind.as_str(), a.name.as_str(), a.contract.as_str()).cmp(&(
            b.kind.as_str(),
            b.name.as_str(),
            b.contract.as_str(),
        ))
    });
}

fn document_members(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    decl: &DeclRef,
    source: Option<&Source>,
    receiver: &Ty,
) -> Vec<ApiMember> {
    let opaque = receiver.opaque_module().is_some();
    let text = source.map_or("", Source::text);
    let comment = |offset: u32| leading_comment(text, offset as usize);
    let mut members = Vec::new();
    for field in decl.type_fields().iter().filter(|_| !opaque) {
        let mut signature = format!(
            "{}: {}",
            syms.str(field.name),
            field
                .ty
                .as_ref()
                .map_or(String::new(), |a| render::type_text(syms, a))
        );
        if field.default.is_some() {
            signature += &format!(" = {}", render::default_text(syms, field, source));
        }
        members.push(ApiMember {
            name: syms.str(field.name).to_string(),
            kind: "field".into(),
            signature,
            doc: comment(field.pos.offset),
            contract: String::new(),
            legacy_contract: String::new(),
        });
    }
    for c in decl.cases().iter().filter(|_| !opaque) {
        let mut signature = syms.str(c.name).to_string();
        if !c.fields.is_empty() {
            signature += &render::parameters(syms, &c.fields, None);
        }
        members.push(ApiMember {
            name: syms.str(c.name).to_string(),
            kind: "case".into(),
            signature,
            doc: comment(c.pos.offset),
            contract: String::new(),
            legacy_contract: String::new(),
        });
        for field in &c.fields {
            members.push(ApiMember {
                name: format!("{}.{}", syms.str(c.name), syms.str(field.name)),
                kind: "field".into(),
                signature: format!(
                    "{}: {}",
                    syms.str(field.name),
                    field
                        .ty
                        .as_ref()
                        .map_or(String::new(), |a| render::type_text(syms, a))
                ),
                doc: comment(field.pos.offset),
                contract: String::new(),
                legacy_contract: String::new(),
            });
        }
    }
    for method in decl.methods() {
        let name = document_operation_name(syms, session, receiver, syms.str(method.func.name));
        let mut signature = fn_declaration(
            syms,
            syms.str(method.func.name),
            &method.func,
            method.mutating,
            source,
        )
        .trim()
        .to_string();
        if is_interface(decl) {
            signature = signature
                .strip_suffix(':')
                .unwrap_or(&signature)
                .to_string();
        }
        members.push(ApiMember {
            name,
            kind: "operation".into(),
            signature,
            doc: comment(method.pos.offset),
            contract: String::new(),
            legacy_contract: String::new(),
        });
    }
    sort_members(&mut members);
    members
}

fn document_symbol(
    syms: ms_syntax::Names,
    session: &Rc<Session>,
    symbol: &SymRef,
    sources: &Sources,
) -> ApiDeclaration {
    let ty = symbol.ty(syms);
    let source = sources.of(symbol.module);
    let kind = match symbol.kind {
        SymKind::Type => "type",
        SymKind::Alias => "alias",
        SymKind::Fn => "fn",
    };
    let mut d = ApiDeclaration {
        name: syms.str(symbol.name).to_string(),
        kind: kind.to_string(),
        ty: ty.display(syms).to_string(),
        opaque: ty.opaque_module().is_some(),
        ..ApiDeclaration::default()
    };
    if symbol.decl.is_none() {
        d.doc = primitive_documentation(syms.str(ty.id)).to_string();
    }
    let intrinsic = session.intrinsic_operations(ty.id);
    if let Some(decl) = &symbol.decl {
        let keyword = match source {
            _ if !decl.cases().is_empty() => "enum",
            Some(s)
                if s.text()
                    .get(decl.pos().offset as usize..)
                    .is_some_and(|t| t.starts_with("interface")) =>
            {
                "interface"
            }
            _ => "type",
        };
        d.declaration =
            document_declaration(syms, decl, keyword, syms.str(symbol.name), source, d.opaque);
        if decl.is_constant() {
            d.kind = "constant".into();
            d.ty = ty.result_ty().display(syms).to_string();
            d.declaration = format!("{}: {}\n", syms.str(symbol.name), d.ty);
        }
        d.doc = leading_comment(source.map_or("", Source::text), decl.pos().offset as usize);
        d.effects =
            declared_effect_lines(source.map_or("", Source::text), decl.pos().offset as usize);
        d.members = document_members(syms, session, decl, source, &ty);
    } else {
        d.declaration = format!("type {}:\n", syms.str(symbol.name));
        // The primitive's own interface gives the declaration; shared interfaces add their members with
        // `T`, the receiver, spelled as this type.
        for (index, interface) in intrinsic.iter().enumerate() {
            let Some((decl, module)) = interface
                .def
                .as_ref()
                .and_then(|def| def.symbol())
                .and_then(|s| s.decl.clone().map(|decl| (decl, s.module)))
            else {
                continue;
            };
            if index == 0 {
                d.declaration =
                    document_declaration(syms, &decl, "type", syms.str(symbol.name), None, false);
            }
            let mut members = document_members(syms, session, &decl, sources.of(module), &ty);
            if !interface.args.is_empty() {
                for member in &mut members {
                    member.signature = member
                        .signature
                        .replace("(other: T)", &format!("(other: {})", syms.str(symbol.name)))
                        .replace(") T", &format!(") {}", syms.str(symbol.name)));
                }
            }
            d.members.extend(members);
        }
    }
    d.parameters = symbol
        .variables()
        .iter()
        .map(|a| variable_text(syms, a))
        .collect();
    let mut operations: BTreeMap<String, String> = BTreeMap::new();
    if let Some(def) = &ty.def {
        d.kind = def_kind(def).to_string();
        if symbol.decl.as_ref().is_some_and(is_interface) {
            d.kind = "interface".into();
        }
        for f in def.fields.borrow().iter().filter(|_| !d.opaque) {
            d.fields
                .push(format!("{}: {}", syms.str(f.name), f.ty.display(syms)));
        }
        for c in def.cases.borrow().iter().filter(|_| !d.opaque) {
            let mut value = syms.str(c.name).to_string();
            if !c.fields.is_empty() {
                let fields: Vec<String> = c
                    .fields
                    .iter()
                    .map(|f| format!("{}: {}", syms.str(f.name), f.ty.display(syms)))
                    .collect();
                value += &format!("({})", fields.join(", "));
            }
            d.cases.push(value);
        }
        for op in def.operations.borrow().iter() {
            operations.insert(
                document_operation_name(syms, session, &ty, syms.str(op.name)),
                op.ty.display(syms).to_string(),
            );
        }
    }
    for interface in &intrinsic {
        let Some(def) = &interface.def else {
            continue;
        };
        let bindings = substitution(interface);
        for op in def.operations.borrow().iter() {
            operations.insert(
                syms.str(op.name).to_string(),
                sub(&op.ty, &bindings).display(syms).to_string(),
            );
        }
    }
    d.operations = operations
        .into_iter()
        .map(|(k, v)| format!("{k}: {v}"))
        .collect();
    d.operations.sort();
    d
}

fn def_kind(def: &Definition) -> &'static str {
    def.kind.as_str()
}

fn receiver_context(syms: ms_syntax::Names, method: &MethodRef, declaration: &Ty) -> String {
    let bounds: Vec<_> = method
        .split_variables()
        .0
        .iter()
        .filter(|variable| !variable.bounds().is_empty())
        .map(|a| variable_text(syms, a))
        .collect();
    if bounds.is_empty() && same(&method.receiver, declaration) {
        return String::new();
    }
    let mut context = format!("// Receiver: {}", method.receiver.display(syms));
    if !bounds.is_empty() {
        context += &format!("; {}", bounds.join(", "));
    }
    context.push('\n');
    context
}

fn document_implementations(
    syms: ms_syntax::Names,
    d: &mut ApiDeclaration,
    symbol: &SymRef,
    methods: &[MethodRef],
    sources: &Sources,
) {
    let ty = symbol.ty(syms);
    let mut contracts: BTreeSet<String> = BTreeSet::new();
    let mut seen: BTreeSet<String> = d.operations.iter().cloned().collect();
    let mut declarations = BTreeSet::new();
    for method in methods {
        if method.receiver.id != ty.id {
            continue;
        }
        let inherent = method.decl.as_ref().is_some_and(|decl| {
            (decl.decl.decl().synthetic && matches!(decl.decl.decl().kind, DeclKind::Impl(_)))
                || sources
                    .of(method.module)
                    .is_some_and(|source| source.is_inherent_impl(decl.decl.pos().offset))
        });
        let contract = method
            .contract
            .as_ref()
            .map_or_else(|| "<unknown>".to_string(), |c| c.display(syms).to_string());
        let legacy_contract = if inherent {
            contract.clone()
        } else {
            String::new()
        };
        let contract = if inherent { String::new() } else { contract };
        if !contract.is_empty() {
            contracts.insert(contract.clone());
        }
        let Some(decl) = &method.decl else { continue };
        let Some(f) = decl.func() else { continue };
        // Imported source modules can expose the same checked implementation
        // repeatedly. Its source identity distinguishes real overloads.
        if !declarations.insert((method.module, decl.decl.id(), decl.index)) {
            continue;
        }
        let name = syms.str(f.name);
        let context = receiver_context(syms, method, &ty);
        let declaration = if inherent {
            format!(
                "{context}{}",
                receiver_declaration(
                    syms,
                    &method.receiver.display(syms).to_string(),
                    name,
                    f,
                    decl.method().is_some_and(|m| m.mutating),
                    None,
                )
            )
        } else {
            format!(
                "{context}impl {contract} for {}:\n    {}",
                method.receiver.display(syms),
                fn_declaration(
                    syms,
                    name,
                    f,
                    decl.method().is_some_and(|m| m.mutating),
                    None
                )
            )
        };
        d.implementation_declarations.push(declaration);
        let operation = format!("{name}: {}", method.ty.display(syms));
        let source = sources.of(method.module);
        d.members.push(ApiMember {
            name: name.to_string(),
            kind: "operation".into(),
            signature: format!(
                "{context}{}",
                fn_declaration(
                    syms,
                    name,
                    f,
                    decl.method().is_some_and(|m| m.mutating),
                    source
                )
                .trim()
            ),
            doc: leading_comment(
                source.map_or("", Source::text),
                method_offset(decl) as usize,
            ),
            contract,
            legacy_contract,
        });
        if seen.insert(operation.clone()) {
            d.operations.push(operation);
        }
    }
    d.implements = contracts.into_iter().collect();
    d.operations.sort();
    sort_members(&mut d.members);
}

fn method_offset(decl: &FuncRef) -> u32 {
    decl.pos().offset
}

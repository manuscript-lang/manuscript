//! Detached documentation snapshots of importable modules
//! of the bundled standard library, or the
//! exports of a checked program.

use crate::guide::render;
use crate::guide::source::{Source, leading_comment};
use ms_check::Program;
use ms_check::checker::Names;
use ms_check::stdlib;
use ms_check::syntax::{DeclRef, FuncRef};
use ms_check::types::{Definition, MethodRef, Name, SymKind, SymRef, Ty, n};
use ms_syntax::{DeclKind, Func};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::rc::Rc;
use std::sync::{Arc, OnceLock};

/// A detached documentation snapshot of an importable module.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiModule {
    /// Import path (`@std/json.ms`, `prelude`, or a program file).
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
    /// `fn`, `record`, `alternative`, `interface`, `native`, `constant`, `type`.
    pub kind: String,
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
pub fn standard_library() -> &'static [ApiModule] {
    static CACHE: OnceLock<Vec<ApiModule>> = OnceLock::new();
    CACHE.get_or_init(compute_standard_library)
}

fn compute_standard_library() -> Vec<ApiModule> {
    stdlib::ensure_all_sources();
    let mut sources = HashMap::new();
    for (name, text) in stdlib::SOURCES {
        let file = n(&format!("@std/{name}"));
        // The source half of a mixed module shares its file's text.
        sources.insert(n(&format!("{file}+source")), Source::new(Arc::from(*text)));
        sources.insert(file, Source::new(Arc::from(*text)));
    }
    let sources = Sources(sources);
    let mut methods = stdlib::standard_implementations();
    for path in stdlib::standard_module_names() {
        if let Some(done) = stdlib::done(n(path)) {
            methods.extend(done.methods.iter().cloned());
        }
    }
    let mut modules: BTreeMap<String, Vec<SymRef>> = BTreeMap::new();
    for path in stdlib::standard_module_names() {
        for symbol in stdlib::standard_exports(path).into_values() {
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
        if let Some(symbol) = stdlib::standard_symbol(name) {
            prelude.push(symbol);
        }
    }
    modules
        .into_iter()
        .map(|(path, mut symbols)| {
            symbols.sort_by(|a, b| a.name.as_str().cmp(b.name.as_str()));
            let declarations = symbols
                .iter()
                .map(|symbol| {
                    let mut d = document_symbol(symbol, &sources);
                    document_implementations(&mut d, symbol, &methods, &sources);
                    d
                })
                .collect();
            ApiModule { path, declarations }
        })
        .collect()
}

fn primitive_symbol(name: &str) -> SymRef {
    let nm = n(name);
    Rc::new(ms_check::types::Sym {
        name: nm,
        id: nm,
        kind: SymKind::Type,
        module: n(""),
        native: n(""),
        export: true,
        ty: std::cell::RefCell::new(Some(ms_check::types::primitive(name))),
        variables: std::cell::RefCell::new(Vec::new()),
        decl: None,
    })
}

/// The exports declared by each checked source module. Imported symbols and
/// private declarations do not become public documentation.
pub fn module_documentation(program: &Program) -> Vec<ApiModule> {
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
            let mut d = document_symbol(&symbol, &sources);
            document_implementations(&mut d, &symbol, &program.methods, &sources);
            declarations.push(d);
        }
        declarations.sort_by(|a, b| a.name.cmp(&b.name));
        modules.push(ApiModule {
            path: module.file.as_str().to_string(),
            declarations,
        });
    }
    modules.sort_by(|a, b| a.path.cmp(&b.path));
    modules
}

fn variable_text(v: &Ty) -> String {
    let mut parameter = v.name.as_str().to_string();
    for (i, b) in v.bounds().iter().enumerate() {
        parameter += if i == 0 { ": " } else { " & " };
        parameter += &b.to_string();
    }
    parameter
}

fn document_operation_name(receiver: &Ty, name: &str) -> String {
    let variables = stdlib::operation_variables(&format!("{}/{}", receiver.id, name));
    if variables.is_empty() {
        return name.to_string();
    }
    let params: Vec<String> = variables.iter().map(variable_text).collect();
    format!("{name}[{}]", params.join(", "))
}

fn fn_declaration(name: &str, f: &Func, mutating: bool, source: Option<&Source>) -> String {
    format!(
        "{}{name}{}{} {}:\n",
        if mutating { "var fn " } else { "fn " },
        render::type_parameters(&f.type_params),
        render::parameters(&f.params, source),
        render::type_text(&f.result)
    )
}

/// Keeps source names and declaration order, omitting function bodies.
fn document_declaration(
    decl: &DeclRef,
    keyword: &str,
    name: &str,
    source: Option<&Source>,
) -> String {
    if let Some(f) = decl.func() {
        return fn_declaration(name, f, false, source);
    }
    let mut b = format!(
        "{keyword} {name}{}:\n",
        render::type_parameters(decl.type_params())
    );
    for field in decl.record_fields() {
        b += &format!(
            "    {}: {}",
            field.name,
            field.ty.as_ref().map_or(String::new(), render::type_text)
        );
        if field.default.is_some() {
            b += &format!(" = {}", render::default_text(field, source));
        }
        b.push('\n');
    }
    for c in decl.cases() {
        b += &format!("    case {}", c.name);
        if !c.fields.is_empty() {
            b += &render::parameters(&c.fields, source);
        }
        b.push('\n');
    }
    if keyword == "type" && !decl.methods().is_empty() {
        // A type's own methods are written in an `impl Type:` block.
        b += &format!(
            "\nimpl {name}{}:\n",
            render::type_arguments(decl.type_params())
        );
    }
    for method in decl.methods() {
        let mut header = fn_declaration(
            method.func.name.as_str(),
            &method.func,
            method.mutating,
            source,
        );
        if keyword == "interface" {
            header = header.strip_suffix(":\n").unwrap_or(&header).to_string() + "\n";
        }
        b += &format!("    {header}");
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

fn document_members(decl: &DeclRef, source: Option<&Source>, receiver: &Ty) -> Vec<ApiMember> {
    let text = source.map_or("", Source::text);
    let comment = |offset: u32| leading_comment(text, offset as usize);
    let mut members = Vec::new();
    for field in decl.record_fields() {
        let mut signature = format!(
            "{}: {}",
            field.name,
            field.ty.as_ref().map_or(String::new(), render::type_text)
        );
        if field.default.is_some() {
            signature += &format!(" = {}", render::default_text(field, source));
        }
        members.push(ApiMember {
            name: field.name.as_str().to_string(),
            kind: "field".into(),
            signature,
            doc: comment(field.pos.offset),
            contract: String::new(),
        });
    }
    for c in decl.cases() {
        let mut signature = format!("case {}", c.name);
        if !c.fields.is_empty() {
            signature += &render::parameters(&c.fields, None);
        }
        members.push(ApiMember {
            name: c.name.as_str().to_string(),
            kind: "case".into(),
            signature,
            doc: comment(c.pos.offset),
            contract: String::new(),
        });
        for field in &c.fields {
            members.push(ApiMember {
                name: format!("{}.{}", c.name, field.name),
                kind: "field".into(),
                signature: format!(
                    "{}: {}",
                    field.name,
                    field.ty.as_ref().map_or(String::new(), render::type_text)
                ),
                doc: comment(field.pos.offset),
                contract: String::new(),
            });
        }
    }
    for method in decl.methods() {
        let name = document_operation_name(receiver, method.func.name.as_str());
        let mut signature = fn_declaration(
            method.func.name.as_str(),
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
        });
    }
    sort_members(&mut members);
    members
}

fn document_symbol(symbol: &SymRef, sources: &Sources) -> ApiDeclaration {
    let ty = symbol.ty();
    let source = sources.of(symbol.module);
    let kind = match symbol.kind {
        SymKind::Type => "type",
        SymKind::Fn => "fn",
    };
    let mut d = ApiDeclaration {
        name: symbol.name.as_str().to_string(),
        kind: kind.to_string(),
        ty: ty.to_string(),
        ..ApiDeclaration::default()
    };
    if symbol.decl.is_none() {
        d.doc = primitive_documentation(ty.id.as_str()).to_string();
    }
    let intrinsic = stdlib::intrinsic_operations(ty.id);
    if let Some(decl) = &symbol.decl {
        let keyword = match source {
            Some(s)
                if s.text()
                    .get(decl.pos().offset as usize..)
                    .is_some_and(|t| t.starts_with("interface")) =>
            {
                "interface"
            }
            _ => "type",
        };
        d.declaration = document_declaration(decl, keyword, symbol.name.as_str(), source);
        if decl.is_constant() {
            d.kind = "constant".into();
            d.ty = ty.result_ty().to_string();
            d.declaration = format!("let {}: {}\n", symbol.name, d.ty);
        }
        d.doc = leading_comment(source.map_or("", Source::text), decl.pos().offset as usize);
        d.members = document_members(decl, source, &ty);
    } else if let Some(decl) = intrinsic
        .as_ref()
        .and_then(|t| t.def.as_ref())
        .and_then(|def| def.symbol())
        .and_then(|s| s.decl.clone().map(|decl| (decl, s.module)))
    {
        let (decl, module) = decl;
        d.declaration = document_declaration(&decl, "type", symbol.name.as_str(), None);
        d.members = document_members(&decl, sources.of(module), &ty);
    } else {
        d.declaration = format!("type {}:\n", symbol.name);
    }
    d.parameters = symbol.variables().iter().map(variable_text).collect();
    let mut operations: BTreeMap<String, String> = BTreeMap::new();
    if let Some(def) = &ty.def {
        d.kind = def_kind(def).to_string();
        if symbol.decl.as_ref().is_some_and(is_interface) {
            d.kind = "interface".into();
        }
        for f in def.fields.borrow().iter() {
            d.fields.push(format!("{}: {}", f.name, f.ty));
        }
        for c in def.cases.borrow().iter() {
            let mut value = c.name.as_str().to_string();
            if !c.fields.is_empty() {
                let fields: Vec<String> = c
                    .fields
                    .iter()
                    .map(|f| format!("{}: {}", f.name, f.ty))
                    .collect();
                value += &format!("({})", fields.join(", "));
            }
            d.cases.push(value);
        }
        for op in def.operations.borrow().iter() {
            operations.insert(
                document_operation_name(&ty, op.name.as_str()),
                op.ty.to_string(),
            );
        }
    }
    if let Some(intrinsic) = &intrinsic
        && let Some(def) = &intrinsic.def
    {
        for op in def.operations.borrow().iter() {
            operations.insert(op.name.as_str().to_string(), op.ty.to_string());
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

fn document_implementations(
    d: &mut ApiDeclaration,
    symbol: &SymRef,
    methods: &[MethodRef],
    sources: &Sources,
) {
    let ty = symbol.ty();
    let mut contracts: BTreeSet<String> = BTreeSet::new();
    let mut seen: BTreeSet<String> = BTreeSet::new();
    for method in methods {
        if method.receiver.id != ty.id {
            continue;
        }
        let contract = method
            .contract
            .as_ref()
            .map_or_else(|| "<unknown>".to_string(), |c| c.to_string());
        contracts.insert(contract.clone());
        let Some(decl) = &method.decl else { continue };
        let Some(f) = decl.func() else { continue };
        let name = f.name.as_str();
        d.implementation_declarations.push(format!(
            "impl {contract} for {}:\n    {}",
            method.receiver,
            fn_declaration(name, f, decl.method().is_some_and(|m| m.mutating), None)
        ));
        let operation = format!("{name}: {}", method.ty);
        let source = sources.of(method.module);
        d.members.push(ApiMember {
            name: name.to_string(),
            kind: "operation".into(),
            signature: fn_declaration(name, f, decl.method().is_some_and(|m| m.mutating), source)
                .trim()
                .to_string(),
            doc: leading_comment(
                source.map_or("", Source::text),
                method_offset(decl) as usize,
            ),
            contract,
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

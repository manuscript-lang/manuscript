//! Passes that run around checking: inherent-impl desugaring, and the
//! post-check passes that make trees ready for lowering (constant folding,
//! argument order, `try` shape).

use crate::syntax::*;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::Method;
use ms_syntax::ast::*;
use ms_syntax::visit::{self, Visitor};
use std::collections::HashMap;

/// A misuse of an inherent `impl Type:` block.
pub struct InherentError {
    /// Position of the offending node.
    pub pos: Pos,
    /// Diagnostic message.
    pub message: String,
}

/// The suffix that keeps the interface synthesized for a type's own methods from colliding with
/// a declared name. Identity is the `synthetic` flag of the impl, never this suffix.
pub(crate) const INHERENT_SUFFIX: &str = "$methods";

fn named_args(t: &TypeRef) -> &[TypeRef] {
    match &t.kind {
        TypeKind::Named { args, .. } => args,
        TypeKind::Fn { .. } => &[],
    }
}

fn repeats_type_parameters(receiver: &TypeRef, params: &[TypeParam]) -> bool {
    let args = named_args(receiver);
    if args.len() != params.len() {
        return false;
    }
    args.iter().zip(params).all(|(a, p)| match &a.kind {
        TypeKind::Named { name, args } => *name == p.name && args.is_empty(),
        TypeKind::Fn { .. } => false,
    })
}

/// Text identifying a written type, for grouping receiver methods that share a receiver.
fn type_key(syms: ms_syntax::Names, t: &TypeRef) -> String {
    match &t.kind {
        TypeKind::Named { name, args } => {
            let args: Vec<String> = args.iter().map(|a| type_key(syms, a)).collect();
            format!("{}[{}]", syms.str(name), args.join(","))
        }
        TypeKind::Fn { params, result } => {
            let params: Vec<String> = params
                .iter()
                .map(|p| {
                    format!(
                        "{}{}",
                        if p.mutable { "var " } else { "" },
                        p.ty.as_ref().map_or(String::new(), |t| type_key(syms, t))
                    )
                })
                .collect();
            format!("fn({}){}", params.join(","), type_key(syms, result))
        }
    }
}

/// Whether `t` names one of `params` anywhere, so it can match more than one application.
fn mentions_parameter(t: &TypeRef, params: &[TypeParam]) -> bool {
    match &t.kind {
        TypeKind::Named { name, args } => {
            params.iter().any(|p| p.name == *name)
                || args.iter().any(|a| mentions_parameter(a, params))
        }
        TypeKind::Fn { params: ps, result } => {
            ps.iter()
                .any(|p| p.ty.as_ref().is_some_and(|t| mentions_parameter(t, params)))
                || mentions_parameter(result, params)
        }
    }
}

/// `t` with each named parameter replaced by the type argument written for it.
fn substitute_parameters(t: &TypeRef, with: &[(Name, &TypeRef)]) -> TypeRef {
    match &t.kind {
        TypeKind::Named { name, args } => {
            if args.is_empty()
                && let Some((_, replacement)) = with.iter().find(|(p, _)| p == name)
            {
                return (*replacement).clone();
            }
            TypeRef {
                id: t.id,
                pos: t.pos,
                kind: TypeKind::Named {
                    name: *name,
                    args: args
                        .iter()
                        .map(|a| substitute_parameters(a, with))
                        .collect(),
                },
            }
        }
        TypeKind::Fn { params, result } => TypeRef {
            id: t.id,
            pos: t.pos,
            kind: TypeKind::Fn {
                params: params
                    .iter()
                    .map(|p| {
                        let mut p = p.clone();
                        p.ty = p.ty.as_ref().map(|t| substitute_parameters(t, with));
                        p
                    })
                    .collect(),
                result: Box::new(substitute_parameters(result, with)),
            },
        },
    }
}

fn parameter_names(syms: ms_syntax::Names, params: &[TypeParam]) -> String {
    if params.is_empty() {
        return String::new();
    }
    let names: Vec<&str> = params.iter().map(|p| syms.str(p.name)).collect();
    format!("[{}]", names.join(", "))
}

fn type_decl_params(d: &Decl) -> Option<(Name, &[TypeParam], bool)> {
    match &d.kind {
        DeclKind::Type(r) => Some((r.name, &r.type_params, false)),
        DeclKind::Alternative(a) => Some((a.name, &a.type_params, false)),
        DeclKind::Interface(i) => Some((i.name, &i.type_params, true)),
        _ => None,
    }
}

/// The property markers (`// ms: data`, `// ms: clonable`) in the comment lines just
/// above the declaration at `offset`: a bundled type with no methods of its own declares its
/// properties there, since a marker has nothing to write as a method.
fn property_markers(source: &str, offset: u32) -> Vec<&'static str> {
    let mut found = Vec::new();
    let mut end = (offset as usize).min(source.len());
    // Start of the declaration's line, then each comment line above it.
    end = source[..end].rfind('\n').map_or(0, |i| i + 1);
    while end > 0 {
        let before = &source[..end - 1];
        let start = before.rfind('\n').map_or(0, |i| i + 1);
        let line = source[start..end - 1].trim();
        let Some(text) = line.strip_prefix("//") else {
            break;
        };
        for (word, name) in [("data", "Data"), ("clonable", "Clonable")] {
            if text.trim() == format!("ms: {word}") {
                found.push(name);
            }
        }
        end = start;
    }
    found
}

/// The property-marker implementations (`Data`, `Clonable`) a bundled type declares with
/// `// ms: data`-style comments above it; each is a body-less implementation of that interface.
pub(crate) fn marker_decls(module: &Module, d: &Decl, next_id: &mut u32) -> Vec<Decl> {
    let mut out = Vec::new();
    let Some((name, params, false)) = type_decl_params(d) else {
        return out;
    };
    if !module.file.starts_with("@std/") {
        return out;
    }
    for marker in property_markers(&module.source, d.pos.offset) {
        let id = *next_id;
        let named = |name: Name, args: Vec<TypeRef>, at: u32| TypeRef {
            id: NodeId(at),
            pos: d.pos,
            kind: TypeKind::Named { name, args },
        };
        let args = params
            .iter()
            .enumerate()
            .map(|(i, p)| named(p.name, Vec::new(), id + 2 + i as u32))
            .collect();
        let receiver = named(name, args, id);
        let contract = named(n(marker), Vec::new(), id + 1);
        out.push(Decl {
            id: NodeId(id + 2 + params.len() as u32),
            pos: d.pos,
            export: false,
            synthetic: true,
            kind: DeclKind::Impl(ImplDecl {
                contract: Some(contract),
                receiver,
                bounds: Vec::new(),
                methods: Vec::new(),
            }),
        });
        *next_id += 3 + params.len() as u32;
    }
    out
}

/// Rewrites each `impl Type:` block of a source module into
/// `impl Type$methods for Type:` with a synthesized interface carrying the same
/// signatures. A type's own methods then use the ordinary implementation rules:
/// visibility wherever the type is used, exact signatures, selection by
/// receiver, and lowering as plain methods. Blocks for one type merge into the
/// first.
const BUILTIN_SCALARS: [&str; 13] = [
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64", "Float",
    "Float32", "Bool", "String",
];

/// Replaces each inherent `impl` whose receiver names a type set declared in the module
/// (`type Ordered = Int | Float`, `fn Ordered.min(...)`) with one `impl` per member, so a
/// method written once over a set exists on every member. Each copy has fresh node ids.
/// Removed once blanket generic methods land (#3604).
fn expand_set_receivers(decls: &[Decl], next_id: &mut u32) -> Vec<Decl> {
    let sets: HashMap<Name, &[TypeRef]> = decls
        .iter()
        .filter_map(|d| match &d.kind {
            DeclKind::Alias(a) if a.type_params.is_empty() && a.targets.len() > 1 => {
                Some((a.name, a.targets.as_slice()))
            }
            _ => None,
        })
        .collect();
    let mut out = Vec::with_capacity(decls.len());
    for d in decls {
        let members = match &d.kind {
            DeclKind::Impl(imp) if imp.contract.is_none() => match &imp.receiver.kind {
                TypeKind::Named { name, args } if args.is_empty() => sets.get(name),
                _ => None,
            },
            _ => None,
        };
        let Some(members) = members else {
            out.push(d.clone());
            continue;
        };
        for member in *members {
            let mut copy = d.clone();
            let DeclKind::Impl(c) = &mut copy.kind else {
                continue;
            };
            c.receiver = member.clone();
            c.receiver.id = NodeId(*next_id);
            copy.id = NodeId(*next_id + 1);
            *next_id += 2;
            for m in &mut c.methods {
                ms_syntax::renumber::renumber_method(m, next_id);
            }
            out.push(copy);
        }
    }
    out
}

pub fn desugar_inherent_impls(
    syms: ms_syntax::Names,
    module: &Module,
    foreign: &[Decl],
) -> (Vec<Decl>, Vec<InherentError>, u32) {
    let mut errors: Vec<InherentError> = Vec::new();
    let mut next_id = module.node_count;
    let mut types: HashMap<Name, (&[TypeParam], bool)> = HashMap::new();
    for d in foreign.iter().chain(&module.decls) {
        if let Some((name, params, is_interface)) = type_decl_params(d) {
            types.insert(name, (params, is_interface));
        }
    }
    // A bundled `@std/` module may give the built-in scalars methods, which no module declares.
    if module.file.starts_with("@std/") {
        for scalar in BUILTIN_SCALARS {
            types.entry(n(scalar)).or_insert((&[], false));
        }
    }
    let mut first: HashMap<(Name, String), usize> = HashMap::new();
    let mut out: Vec<Decl> = Vec::new();
    let expanded = expand_set_receivers(&module.decls, &mut next_id);
    for d in &expanded {
        let DeclKind::Impl(imp) = &d.kind else {
            out.push(d.clone());
            out.extend(marker_decls(module, d, &mut next_id));
            continue;
        };
        if imp.contract.is_some() {
            out.push(d.clone());
            continue;
        }
        let name = n(imp.receiver.name(syms));
        match types.get(&name) {
            None => errors.push(InherentError {
                pos: d.pos,
                message: format!("inherent methods belong in the module that declares {name_t}; to add operations to another module's type, write a free function or a wrapper type", name_t = syms.str(name)),
            }),
            Some((_, true)) => errors.push(InherentError {
                pos: d.pos,
                message: format!("{name_t} is an interface; a method belongs to a type, and a type whose methods match the interface satisfies it", name_t = syms.str(name)),
            }),
            Some((params, false)) if named_args(&imp.receiver).len() != params.len() => {
                errors.push(InherentError {
                    pos: d.pos,
                    message: format!("a method of {name_t} names one receiver argument per type parameter, as in 'fn {name_t}{}.name()'", parameter_names(syms, params), name_t = syms.str(name)),
                });
            }
            Some((params, false)) => {
                // Methods merge into one block per receiver form: the plain `T[A]`, a bounded
                // `T[A: Bound]`, or a specialized `T[Int]`.
                let plain = repeats_type_parameters(&imp.receiver, params) && imp.bounds.is_empty();
                let bounds: Vec<String> = imp
                    .bounds
                    .iter()
                    .map(|b| {
                        let bs: Vec<String> =
                            b.bounds.iter().map(|t| type_key(syms, t)).collect();
                        format!("{}:{}", syms.str(b.name), bs.join("&"))
                    })
                    .collect();
                let key = if plain {
                    String::new()
                } else {
                    format!("{}|{}", type_key(syms, &imp.receiver), bounds.join(";"))
                };
                if let Some(&at) = first.get(&(name, key.clone())) {
                    if let DeclKind::Impl(merged) = &mut out[at].kind {
                        merged.methods.extend(imp.methods.iter().cloned());
                    }
                    continue;
                }
                first.insert((name, key), out.len());
                out.push(d.clone());
            }
        }
    }
    // Two receiver forms of one type that could match the same application, under the same
    // written bounds, must not declare one method name.
    let forms: Vec<(usize, Name, String)> = out
        .iter()
        .enumerate()
        .filter_map(|(at, d)| match &d.kind {
            DeclKind::Impl(i) if i.contract.is_none() => {
                let bounds: Vec<String> = i
                    .bounds
                    .iter()
                    .map(|b| {
                        let bs: Vec<String> = b.bounds.iter().map(|t| type_key(syms, t)).collect();
                        format!("{}:{}", syms.str(b.name), bs.join("&"))
                    })
                    .collect();
                Some((at, n(i.receiver.name(syms)), bounds.join(";")))
            }
            _ => None,
        })
        .collect();
    for (x, (i, name_i, bounds_i)) in forms.iter().enumerate() {
        for (j, name_j, bounds_j) in &forms[x + 1..] {
            if name_i != name_j || bounds_i != bounds_j {
                continue;
            }
            let (DeclKind::Impl(a), DeclKind::Impl(b)) = (&out[*i].kind, &out[*j].kind) else {
                continue;
            };
            let Some((params, _)) = types.get(name_i) else {
                continue;
            };
            let open = |t: &TypeRef, _p: &TypeParam| mentions_parameter(t, params);
            let overlap = named_args(&a.receiver)
                .iter()
                .zip(named_args(&b.receiver))
                .zip(params.iter())
                .all(|((x, y), p)| {
                    open(x, p) || open(y, p) || type_key(syms, x) == type_key(syms, y)
                });
            if !overlap {
                continue;
            }
            for m in &b.methods {
                if a.methods.iter().any(|o| o.func.name == m.func.name) {
                    errors.push(InherentError {
                        pos: m.pos,
                        message: format!(
                            "duplicate or overlapping implementation of {} on {}: another receiver form of the same type could match the same application",
                            syms.str(m.func.name),
                            syms.str(*name_i)
                        ),
                    });
                }
            }
        }
    }
    let mut counters: HashMap<Name, usize> = HashMap::new();
    let mut final_decls: Vec<Decl> = Vec::with_capacity(out.len() + first.len());
    for mut d in out {
        let DeclKind::Impl(imp) = &mut d.kind else {
            final_decls.push(d);
            continue;
        };
        if imp.contract.is_some() {
            final_decls.push(d);
            continue;
        }
        let name = n(imp.receiver.name(syms));
        let (params, _) = types[&name];
        let plain = repeats_type_parameters(&imp.receiver, params) && imp.bounds.is_empty();
        // The interface of a bounded or specialized receiver takes only the receiver's variable
        // positions, with the written bounds added; its concrete arguments stay in the receiver.
        let mut interface_params: Vec<TypeParam> = Vec::new();
        let mut interface_args: Vec<TypeRef> = Vec::new();
        let dropped: Vec<(Name, &TypeRef)> = params
            .iter()
            .zip(named_args(&imp.receiver))
            .filter(|(p, a)| {
                !(matches!(&a.kind, TypeKind::Named { name, args } if *name == p.name && args.is_empty()))
            })
            .map(|(p, a)| (p.name, a))
            .collect();
        for (p, a) in params.iter().zip(named_args(&imp.receiver)) {
            let variable = matches!(&a.kind, TypeKind::Named { name, args } if *name == p.name && args.is_empty());
            if plain || variable {
                let mut p = p.clone();
                // A bound that names a specialized parameter reads as that argument.
                for bound in &mut p.bounds {
                    *bound = substitute_parameters(bound, &dropped);
                }
                if let Some(written) = imp.bounds.iter().find(|b| b.name == p.name) {
                    p.bounds.extend(written.bounds.iter().cloned());
                }
                interface_params.push(p);
                interface_args.push(a.clone());
            }
        }
        // A type parameter written inside a larger argument (`Box[fn(Int) T]`) is still a variable
        // of the receiver form; it carries only the bounds written for it.
        if !plain {
            for p in params {
                let direct = interface_params.iter().any(|q| q.name == p.name);
                let nested = named_args(&imp.receiver)
                    .iter()
                    .any(|a| mentions_parameter(a, std::slice::from_ref(p)));
                if direct || !nested {
                    continue;
                }
                let mut q = p.clone();
                q.bounds = imp
                    .bounds
                    .iter()
                    .find(|b| b.name == p.name)
                    .map(|b| b.bounds.clone())
                    .unwrap_or_default();
                interface_params.push(q);
                interface_args.push(TypeRef {
                    id: NodeId(next_id),
                    pos: d.pos,
                    kind: TypeKind::Named {
                        name: p.name,
                        args: Vec::new(),
                    },
                });
                next_id += 1;
            }
        }
        let contract_name = if plain {
            n(&format!(
                "{name_t}{INHERENT_SUFFIX}",
                name_t = syms.str(name)
            ))
        } else {
            let k = counters.entry(name).or_insert(0usize);
            *k += 1;
            n(&format!(
                "{name_t}${k}{INHERENT_SUFFIX}",
                name_t = syms.str(name)
            ))
        };
        let mut methods: Vec<Method> = Vec::with_capacity(imp.methods.len());
        for method in &imp.methods {
            let mut signature = method.clone();
            signature.func.body = Vec::new();
            for p in &mut signature.func.params {
                p.default = None;
            }
            methods.push(signature);
        }
        let interface = Decl {
            id: NodeId(next_id),
            pos: d.pos,
            export: false,
            synthetic: true,
            kind: DeclKind::Interface(InterfaceDecl {
                name: contract_name,
                type_params: interface_params,
                methods,
            }),
        };
        let reference = TypeRef {
            id: NodeId(next_id + 1),
            pos: d.pos,
            kind: TypeKind::Named {
                name: contract_name,
                args: interface_args,
            },
        };
        next_id += 2;
        imp.contract = Some(reference);
        d.synthetic = true;
        final_decls.push(interface);
        final_decls.push(d);
    }
    (final_decls, errors, next_id)
}

// ------------------------------------------------------------------ post passes

/// Runs the passes that make checked trees ready for lowering.
pub fn finish_modules(modules: &[ModRef]) {
    for m in modules {
        order_arguments(m);
        mark_plain_try(m);
    }
}

fn each_decl_node<V: Visitor>(module: &ModRef, v: &mut V) {
    for d in &module.decls {
        visit::walk_decl(v, d.decl());
        // Folded native methods carry only parameter defaults.
        for m in &d.0.folded {
            visit::walk_callable(v, &m.func.params, &m.func.body);
        }
    }
}

fn order_arguments(module: &ModRef) {
    struct Order<'a> {
        module: &'a ModRef,
    }
    impl Visitor for Order<'_> {
        fn expr(&mut self, e: &Expr) {
            let ExprKind::Call { args, .. } = &e.kind else {
                return;
            };
            let mut facts = self.module.facts_mut();
            if let Some(Some(info)) = facts.exprs.get_mut(e.id.index())
                && info.arguments.is_none()
            {
                info.arguments = Some(
                    args.iter()
                        .enumerate()
                        .map(|(index, a)| ArgSlot {
                            pos: a.pos,
                            name: a.name.unwrap_or_else(|| n("")),
                            index,
                        })
                        .collect(),
                );
            }
        }
    }
    each_decl_node(module, &mut Order { module });
}

fn mark_plain_try(module: &ModRef) {
    struct Plain<'a> {
        module: &'a ModRef,
    }
    impl Visitor for Plain<'_> {
        fn stmt(&mut self, s: &Stmt) {
            let value = match &s.kind {
                StmtKind::Bind { value, .. } => value,
                StmtKind::Assign {
                    target: AssignTarget::Name(_),
                    value,
                    ..
                } => value,
                StmtKind::Return(Some(value)) => value,
                StmtKind::Call(value) => value,
                _ => return,
            };
            let is_try = matches!(
                &value.kind,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    ..
                }
            );
            if !is_try {
                return;
            }
            let plain = self
                .module
                .facts()
                .info(value.id)
                .is_some_and(|i| i.interface_source.is_none());
            if plain {
                self.module
                    .facts_mut()
                    .stmts
                    .entry(s.id)
                    .or_default()
                    .plain_try = true;
            }
        }
    }
    each_decl_node(module, &mut Plain { module });
}

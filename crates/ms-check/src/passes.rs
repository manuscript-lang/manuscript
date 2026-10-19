//! Passes that run around checking: inherent-impl desugaring, and the
//! post-check passes that make trees ready for lowering (constant folding,
//! argument order, `try` shape) from `pkg/checker/{inherent,pass_*}.go`.

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

/// The suffix of the interface synthesized for a type's own methods.
pub const INHERENT_SUFFIX: &str = "$methods";

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

fn parameter_names(params: &[TypeParam]) -> String {
    if params.is_empty() {
        return String::new();
    }
    let names: Vec<&str> = params.iter().map(|p| p.name.as_str()).collect();
    format!("[{}]", names.join(", "))
}

fn type_decl_params(d: &Decl) -> Option<(Name, &[TypeParam], bool)> {
    match &d.kind {
        DeclKind::Record(r) => Some((r.name, &r.type_params, false)),
        DeclKind::Alternative(a) => Some((a.name, &a.type_params, false)),
        DeclKind::Interface(i) => Some((i.name, &i.type_params, true)),
        _ => None,
    }
}

/// Rewrites each `impl Type:` block of a source module into
/// `impl Type$methods for Type:` with a synthesized interface carrying the same
/// signatures. A type's own methods then use the ordinary implementation rules:
/// visibility wherever the type is used, exact signatures, selection by
/// receiver, and lowering as plain methods. Blocks for one type merge into the
/// first.
pub fn desugar_inherent_impls(module: &Module) -> (Vec<Decl>, Vec<InherentError>, u32) {
    let mut errors: Vec<InherentError> = Vec::new();
    let mut next_id = module.node_count;
    let mut types: HashMap<Name, (&[TypeParam], bool)> = HashMap::new();
    for d in &module.decls {
        if let Some((name, params, is_interface)) = type_decl_params(d) {
            types.insert(name, (params, is_interface));
        }
    }
    let mut first: HashMap<Name, usize> = HashMap::new();
    let mut out: Vec<Decl> = Vec::new();
    for d in &module.decls {
        let DeclKind::Impl(imp) = &d.kind else {
            out.push(d.clone());
            continue;
        };
        if imp.contract.is_some() {
            out.push(d.clone());
            continue;
        }
        let name = n(imp.receiver.name());
        match types.get(&name) {
            None => errors.push(InherentError {
                pos: d.pos,
                message: format!("inherent methods belong in the module that declares {name}; to add operations to another module's type, declare an interface and write 'impl <Interface> for {name}:'"),
            }),
            Some((_, true)) => errors.push(InherentError {
                pos: d.pos,
                message: format!("{name} is an interface; 'impl {name}:' declares a type's own methods, so write 'impl {name} for <Type>:' to implement the interface"),
            }),
            Some((params, false)) if !repeats_type_parameters(&imp.receiver, params) => {
                errors.push(InherentError {
                    pos: d.pos,
                    message: format!("impl must repeat the type parameters of {name} as its receiver arguments, as in 'impl {name}{}:'", parameter_names(params)),
                });
            }
            Some(_) => {
                if let Some(&at) = first.get(&name) {
                    if let DeclKind::Impl(merged) = &mut out[at].kind {
                        merged.methods.extend(imp.methods.iter().cloned());
                    }
                    continue;
                }
                first.insert(name, out.len());
                out.push(d.clone());
            }
        }
    }
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
        let name = n(imp.receiver.name());
        let (params, _) = types[&name];
        let contract_name = n(&format!("{name}{INHERENT_SUFFIX}"));
        let mut methods: Vec<Method> = Vec::with_capacity(imp.methods.len());
        for method in &imp.methods {
            if !method.func.type_params.is_empty() {
                errors.push(InherentError {
                    pos: method.pos,
                    message: format!("method {} declares its own type parameters, which source methods do not support yet; use a generic function that takes the receiver as an argument", method.func.name),
                });
            }
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
                type_params: params.to_vec(),
                methods,
            }),
        };
        let reference = TypeRef {
            id: NodeId(next_id + 1),
            pos: d.pos,
            kind: TypeKind::Named {
                name: contract_name,
                args: named_args(&imp.receiver).to_vec(),
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
        fold_constants(m);
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

fn fold_constants(module: &ModRef) {
    struct Fold<'a> {
        module: &'a ModRef,
    }
    impl Visitor for Fold<'_> {
        fn expr(&mut self, e: &Expr) {
            fold_bool(self.module, e);
        }
    }
    each_decl_node(module, &mut Fold { module });
}

/// Reports the constant value of `e` and whether `e` is a constant, recording
/// it on `e`'s facts. Folding never evaluates calls or changes numeric fault
/// behavior: only a constant left operand may drop the right operand.
fn fold_bool(module: &ModRef, e: &Expr) -> (bool, bool) {
    let info = module.facts().info(e.id).cloned();
    let Some(info) = info else {
        return (false, false);
    };
    if info.ty.as_ref().is_none_or(|t| t.id != "Bool") {
        return (false, false);
    }
    if info.fold_done {
        return (info.constant, info.folded);
    }
    let (value, constant) = fold(module, e);
    let mut facts = module.facts_mut();
    if let Some(Some(stored)) = facts.exprs.get_mut(e.id.index()) {
        stored.constant = value;
        stored.folded = constant;
        stored.fold_done = true;
    }
    (value, constant)
}

fn fold(module: &ModRef, e: &Expr) -> (bool, bool) {
    match &e.kind {
        ExprKind::Bool(b) => (*b, true),
        ExprKind::Unary {
            op: UnaryOp::Not,
            operand,
        } => {
            let (right, ok) = fold_bool(module, operand);
            (!right, ok)
        }
        ExprKind::Binary { op, left, right } if matches!(op, BinaryOp::And | BinaryOp::Or) => {
            let (l, ok) = fold_bool(module, left);
            if !ok {
                return (false, false);
            }
            // Only a constant left operand may eliminate the right operand.
            if (*op == BinaryOp::And && !l) || (*op == BinaryOp::Or && l) {
                return (l, true);
            }
            fold_bool(module, right)
        }
        _ => (false, false),
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
                .is_some_and(|i| i.error_source.is_none());
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

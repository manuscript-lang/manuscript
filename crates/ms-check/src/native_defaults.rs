//! Default expressions of native standard declarations

use crate::checker::Checker;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;

fn is_none(e: &Expr) -> bool {
    matches!(&e.kind, ExprKind::Name(nm) if nm == "none")
}

/// Extended defaults need source preparation rather than the native none adapter.
fn has_extended_defaults(params: &[ms_syntax::ast::Param]) -> bool {
    params
        .iter()
        .any(|p| p.default.as_ref().is_some_and(|e| !is_none(e)))
}

fn closed_literal_defaults(params: &[ms_syntax::ast::Param]) -> bool {
    params.iter().all(|p| match &p.default {
        None => true,
        Some(e) => {
            matches!(
                e.kind,
                ExprKind::Bool(_) | ExprKind::Number(_) | ExprKind::Unit
            ) || is_none(e)
        }
    })
}

impl Checker {
    /// Checks the default expressions of one native standard callable.
    pub(crate) fn check_native_defaults(
        &mut self,
        d: &FuncRef,
        params: &[ms_syntax::ast::Param],
        t: &Ty,
        variables: &[Ty],
        contract: bool,
    ) {
        if !has_extended_defaults(params) {
            // Existing Optional.none adapters retain their allocation-free path.
            for parameter in params {
                let optional = parameter
                    .ty
                    .as_ref()
                    .is_some_and(|ty| ty.name() == "Optional");
                if parameter.default.is_some() && !optional {
                    self.type_error(
                        parameter.pos,
                        "none default requires Optional; use a value matching the declared type",
                    );
                }
            }
            return;
        }
        // Keep this first native-default slice bounded. Source generic defaults and
        // generic calls through nongeneric standard contracts retain their existing
        // rules; native generic expression defaults need a substitution design.
        if !variables.is_empty() && !closed_literal_defaults(params) {
            self.type_error(
                d.pos(),
                "native generic expression defaults are not supported; keep '= none' on Optional parameters or use a source wrapper",
            );
            return;
        }
        let record = d.index.is_none() && matches!(d.decl.decl().kind, DeclKind::Record(_));
        if record && t.result_ty().kind != Kind::Record {
            self.type_error(
                d.pos(),
                "native opaque constructor expression defaults need a delivery/disposal design; keep Optional.none defaults or use a source wrapper",
            );
            return;
        }
        let old_scope = self.scope.clone();
        let old_result = self.result.clone();
        let old_function = self.function;
        self.scope = self.variable_scope(variables);
        self.result = t.result.clone();
        self.serial += 1;
        self.function = self.serial;
        self.check_parameters(d, params, &t.params);
        if contract {
            // Inherited preparation precedes an implementation's own defaults.
            // Keep this bounded interface slice independent and free of effects;
            // combining dependent/effectful defaults needs one ordered prologue.
            for parameter in params {
                if let Some(e) = &parameter.default
                    && !self.closed_interface_default(e)
                {
                    self.type_error(
                            parameter.pos,
                            "standard interface expression defaults must be closed literals or bytes from literal text; use a source wrapper for dependent or effectful defaults",
                        );
                }
            }
        }
        self.scope = old_scope;
        self.result = old_result;
        self.function = old_function;
    }

    fn closed_interface_default(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::Bool(_) | ExprKind::Number(_) | ExprKind::Unit => true,
            ExprKind::Name(nm) => {
                nm == "none"
                    && self.info_of(e).is_some_and(|i| {
                        i.binding.is_none()
                            && i.constructor.as_ref().is_some_and(|c| c.is_std("Optional"))
                            && i.case.is_some_and(|c| c == "none")
                    })
            }
            ExprKind::Text(parts) => parts.iter().all(|p| matches!(p, TextPart::Lit(_))),
            ExprKind::Call { callee, args } => {
                let ExprKind::Member { left, .. } = &callee.kind else {
                    return false;
                };
                args.is_empty()
                    && self.info_of(callee).is_some_and(|i| {
                        i.method
                            .as_ref()
                            .is_some_and(|m| m.native == "to_bytes" && m.receiver.id == "String")
                    })
                    && self.closed_interface_default(left)
            }
            _ => false,
        }
    }
}

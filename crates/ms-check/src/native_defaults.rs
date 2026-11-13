//! Default expressions of native standard declarations

use crate::checker::Checker;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;

impl Checker {
    /// Checks the default expressions of one native standard callable, recording what each
    /// resolves to for lowering.
    pub(crate) fn check_native_defaults(
        &mut self,
        d: &FuncRef,
        params: &[ms_syntax::ast::Param],
        t: &Ty,
        variables: &[Ty],
        contract: bool,
    ) {
        if params.iter().all(|p| p.default.is_none()) {
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
        self.scope = old_scope;
        self.result = old_result;
        self.function = old_function;
        let form = |c: &Checker, e: &Expr| c.m().default_form(c.syms, e);
        // `none` defaults keep the allocation-free Optional adapter; anything else is prepared
        // by lowering before native dispatch.
        let extended: Vec<&Expr> = params
            .iter()
            .filter_map(|p| p.default.as_ref())
            .filter(|e| form(self, e) != DefaultForm::None)
            .collect();
        if extended.is_empty() {
            return;
        }
        // Keep this first native-default slice bounded. Source generic defaults and
        // generic calls through nongeneric standard contracts retain their existing
        // rules; native generic expression defaults need a substitution design.
        let closed = extended.iter().all(|e| {
            matches!(
                e.kind,
                ExprKind::Bool(_) | ExprKind::Number(_) | ExprKind::Unit
            )
        });
        if !variables.is_empty() && !closed {
            self.type_error(
                d.pos(),
                "native generic expression defaults are not supported; keep '= none' on Optional parameters or use a source wrapper",
            );
            return;
        }
        let is_user_type = d.index.is_none() && matches!(d.decl.decl().kind, DeclKind::Type(_));
        if is_user_type && t.result_ty().kind != Kind::Type {
            self.type_error(
                d.pos(),
                "native opaque constructor expression defaults need a delivery/disposal design; keep Optional.none defaults or use a source wrapper",
            );
            return;
        }
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
    }

    fn closed_interface_default(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::Bool(_) | ExprKind::Number(_) | ExprKind::Unit => true,
            ExprKind::Name(_) => self.m().default_form(self.syms, e) == DefaultForm::None,
            ExprKind::Text(parts) => parts.iter().all(|p| matches!(p, TextPart::Lit(_))),
            ExprKind::Call { callee, args } => {
                let ExprKind::Member { left, .. } = &callee.kind else {
                    return false;
                };
                args.is_empty()
                    && self.info_of(callee).is_some_and(|i| {
                        i.method.as_ref().is_some_and(|m| {
                            m.native.is(self.syms, "to_bytes") && m.receiver.is(Builtin::String)
                        })
                    })
                    && self.closed_interface_default(left)
            }
            _ => false,
        }
    }
}

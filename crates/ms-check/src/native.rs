//! Native operations on standard receivers.

use crate::calls::function_arguments;
use crate::checker::Checker;
use crate::exprs::callee_name;
use crate::inference::CallContext;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::rc::Rc;

impl Checker {
    /// Resolves native operations before generic specialization. Only pinned
    /// standard declarations introduce method variables; user contracts retain
    /// their existing nongeneric operation grammar.
    pub(crate) fn native_callable(&mut self, e: &Expr) -> Option<Info> {
        let member = match &e.kind {
            ExprKind::Apply { left, .. } => left.as_ref(),
            _ => e,
        };
        let ExprKind::Member { left, name } = &member.kind else {
            return None;
        };
        if self.type_expression(left).is_some() {
            return None;
        }
        let receiver = self.expression(left, None);
        let rt = receiver.t();
        if invalid_ty(&rt) {
            return Some(Info::of(invalid()));
        }
        if rt.kind == Kind::Record
            && *name != "to_string"
            && fields(&rt).iter().any(|f| f.name == *name)
        {
            return None;
        }
        let methods = self.methods(&rt, *name);
        // A source operation of the same name that takes this many arguments is resolved as a member.
        if let Some((callee, count)) = self.call_arity
            && callee == member.id
            && methods.len() == 1
            && !crate::exprs::accepts_arguments(&methods[0].ty, count)
        {
            return None;
        }
        // Implementations have already specialized their receiver variables. They
        // dispatch through the contract, rather than native receiver operations.
        // A source or interface operation with type parameters of its own is specialized here too.
        let generic = |m: &crate::types::Method| {
            !m.variables.is_empty()
                && (m.native.as_str().is_empty() || m.native == "contract" || m.contract.is_some())
        };
        if methods.len() != 1
            || (!generic(&methods[0])
                && (methods[0].contract.is_some()
                    || methods[0].native.as_str().is_empty()
                    || methods[0].native == "contract"))
        {
            return None;
        }
        let m = methods[0].clone();
        let info = Info {
            ty: Some(m.ty.clone()),
            native: (!m.native.as_str().is_empty()).then_some(m.native),
            method: Some(m),
            no_return: receiver.no_return,
            ..Info::default()
        };
        self.set_info(member, info.clone());
        Some(info)
    }

    /// Specializes a native call's signature from explicit type arguments or
    /// argument and result evidence, recording it on the callee.
    pub(crate) fn specialize_native_call(
        &mut self,
        e: &Expr,
        callee: &Expr,
        args: &[Argument],
        mut info: Info,
        expected: Option<&Ty>,
    ) -> Info {
        let method = info.method.clone().expect("native method");
        let vars = method.variables.clone();
        let signature = info.t();
        let mut context = CallContext {
            result: signature.result_ty(),
            expected: expected.cloned(),
            pos: e.pos,
            conflict: false,
        };
        let mut supplied: Vec<Option<Ty>> = Vec::new();
        let applied = matches!(callee.kind, ExprKind::Apply { .. });
        if let ExprKind::Apply { types, .. } = &callee.kind {
            supplied = self
                .resolve_arguments(types)
                .into_iter()
                .map(Some)
                .collect();
        } else if !vars.is_empty() {
            let mut subst = Subst::new();
            let resolved = function_arguments(args, &signature.params);
            self.infer_arguments(
                &resolved,
                &signature.params,
                &vars,
                &mut subst,
                Some(&mut context),
            );
            supplied = vars.iter().map(|v| subst.get(&v.id).cloned()).collect();
        }
        if supplied.len() >= required_type_arguments(&vars) {
            supplied = complete_type_arguments(&vars, &supplied);
        }
        if method.native.as_str().is_empty() || method.native == "contract" {
            info.type_args = supplied.clone();
        }
        if !vars.is_empty() || applied {
            info.ty =
                Some(self.specialize(&signature, &vars, &supplied, e.pos, &callee_name(callee)));
        }
        if context.conflict {
            let mut t = (*info.t()).clone();
            t.result = Some(invalid());
            info.ty = Some(Rc::new(t));
        }
        self.set_info(callee, info.clone());
        info
    }
}

#[cfg(test)]
#[path = "method_type_defaults_tests.rs"]
mod method_type_defaults_tests;

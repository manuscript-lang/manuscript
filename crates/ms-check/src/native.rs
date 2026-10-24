//! Native operations on standard receivers.

use crate::calls::function_arguments;
use crate::checker::Checker;
use crate::exprs::callee_name;
use crate::inference::CallContext;
use crate::stdlib;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::rc::Rc;

impl Checker {
    /// Applies explicit requirements on the checked receiver. For example,
    /// equality search requires Equal, join requires List[String] or List[Int], and to_set
    /// requires Hashable, without strengthening List's element requirements.
    pub(crate) fn native_receiver_available(&self, receiver: &Ty, name: Name) -> bool {
        let s = substitution(receiver);
        for requirement in stdlib::receiver_requirements(&format!("{}/{}", receiver.id, name)) {
            let Some(actual) = s.get(&requirement.variable.id) else {
                return false;
            };
            let met = requirement.constraints.iter().any(|constraint| {
                if constraint.kind == Kind::Contract {
                    self.satisfies(actual, constraint)
                } else {
                    same(actual, constraint)
                }
            });
            if !met {
                return false;
            }
        }
        true
    }

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
        // Implementations have already specialized their receiver variables. They
        // dispatch through the contract, rather than native receiver operations.
        if methods.len() != 1
            || methods[0].contract.is_some()
            || methods[0].native.as_str().is_empty()
            || methods[0].native == "contract"
        {
            return None;
        }
        let m = methods[0].clone();
        let info = Info {
            ty: Some(m.ty.clone()),
            native: Some(m.native),
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

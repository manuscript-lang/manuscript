//! Generic argument inference and the pieces of
//! callback return inference it shares (`callbacks.go`).

use crate::checker::{CheckedArgument, Checker};
use crate::hints::{arity_mismatch_hint, label_mismatch_hint};
use crate::syntax::*;
use crate::types::Param;
use crate::types::*;
use ms_syntax::Pos;
use ms_syntax::ast::*;

/// A call argument with its label resolved (after
/// `functionArguments`). An empty `name` means no parameter was left for it.
#[derive(Clone, Copy)]
pub(crate) struct Arg<'a> {
    pub pos: Pos,
    pub name: Name,
    pub value: &'a Expr,
}

/// Evidence for inferring a generic call's type arguments from its result.
pub(crate) struct CallContext {
    pub result: Ty,
    pub expected: Option<Ty>,
    pub pos: Pos,
    pub conflict: bool,
}

pub(crate) const CONFLICTING_INFERENCE: &str = "conflicting generic inference; arguments imply different types for one type parameter, so make them the same type or give type arguments explicitly, e.g. f[Int](...)";

/// The function type a callback argument is checked against.
pub(crate) fn callback_context(expected: Option<&Ty>) -> Option<Ty> {
    let mut expected = expected?.clone();
    if expected.is_std("Optional") && expected.args.len() == 1 {
        expected = expected.args[0].clone();
    }
    (expected.kind == Kind::Function).then_some(expected)
}

/// Whether `t` mentions no inference variable and no invalid part.
pub(crate) fn inference_type_known(t: &Ty, variables: &VarSet) -> bool {
    inference_type_resolved(t, variables, false)
}

/// `inference_type_known` for a type that may be absent.
pub(crate) fn inference_known_opt(t: &Option<Ty>, variables: &VarSet) -> bool {
    t.as_ref()
        .is_some_and(|t| inference_type_known(t, variables))
}

/// Whether `t` mentions no inference variable; invalid parts count as resolved
/// when `allow_invalid` is set.
pub(crate) fn inference_type_resolved(t: &Ty, variables: &VarSet, allow_invalid: bool) -> bool {
    if (!allow_invalid && t.id == "<invalid>") || variables.contains(&t.id) {
        return false;
    }
    t.args
        .iter()
        .all(|a| inference_type_resolved(a, variables, allow_invalid))
        && t.params
            .iter()
            .all(|p| inference_type_resolved(&p.ty, variables, allow_invalid))
        && t.result
            .as_ref()
            .is_none_or(|r| inference_type_resolved(r, variables, allow_invalid))
}

/// Keeps valid evidence and mismatches when another part of an argument is
/// invalid. Error markers fill only the variables whose evidence failed.
pub(crate) fn infer_invalid_argument(
    pattern: Option<&Ty>,
    actual: Option<&Ty>,
    vars: &VarSet,
    s: &mut Subst,
) -> bool {
    let (Some(pattern), Some(actual)) = (pattern, actual) else {
        return pattern.is_none() && actual.is_none();
    };
    if vars.contains(&pattern.id) {
        let previous = s.get(&pattern.id).cloned();
        if previous.as_ref().is_none_or(|p| p.id == "<invalid>") {
            s.insert(pattern.id, required_type(actual));
            return true;
        }
        return actual.id == "<invalid>" || same(&previous.expect("previous"), actual);
    }
    if actual.id == "<invalid>" {
        for a in &pattern.args {
            infer_invalid_argument(Some(a), Some(actual), vars, s);
        }
        for p in &pattern.params {
            infer_invalid_argument(Some(&p.ty), Some(actual), vars, s);
        }
        infer_invalid_argument(pattern.result.as_ref(), Some(actual), vars, s);
        return true;
    }
    if pattern.id != actual.id
        || pattern.args.len() != actual.args.len()
        || pattern.params.len() != actual.params.len()
    {
        return false;
    }
    let mut valid = true;
    for (a, b) in pattern.args.iter().zip(&actual.args) {
        if !infer_invalid_argument(Some(a), Some(b), vars, s) {
            valid = false;
        }
    }
    for (p, q) in pattern.params.iter().zip(&actual.params) {
        if p.name != q.name {
            valid = false;
        }
        if !infer_invalid_argument(Some(&p.ty), Some(&q.ty), vars, s) {
            valid = false;
        }
    }
    infer_invalid_argument(pattern.result.as_ref(), actual.result.as_ref(), vars, s) && valid
}

impl Checker {
    /// Records one callback return against the frame being inferred.
    pub(crate) fn return_add(&mut self, typ: &Ty, pos: Pos) {
        if !inference_type_known(typ, &self.inference_variables) {
            if let Some(r) = self.return_inference.as_mut() {
                r.unresolved = true;
            }
            return;
        }
        if typ.id == "Never" {
            return;
        }
        let Some(r) = self.return_inference.as_mut() else {
            return;
        };
        let Some(previous) = r.ty.clone() else {
            r.ty = Some(typ.clone());
            return;
        };
        if !same(typ, &previous) {
            r.context_dependent = true;
            let msg = format!(
                "callback returns require the same type: {}; make every return in the callback produce one type",
                format_mismatch(typ, &previous)
            );
            self.type_error(pos, msg);
        }
    }

    /// Infers ordinary arguments first, then uses the expected result to
    /// complete missing evidence before checking callbacks whose input types
    /// are known. Callback results supply evidence for generic result
    /// variables. Deferred callbacks are revisited when another argument
    /// provides their input context.
    pub(crate) fn infer_arguments(
        &mut self,
        args: &[Arg],
        params: &[Param],
        variables: &[Ty],
        s: &mut Subst,
        context: Option<&mut CallContext>,
    ) {
        let vars = variable_set(variables);
        let mut pending: Vec<Arg> = Vec::new();
        for arg in args {
            if matches!(arg.value.kind, ExprKind::Lambda(_)) {
                pending.push(*arg);
            } else if !self.contextual(arg.value)
                && let Some(actual) = self.independent_argument(arg.value)
            {
                self.contribute(arg, &actual, params, &vars, s);
            }
        }
        if let Some(c) = context {
            self.infer_expected_result(variables, s, c);
        }
        while !pending.is_empty() {
            let mut progress = false;
            let mut next: Vec<Arg> = Vec::new();
            for arg in &pending {
                let pattern = parameter_type(params, arg.name).map(|p| sub(&p, s));
                let callback = callback_context(pattern.as_ref());
                let ExprKind::Lambda(lambda) = &arg.value.kind else {
                    continue;
                };
                let known = lambda.params.iter().enumerate().all(|(index, param)| {
                    param.ty.is_some()
                        || callback.as_ref().is_some_and(|c| {
                            c.params.len() == lambda.params.len()
                                && inference_type_known(&c.params[index].ty, &vars)
                        })
                });
                if !known {
                    next.push(*arg);
                    continue;
                }
                let previous = self.inference_variables.clone();
                self.inference_variables.extend(vars.iter().copied());
                let checkpoint = self.p.diagnostics.len();
                let actual = self.infer(arg.value, pattern.as_ref());
                // Retain complete probe evidence, including root diagnostics. Invalid
                // slots may be reused only if the final signature has the same slots;
                // new concrete context forces a fresh check in argument_expression.
                // Even a complete signature may need rechecking after deferred returns
                // or try; they can become valid under the inferred enclosing result.
                let resolved = actual
                    .ty
                    .as_ref()
                    .is_some_and(|t| inference_type_resolved(t, &self.inference_variables, true));
                if resolved
                    && (!actual.inference_deferred || invalid_type(&actual.ty))
                    && self.checked_arguments.is_some()
                {
                    let diagnostics = self.p.diagnostics[checkpoint..].to_vec();
                    if let Some(checked) = self.checked_arguments.as_mut() {
                        checked.insert(
                            arg.value.id,
                            CheckedArgument {
                                info: Some(actual.clone()),
                                diagnostics,
                            },
                        );
                    }
                }
                self.inference_variables = previous;
                if self.p.diagnostics.len() != checkpoint {
                    self.p.diagnostics.truncate(checkpoint);
                    if !inference_known_opt(&actual.ty, &vars) && !invalid_type(&actual.ty) {
                        next.push(*arg);
                        continue;
                    }
                }
                self.contribute(arg, &actual, params, &vars, s);
                progress = true;
            }
            if !progress {
                break;
            }
            pending = next;
        }
    }

    fn contribute(
        &mut self,
        arg: &Arg,
        actual: &Info,
        params: &[Param],
        vars: &VarSet,
        s: &mut Subst,
    ) {
        let Some(mut pattern) = parameter_type(params, arg.name) else {
            return;
        };
        let actual_ty = actual.t();
        if invalid_ty(&actual_ty) {
            if pattern.is_std("Optional") && actual_ty.kind == Kind::Function {
                pattern = pattern.args[0].clone();
            }
            if !infer_invalid_argument(Some(&pattern), Some(&actual_ty), vars, s) {
                self.type_error(arg.pos, CONFLICTING_INFERENCE);
            }
            return;
        }
        let substituted = sub(&pattern, s);
        if self.error_assignable(&actual_ty, &substituted)
            || self.unify_argument(&pattern, &actual_ty, vars, s)
        {
            return;
        }
        let mut hint = label_mismatch_hint(&actual_ty, &substituted);
        if hint.is_empty() && mentions_variable(&pattern, vars) {
            hint = arity_mismatch_hint(&actual_ty, &substituted);
        }
        if !hint.is_empty() {
            self.type_error(arg.pos, format!("callback mismatch: {hint}"));
            self.unknown_type = true;
            self.label_mismatch = true;
            return;
        }
        // A pattern without type variables has nothing to conflict; the
        // argument check reports the plain mismatch.
        if mentions_variable(&pattern, vars) {
            self.type_error(arg.pos, CONFLICTING_INFERENCE);
        }
    }

    /// Result evidence is transactional and invariant. A failed structural match
    /// must not commit the prefix it happened to match. The only widening here
    /// is the same explicit Error boundary checked after ordinary expression
    /// inference.
    fn infer_expected_result(
        &mut self,
        variables: &[Ty],
        s: &mut Subst,
        context: &mut CallContext,
    ) {
        if invalid_type(&context.expected) {
            // Keep usable parts of a failed annotation and poison only the result
            // variables whose evidence is invalid; the resolution error owns them.
            infer_invalid_argument(
                Some(&context.result),
                context.expected.as_ref(),
                &variable_set(variables),
                s,
            );
            return;
        }
        let Some(expected) = context.expected.clone() else {
            return;
        };
        if !inference_type_known(&expected, &self.inference_variables)
            || invalid_ty(&context.result)
        {
            return;
        }
        if variables.iter().all(|v| s.contains_key(&v.id)) {
            return; // Keep argument evidence; ordinary result checking reports mismatches.
        }
        let vars = variable_set(variables);
        let mut trial = s.clone();
        let result = sub(&context.result, s);
        let mut matched = unify(&context.result, &expected, &vars, &mut trial);
        if !matched
            && result.is_std("Result")
            && expected.is_std("Result")
            && result.args.len() == 2
            && expected.args.len() == 2
            && self.error_assignable(&result.args[1], &expected.args[1])
        {
            trial = s.clone();
            matched = unify(
                &context.result.args[0],
                &expected.args[0],
                &vars,
                &mut trial,
            );
        }
        if !matched && self.error_assignable(&result, &expected) {
            return; // Existing concrete error evidence needs no substitution.
        }
        if !matched {
            self.type_error(
                context.pos,
                format!(
                    "conflicting generic inference; expected result type {expected} does not match {result}; give consistent argument and result types or specify the type arguments"
                ),
            );
            context.conflict = true;
            for v in variables {
                s.entry(v.id).or_insert_with(invalid);
            }
            return;
        }
        for (key, value) in trial {
            s.insert(key, value);
        }
    }

    /// Only complete, independently typed arguments contribute inference
    /// evidence. Context-dependent arguments are checked again against the
    /// inferred signature.
    pub(crate) fn independent_argument(&mut self, e: &Expr) -> Option<Info> {
        let checkpoint = self.p.diagnostics.len();
        let info = self.expression(e, None);
        if self.p.diagnostics.len() != checkpoint {
            self.p.diagnostics.truncate(checkpoint);
            return None;
        }
        if let Some(checked) = self.checked_arguments.as_mut() {
            checked.insert(
                e.id,
                CheckedArgument {
                    info: Some(info.clone()),
                    diagnostics: Vec::new(),
                },
            );
        }
        Some(info)
    }

    /// Matches exactly before trying the existing Result error widening or a
    /// single Optional argument wrapper. Result successes and nested
    /// applications remain invariant. Each attempt commits substitutions only
    /// after its whole boundary is valid; final argument checking retains the
    /// selected Error evidence.
    pub(crate) fn unify_argument(
        &self,
        pattern: &Ty,
        actual: &Ty,
        vars: &VarSet,
        s: &mut Subst,
    ) -> bool {
        let fresh = |s: &Subst| -> Subst {
            // A prior failed argument supplies no constraint on later evidence.
            s.iter()
                .filter(|(_, v)| !invalid_ty(v))
                .map(|(k, v)| (*k, v.clone()))
                .collect()
        };
        let attempt = |target: &Ty, s: &mut Subst| -> bool {
            let mut trial = fresh(s);
            if !unify(target, actual, vars, &mut trial) {
                if !target.is_std("Result")
                    || !actual.is_std("Result")
                    || target.args.len() != 2
                    || actual.args.len() != 2
                {
                    return false;
                }
                trial = fresh(s);
                if !unify(&target.args[0], &actual.args[0], vars, &mut trial)
                    || !self.error_assignable(actual, &sub(target, &trial))
                {
                    return false;
                }
            }
            for (key, value) in trial {
                s.insert(key, value);
            }
            true
        };
        if attempt(pattern, s) {
            return true;
        }
        pattern.is_std("Optional")
            && pattern.args.len() == 1
            && (self.error_assignable(actual, &sub(&pattern.args[0], s))
                || attempt(&pattern.args[0], s))
    }
}

fn parameter_type(params: &[Param], name: Name) -> Option<Ty> {
    params.iter().find(|p| p.name == name).map(|p| p.ty.clone())
}

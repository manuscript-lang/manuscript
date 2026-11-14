//! Calls, constructors, specialization.

use crate::checker::Checker;
use crate::exprs::{callee_name, is_plain_literal};
use crate::fxmap::{HashMap, HashSet};
use crate::hints::*;
use crate::inference::*;
use crate::stdlib::constructor_signature;
use crate::stmts::case_names;
use crate::suggestions;
use crate::syntax::*;
use crate::types::*;
use crate::types::{Case, Param};
use ms_syntax::Cause;
use ms_syntax::Pos;
use ms_syntax::ast::*;

/// Resolves labels without changing source syntax or written evaluation order.
/// Only an explicit `name: value` selects a named parameter. Every other value,
/// including a bare identifier, fills the first parameter not supplied by an
/// earlier argument.
pub(crate) fn function_arguments<'a>(
    syms: ms_syntax::Names,
    args: &'a [Argument],
    params: &[Param],
) -> Vec<Arg<'a>> {
    bind_arguments(syms, args, params, true)
}

fn parameter_indices(params: &[Param]) -> HashMap<Name, usize> {
    // Keep the first declaration for malformed signatures, just as the old lookup did.
    let mut indices = HashMap::with_capacity_and_hasher(params.len(), Default::default());
    for (index, param) in params.iter().enumerate() {
        indices.entry(param.name).or_insert(index);
    }
    indices
}

fn bind_arguments<'a>(
    syms: ms_syntax::Names,
    args: &'a [Argument],
    params: &[Param],
    positional: bool,
) -> Vec<Arg<'a>> {
    let by_name = parameter_indices(params);
    let mut seen = vec![false; params.len()];
    let mut next = 0;
    let mut resolved = Vec::with_capacity(args.len());
    for a in args {
        let mut name = a.name.unwrap_or_else(|| n(""));
        let parameter = if syms.str(name).is_empty() && positional {
            while next < params.len() && seen[by_name[&params[next].name]] {
                next += 1;
            }
            params.get(next).map(|p| {
                name = p.name;
                by_name[&name]
            })
        } else {
            by_name.get(&name).copied()
        };
        if let Some(index) = parameter {
            seen[index] = true;
        }
        resolved.push(Arg {
            pos: a.pos,
            name,
            parameter,
            value: &a.value,
            mutable: a.mutable,
        });
    }
    resolved
}

/// Constructors use the same binding rule as functions.
fn constructor_arguments<'a>(
    syms: ms_syntax::Names,
    args: &'a [Argument],
    params: &[Param],
) -> Vec<Arg<'a>> {
    function_arguments(syms, args, params)
}

fn slots(args: &[Arg]) -> Option<Vec<crate::syntax::ArgSlot>> {
    Some(
        args.iter()
            .enumerate()
            .map(|(index, a)| crate::syntax::ArgSlot {
                pos: a.pos,
                name: a.name,
                index,
            })
            .collect(),
    )
}

fn unknown_argument_hint(
    syms: ms_syntax::Names,
    name: &str,
    callee: &str,
    params: &[Param],
) -> String {
    if !params.is_empty() && params.iter().all(|p| p.positional) {
        let types: Vec<String> = params
            .iter()
            .map(|p| p.ty.display(syms).to_string())
            .collect();
        return format!(
            "; function values take positional arguments ({}), so pass them without labels",
            types.join(", ")
        );
    }
    let hint = did_you_mean(name, &names_of(syms, params));
    if !hint.is_empty() {
        return hint;
    }
    if params.is_empty() {
        return "; this call takes no arguments".to_string();
    }
    let in_callee = if callee.is_empty() {
        String::new()
    } else {
        format!(" of {callee}")
    };
    format!(
        "; parameters{in_callee}: {}",
        list(&names_of(syms, params), 12)
    )
}

fn missing_argument_hint(
    syms: ms_syntax::Names,
    param: &Param,
    position: usize,
    callee: &str,
) -> String {
    let in_callee = if callee.is_empty() {
        String::new()
    } else {
        format!(" in call to {callee}")
    };
    if param.positional {
        return format!(
            "{position}: {}{in_callee}; pass it positionally, without a label",
            param.ty.display(syms)
        );
    }
    format!(
        "{}: {}{in_callee}; add '{}: <{}>'",
        syms.str(param.name),
        param.ty.display(syms),
        syms.str(param.name),
        param.ty.display(syms)
    )
}

fn with_result(t: &Ty, result: Ty) -> Ty {
    let mut r = (**t).clone();
    r.result = Some(result);
    std::rc::Rc::new(r)
}

impl Checker {
    /// Checks a call. `callee` is the called expression; for the use of a
    /// constant it is the name itself and `const_use` is set.
    pub(crate) fn call(
        &mut self,
        e: &Expr,
        callee: &Expr,
        args: &[Argument],
        const_use: bool,
        expected: Option<&Ty>,
    ) -> Info {
        // Argument checks belong to this call only. Nested calls own
        // their own evidence; callback reuse also requires the same final context.
        let previous = self.checked_arguments.replace(HashMap::default());
        let outer_arity = self.call_arity.take();
        self.call_arity =
            matches!(callee.kind, ExprKind::Member { .. }).then_some((callee.id, args.len()));
        let info = self.call_checked(e, callee, args, const_use, expected);
        self.call_arity = outer_arity;
        self.checked_arguments = previous;
        info
    }

    fn call_checked(
        &mut self,
        e: &Expr,
        callee: &Expr,
        args: &[Argument],
        const_use: bool,
        expected: Option<&Ty>,
    ) -> Info {
        let mut i = Info::default();
        if let Some(mut typ) = self.type_expression(callee) {
            if typ.kind == Kind::Primitive || typ.kind == Kind::Variable {
                if self.rejected_names.contains(&typ.name) {
                    // The declaration reusing this built-in name is already rejected.
                    i.ty = Some(invalid());
                    return i;
                }
                self.type_error(
                    e.pos,
                    format!("this type has no source constructor: {typ_t} is built in; write a literal or call a standard function that returns it{}", builtin_constructor_hint(self.syms, &typ), typ_t = typ.display(self.syms)),
                );
                return i;
            }
            if typ.kind == Kind::Contract {
                for a in args {
                    self.expression(&a.value, None);
                }
                let msg = self.interface_construction_message(&typ);
                self.type_error(e.pos, msg);
                return i;
            }
            if typ.kind == Kind::Alternative {
                self.type_error(
                    e.pos,
                    format!(
                        "construct an alternative case rather than its type; call one of {}'s cases: {}",
                        self.syms.str(typ.name),
                        list(&case_names(self.syms, &typ), 8)
                    ),
                );
                return i;
            }
            self.opaque_denied(e.pos, &typ, "it cannot be constructed here");
            let mut fields = constructor_signature(self.syms, &self.session, &typ)
                .params
                .clone();
            if [
                "BigInt",
                "Regex",
                "Decimal",
                "HttpHeaders",
                "IpAddress",
                "Cidr",
            ]
            .iter()
            .any(|name| typ.is_std(self.syms, name))
            {
                self.type_error(
                    e.pos,
                    format!("standard type has no source constructor: {typ_t}; create it with a literal or the standard function documented for it (ms doc)", typ_t = typ.display(self.syms)),
                );
                return i;
            }
            // `reserve` is named-only: `List[T](n)` stays an error.
            let named_only = typ.is(Builtin::List) && args.iter().any(|a| a.name.is_none());
            let mut resolved = bind_arguments(self.syms, args, &fields, !named_only);
            i.arguments = slots(&resolved);
            typ = self.instantiate(&typ, &fields, &resolved, expected, e.pos);
            let signature = constructor_signature(self.syms, &self.session, &typ);
            // Invalid type arity can recover to a different constructor signature.
            // Retain the original labels/positional errors and written slots, but
            // check those names against the recovered signature as before.
            if fields
                .iter()
                .map(|p| p.name)
                .ne(signature.params.iter().map(|p| p.name))
            {
                let indices = parameter_indices(&signature.params);
                for arg in &mut resolved {
                    arg.parameter = indices.get(&arg.name).copied();
                }
            }
            fields = signature.params.clone();
            if typ.is(Builtin::Set) && args.is_empty() {
                fields.clear();
            }
            i.no_return = self.arguments_for(
                self.syms.str(typ.name),
                e.pos,
                &resolved,
                &fields,
                &signature.defaults,
            );
            i.ty = Some(typ.clone());
            i.constructor = Some(typ);
            return i;
        }
        let mut alternative: Option<Ty> = None;
        let mut cs: Option<Case> = None;
        if let ExprKind::Member { left, name } = &callee.kind {
            alternative = self.type_expression(left);
            if let Some(alt) = &alternative {
                if alt.kind == Kind::Contract {
                    let msg = self.interface_type_member(alt);
                    self.res_error(e.pos, msg);
                    return i;
                }
                if alt.is(Builtin::Optional) {
                    self.res_error(
                        e.pos,
                        "Optional has no qualified cases; write none or the plain value where a T? is expected, and put the type on the binding, e.g. x: Int? := none",
                    );
                    return i;
                }
                cs = case_of(alt, *name);
                if cs.is_none() && case_names(self.syms, alt).is_empty() {
                    self.res_error(
                        e.pos,
                        format!(
                            "{} has no cases or static members, so `{}.{name_t}(...)` does not exist; if {name_t} is a module function, import it and call {name_t}(...); if it is a method, call it on a value",
                            self.syms.str(alt.name), self.syms.str(alt.name)
                        , name_t = self.syms.str(name)),
                    );
                    return i;
                }
                if cs.is_none() {
                    self.res_error(
                        e.pos,
                        format!(
                            "unknown alternative case {name_t} of {}; cases: {}",
                            self.syms.str(alt.name),
                            list(&case_names(self.syms, alt), 8),
                            name_t = self.syms.str(name)
                        ),
                    );
                    return i;
                }
            }
        }
        if let ExprKind::Name(name) = &callee.kind
            && self.unbound(*name)
        {
            let (found, case, ambiguous) = self.find_case(*name, callee.pos);
            if ambiguous {
                i.ty = Some(invalid());
                return i;
            }
            alternative = found;
            cs = case;
        }
        if let (Some(alt), Some(cs)) = (alternative, cs) {
            if alt.is(Builtin::Optional) && self.syms.str(cs.name) == "some" {
                self.type_error(
                    e.pos,
                    "there is no some(...); a plain value converts where a T? is expected, so pass it directly, or annotate the binding, e.g. x: Int? := 5",
                );
                i.ty = Some(invalid());
                return i;
            }
            self.opaque_denied(
                e.pos,
                &alt,
                &format!("case {} cannot be built here", self.syms.str(cs.name)),
            );
            if cs.fields.is_empty() {
                let fix = suggestions::drop_case_parens(
                    &self.m().source,
                    callee.pos,
                    self.syms.str(cs.name),
                );
                self.type_error_with_fix(
                    e.pos,
                    Cause::Other,
                    format!(
                        "nullary cases omit call parentheses; write {0} instead of {0}()",
                        self.syms.str(cs.name)
                    ),
                    fix,
                );
            }
            let resolved = constructor_arguments(self.syms, args, &cs.fields);
            i.arguments = slots(&resolved);
            let alt = self.instantiate(&alt, &cs.fields, &resolved, expected, e.pos);
            let cs = case_of(&alt, cs.name).unwrap_or(cs);
            i.no_return =
                self.arguments_for(self.syms.str(cs.name), e.pos, &resolved, &cs.fields, &None);
            i.ty = Some(alt.clone());
            i.constructor = Some(alt);
            i.case = Some(cs.name);
            return i;
        }
        let mut symbol = None;
        let mut supplied: Vec<Option<Ty>> = Vec::new();
        let mut explicit = false;
        if let ExprKind::Apply { left, types, .. } = &callee.kind {
            symbol = self.function_symbol(left);
            if symbol.is_some() {
                supplied = self
                    .resolve_arguments(types)
                    .into_iter()
                    .map(Some)
                    .collect();
                explicit = true;
            }
        } else {
            symbol = symbol.or_else(|| self.function_symbol(callee));
        }
        let signature: Option<Ty>;
        let callable: Info;
        // Where this call reported that a type argument cannot be inferred.
        let mut undetermined: Option<usize> = None;
        if let Some(s) = symbol.as_ref().filter(|s| s.is_constant() && !const_use) {
            self.type_error(
                e.pos,
                format!(
                    "{} is a constant, not a function; remove the parentheses and write {}",
                    self.syms.str(s.name),
                    self.syms.str(s.name)
                ),
            );
            i.ty = Some(invalid());
            return i;
        }
        if let Some(s) = symbol {
            i.symbol = Some(s.clone());
            i.native = s.native;
            let mut sig = s.ty(self.syms);
            let vars = s.variables();
            if !vars.is_empty() {
                let mut context = CallContext {
                    result: sig.result_ty(),
                    expected: expected.cloned(),
                    pos: e.pos,
                    conflict: false,
                };
                if !explicit {
                    let mut subst = Subst::default();
                    let params = sig.params.clone();
                    let resolved = function_arguments(self.syms, args, &params);
                    self.infer_arguments(&resolved, &params, &vars, &mut subst, Some(&mut context));
                    for v in &vars {
                        supplied.push(subst.get(&v.id).cloned());
                    }
                }
                if supplied.len() >= required_type_arguments(&vars) {
                    supplied = complete_type_arguments(&vars, &supplied);
                }
                let before = self.p.diagnostics.len();
                sig = self.specialize(
                    &sig,
                    &vars,
                    &supplied,
                    e.pos,
                    &callee_name(self.syms, callee),
                );
                if self.p.diagnostics[before..]
                    .first()
                    .is_some_and(|d| d.cause == Cause::CannotInferTypeArgument)
                {
                    undetermined = Some(before);
                }
                if context.conflict {
                    sig = with_result(&sig, invalid());
                }
                i.type_args = supplied;
            } else if explicit && !supplied.is_empty() {
                self.type_error(
                    e.pos,
                    format!(
                        "nongeneric function cannot take type arguments; remove the [...] after {}",
                        self.syms.str(s.name)
                    ),
                );
            }
            callable = Info {
                ty: Some(sig.clone()),
                symbol: Some(s),
                ..Info::default()
            };
            self.set_info(callee, callable.clone());
            signature = Some(sig);
        } else {
            let mut c = match self.native_callable(callee) {
                Some(c) => c,
                None => {
                    let c = self.expression(callee, None);
                    i.method = c.method.clone();
                    if c.native_str(self.syms) != "index" {
                        // An indexed callee (callbacks[0](2)) must not make the call itself lower as an index.
                        i.native = c.native;
                    }
                    signature = c.ty.clone();
                    callable = c;
                    return self.finish_call(e, callee, args, i, signature, callable);
                }
            };
            if c.t().is_invalid() {
                for arg in args {
                    self.expression(&arg.value, None);
                }
                return c;
            }
            c = self.specialize_native_call(e, callee, args, c, expected);
            i.method = c.method.clone();
            i.type_args = c.type_args.clone();
            if c.native_str(self.syms) != "index" {
                i.native = c.native;
            }
            signature = c.ty.clone();
            callable = c;
        }
        let info = self.finish_call(e, callee, args, i, signature, callable);
        if let Some(at) = undetermined
            && self.p.diagnostics[at + 1..]
                .iter()
                .any(|d| d.cause != Cause::CannotInferCallback)
        {
            // An argument reported its own error (an empty literal with no type): the type
            // argument it left undetermined is that error's consequence, so the argument's
            // diagnostic stands alone. A callback parameter left without a type is the other
            // direction: the undetermined type argument is why, so both stay.
            self.p.diagnostics.remove(at);
        }
        info
    }

    fn finish_call(
        &mut self,
        e: &Expr,
        callee: &Expr,
        args: &[Argument],
        mut i: Info,
        signature: Option<Ty>,
        callable: Info,
    ) -> Info {
        if let Some(sig) = &signature
            && sig.is_invalid()
        {
            i.ty = Some(sig.clone());
            return i;
        }
        let Some(sig) = signature.filter(|s| s.kind == Kind::Function) else {
            let t = callable.ty.clone();
            self.not_callable(e, callee, t.as_ref());
            return i;
        };
        let resolved = function_arguments(self.syms, args, &sig.params);
        i.arguments = slots(&resolved);
        i.no_return = callable.no_return
            || self.arguments_for(
                &callee_name(self.syms, callee),
                e.pos,
                &resolved,
                &sig.params,
                &sig.defaults,
            );
        let result = sig.result_ty();
        i.ty = Some(if invalid_ty(&result) {
            invalid()
        } else {
            result.clone()
        });
        if result.is_never() {
            i.no_return = true;
        }
        i
    }

    /// Checks a call to the named callable. A missing argument is reported at
    /// the call, not at the module start, and names the callee.
    fn arguments_for(
        &mut self,
        name: &str,
        pos: Pos,
        args: &[Arg],
        params: &[Param],
        defaults: &Defaults,
    ) -> bool {
        self.call_name = name.to_string();
        self.call_pos = Some(pos);
        self.arguments(args, params, defaults)
    }

    /// Reports a call whose callee has no function type. An invalid callee was
    /// already reported where it was written.
    fn not_callable(&mut self, e: &Expr, callee: &Expr, t: Option<&Ty>) {
        if t.is_none()
            && let ExprKind::Name(name) = &callee.kind
            && self.unbound(*name)
        {
            return;
        }
        if t.is_some_and(invalid_ty) {
            return;
        }
        self.unknown_type = true;
        let mut message = match callee_name(self.syms, callee) {
            name if !name.is_empty() => format!("{name} is not a function"),
            _ => "callee is not a function".to_string(),
        };
        if let Some(t) = t {
            message.push_str(&format!(" (it has type {t_t})", t_t = t.display(self.syms)));
        }
        self.type_error(
            e.pos,
            format!("{message}; only functions and methods can be called, so remove the (...) or call a function instead"),
        );
    }

    fn arguments(&mut self, args: &[Arg], params: &[Param], defaults: &Defaults) -> bool {
        let call_name = std::mem::take(&mut self.call_name);
        let call_pos = self.call_pos.take();
        let mut seen: HashSet<Name> = HashSet::default();
        let mut no_return = false;
        for arg in args {
            if self.syms.str(arg.name).is_empty() {
                self.type_error(
                    arg.pos,
                    "too many positional arguments; every parameter is already supplied, so remove this argument",
                );
                let v = self.expression(arg.value, None);
                no_return = no_return || v.no_return;
                continue;
            }
            if seen.contains(&arg.name) {
                self.type_error(
                    arg.pos,
                    format!(
                        "duplicate argument {}; pass each argument once",
                        self.syms.str(arg.name)
                    ),
                );
            }
            let expected = arg.parameter.map(|index| params[index].ty.clone());
            if expected.is_none() {
                let hint =
                    unknown_argument_hint(self.syms, self.syms.str(arg.name), &call_name, params);
                self.type_error_name(
                    arg.pos,
                    self.syms.str(arg.name).len(),
                    format!("unknown argument {}{hint}", self.syms.str(arg.name)),
                );
            }
            if expected.is_some() && !call_name.is_empty() {
                self.mismatch_context = Some(format!(
                    "argument '{}' of {call_name}",
                    self.syms.str(arg.name)
                ));
            }
            let checkpoint = self.p.diagnostics.len();
            let v = self.argument_expression(arg.value, expected.as_ref());
            self.mismatch_context = None;
            if self.conflicted_arguments.remove(&arg.value.id) {
                // The argument check names both types and may carry a fix; it replaces the generic conflict note.
                let at = arg.pos;
                let explained = self.p.diagnostics[checkpoint..]
                    .iter()
                    .any(|d| d.pos == at && d.cause == Cause::Mismatch);
                if explained
                    && let Some(i) = self.p.diagnostics[..checkpoint]
                        .iter()
                        .rposition(|d| d.pos == at && d.message == CONFLICTING_INFERENCE)
                {
                    self.p.diagnostics.remove(i);
                }
            }
            if let (Some(want), Some(have)) = (&expected, &v.interface_source)
                && arg.mutable
                && want.kind == Kind::Contract
                && have.kind != Kind::Contract
            {
                self.type_error(
                    arg.value.pos,
                    format!(
                        "parameter {} is a var {want_t}, but this {have_t} would be converted to a temporary {want_t} and the callee's changes would be lost; declare the variable as `var x: {want_t} = ...` or make the parameter take {have_t}",
                        self.syms.str(arg.name)
                    , want_t = want.display(self.syms), have_t = have.display(self.syms)),
                );
            }
            no_return = no_return || v.no_return;
            seen.insert(arg.name);
        }
        for (index, param) in params.iter().enumerate() {
            // An invalid parameter type means an earlier diagnostic already explained this call.
            if param.ty.is_invalid() {
                continue;
            }
            let defaulted = defaults.as_ref().is_some_and(|d| d.contains(&param.name));
            if !seen.contains(&param.name) && !defaulted {
                let pos = call_pos
                    .or_else(|| args.first().map(|a| a.pos))
                    .unwrap_or_else(|| self.module_position());
                self.type_error(
                    pos,
                    format!(
                        "missing argument {}",
                        missing_argument_hint(self.syms, param, index + 1, &call_name)
                    ),
                );
            }
        }
        no_return
    }

    /// Instantiates a generic type from its type arguments, the expected type
    /// and the evidence of the supplied arguments.
    pub(crate) fn specialize(
        &mut self,
        t: &Ty,
        vars: &[Ty],
        args: &[Option<Ty>],
        pos: Pos,
        name: &str,
    ) -> Ty {
        let mut subst = Subst::default();
        let mut args: Vec<Option<Ty>> = args.to_vec();
        if args.len() < vars.len() && args.len() >= required_type_arguments(vars) {
            let mut known = Subst::default();
            for (v, a) in vars.iter().zip(&args) {
                if let Some(a) = a {
                    known.insert(v.id, a.clone());
                }
            }
            for v in &vars[args.len()..] {
                let d = v.default_ty().expect("default exists for omitted argument");
                let a = sub(&d, &known);
                known.insert(v.id, a.clone());
                args.push(Some(a));
            }
        }
        if vars.len() != args.len() {
            self.type_error(
                pos,
                format!(
                    "generic arity mismatch; expected {} type arguments, found {}",
                    vars.len(),
                    args.len()
                ),
            );
        }
        let mut missing: Vec<Name> = Vec::new();
        for (index, v) in vars.iter().enumerate() {
            let mut a = args.get(index).cloned().flatten();
            if a.is_none()
                && let Some(d) = v.default_ty()
            {
                a = Some(sub(&d, &subst));
            }
            let a = match a {
                Some(a) => a,
                None => {
                    missing.push(v.name);
                    invalid()
                }
            };
            subst.insert(v.id, a);
        }
        if !missing.is_empty() && !self.label_mismatch {
            self.type_error_with_cause(
                pos,
                Cause::CannotInferTypeArgument,
                missing_type_argument_hint(self.syms, name, &missing, vars, &args),
            );
        }
        self.label_mismatch = false;
        for v in vars {
            for bound in v.bounds() {
                let actual = subst[&v.id].clone();
                let bound = sub(&bound, &subst);
                if !invalid_ty(&actual) && !self.satisfies(&actual, &bound) {
                    let msg = self.unsatisfied_message(
                        &actual,
                        &bound,
                        "pass a type that already implements it",
                    );
                    self.type_error(pos, msg);
                }
            }
        }
        sub(t, &subst)
    }

    /// Whether an argument is itself a constructor whose type arguments could
    /// not be inferred; that was reported where it is written, so the enclosing
    /// constructor adds nothing.
    fn argument_failed_inference(&self, args: &[Arg]) -> bool {
        args.iter()
            .any(|a| self.unresolved_constructors.contains(&a.value.pos))
    }

    pub(crate) fn instantiate(
        &mut self,
        t: &Ty,
        fields: &[Param],
        args: &[Arg],
        expected: Option<&Ty>,
        pos: Pos,
    ) -> Ty {
        let Some(def) = &t.def else {
            return t.clone();
        };
        // A plain constructor can infer its arguments from a matching Optional payload.
        let expected = expected.map(|exp| {
            if !t.is(Builtin::Optional)
                && exp.is(Builtin::Optional)
                && exp.args.len() == 1
                && exp.args[0].id == t.id
            {
                &exp.args[0]
            } else {
                exp
            }
        });
        let vars = def.variables();
        let mut subst = Subst::default();
        for (index, v) in vars.iter().enumerate() {
            if index < t.args.len() && t.args[index].id != v.id {
                subst.insert(v.id, t.args[index].clone());
            }
        }
        if let Some(exp) = expected
            && exp.id == t.id
            && exp.args.len() == vars.len()
        {
            for (index, v) in vars.iter().enumerate() {
                let arg = &exp.args[index];
                if !subst.contains_key(&v.id)
                    && (inference_type_known(arg, &self.inference_variables) || invalid_ty(arg))
                {
                    subst.insert(v.id, arg.clone());
                }
            }
        }
        let inferred_fields: Vec<Param> = fields
            .iter()
            .map(|f| Param::new(f.name, sub(&f.ty, &subst)))
            .collect();
        self.infer_arguments(args, &inferred_fields, &vars, &mut subst, None);
        let mut actual: Vec<Ty> = Vec::new();
        for v in &vars {
            let mut a = subst.get(&v.id).cloned();
            if a.is_none()
                && let Some(d) = v.default_ty()
            {
                let d = sub(&d, &subst);
                subst.insert(v.id, d.clone());
                a = Some(d);
            }
            let a = match a {
                Some(a) => a,
                None => {
                    // A different expected type is reported as a mismatch (or was reported
                    // already, when it is invalid), so this would only restate it.
                    let elsewhere = expected.is_some_and(|e| {
                        e.id != t.id
                            && ((invalid_ty(e) && self.unknown_type)
                                || (!matches!(e.kind, Kind::Variable | Kind::Contract)
                                    && inference_type_known(e, &self.inference_variables)))
                    });
                    if !elsewhere && !self.argument_failed_inference(args) {
                        let message = if t.is(Builtin::Optional) {
                            "cannot infer the type of none; give it a target, e.g. `x: Int? := none`, or pass a value".to_string()
                        } else {
                            format!(
                                "cannot infer constructor type argument {}; write the type arguments, e.g. Box[Int](...), or annotate the binding",
                                self.syms.str(v.name)
                            )
                        };
                        self.type_error_with_cause(pos, Cause::CannotInfer, message);
                    }
                    self.unresolved_constructors.insert(pos);
                    invalid()
                }
            };
            actual.push(a);
        }
        let r = with_args(t, actual);
        // Argument types came from checked expressions, so only this level's bounds
        // are new; walking the arguments again would make nesting quadratic.
        self.bounds_hold(&r, pos);
        r
    }

    /// Prefers an already optional value. Otherwise checks the payload with its
    /// own context (including empty lists and incomplete data constructors),
    /// then wraps only the supplied argument. Ordinary expression compatibility
    /// stays exact.
    pub(crate) fn argument_expression(&mut self, e: &Expr, expected: Option<&Ty>) -> Info {
        let optional = expected.filter(|x| x.is(Builtin::Optional) && x.args.len() == 1);
        let literal = optional.and_then(|t| {
            let payload = &t.args[0];
            let sized = (int_bits(payload).is_some() && !payload.is(Builtin::Int))
                || (float_bits(payload).is_some() && !payload.is(Builtin::Float));
            (is_plain_literal(self.syms, e) || (sized && self.literal_hint(e, payload).is_some()))
                .then_some(payload)
        });
        let checked = self
            .checked_arguments
            .as_ref()
            .and_then(|m| m.get(&e.id))
            .cloned();
        let mut info = checked.as_ref().and_then(|c| c.info.clone());
        if let (Some(hint), Some(cached)) = (literal, &info)
            && cached.ty.as_ref().is_none_or(|actual| !same(actual, hint))
        {
            // Constructor inference may have checked literal arithmetic without its sized
            // optional payload context. Recheck it before replaying those diagnostics.
            info = None;
        }
        if matches!(e.kind, ExprKind::Lambda(_))
            && info
                .as_ref()
                .is_some_and(|i| !same_opt(&i.ty, &callback_context(expected)))
        {
            info = None; // Later inference changed the callback's required signature.
        }
        if info.is_some()
            && let Some(c) = &checked
        {
            self.p.diagnostics.extend(c.diagnostics.iter().cloned());
        }
        let Some(expected_optional) = optional else {
            return match info {
                Some(i) => self.check_expression(e, i, expected),
                None => self.expression(e, expected),
            };
        };
        let checkpoint = self.p.diagnostics.len();
        let payload = expected_optional.args[0].clone();
        // Literal arithmetic takes the same sized payload context as a single number.
        let info = match info {
            Some(i) => i,
            None => self.infer(e, literal.or(expected)),
        };
        let actual = info.ty.clone();
        if compatible(&actual, expected_optional) {
            return self.check_expression(e, info, expected);
        }
        let payload_ok = compatible(&actual, &payload)
            || actual
                .as_ref()
                .is_some_and(|a| self.interface_assignable(a, &payload));
        if payload_ok {
            let mut info = self.check_expression(e, info, Some(&payload));
            info.optional_argument = Some(expected_optional.clone());
            self.set_info(e, info.clone());
            return info;
        }
        if self.p.diagnostics.len() == checkpoint
            || (info.constructor.is_none()
                && !matches!(e.kind, ExprKind::List(_) | ExprKind::Map(_)))
        {
            return self.check_expression(e, info, expected);
        }
        let diagnostics = self.p.diagnostics[checkpoint..].to_vec();
        self.p.diagnostics.truncate(checkpoint);
        let mut info = self.expression(e, Some(&payload));
        if self.p.diagnostics.len() == checkpoint {
            info.optional_argument = Some(expected_optional.clone());
            self.set_info(e, info.clone());
            return info;
        }
        // Retain the original optional-boundary diagnostics when neither form fits.
        self.p.diagnostics.truncate(checkpoint);
        self.p.diagnostics.extend(diagnostics);
        info
    }
}

#[cfg(test)]
mod argument_tests {
    use super::*;
    use std::sync::Arc;

    fn check(syms: ms_syntax::Names, source: &str) -> crate::Program {
        let session = crate::Session::new();
        session.ensure_standard();
        let file: Arc<str> = Arc::from("arguments.ms");
        let ast = ms_syntax::parser::parse(&file, source).expect("valid syntax");
        Checker::new(&session, &crate::CheckOptions::default())
            .check_modules(vec![crate::load_module(syms, &ast)], None)
    }

    #[test]
    fn resolved_slots_match_left_to_right_binding() {
        let syms = ms_syntax::Names::global();
        let labels = [
            None,
            Some(n("a")),
            Some(n("b")),
            Some(n("c")),
            Some(n("unknown")),
        ];
        // Exhaust mixed, duplicate, unknown and excess arguments, including malformed
        // duplicate parameter declarations and the named-only constructor path.
        for names in [vec![], vec!["a", "b", "c"], vec!["a", "a", "b"]] {
            let params: Vec<_> = names
                .iter()
                .map(|name| Param::new(n(name), invalid()))
                .collect();
            for positional in [false, true] {
                for mut code in 0..5usize.pow(5) {
                    let args: Vec<_> = (0..5)
                        .map(|index| {
                            let name = labels[code % 5];
                            code /= 5;
                            Argument {
                                pos: Pos::new(index, 1, index + 1),
                                name,
                                mutable: false,
                                value: Expr {
                                    id: NodeId(index),
                                    pos: Pos::default(),
                                    end: Pos::default(),
                                    kind: ExprKind::Unit,
                                },
                            }
                        })
                        .collect();
                    let resolved = bind_arguments(syms, &args, &params, positional);
                    let mut seen = HashSet::default();
                    for (index, (arg, actual)) in args.iter().zip(&resolved).enumerate() {
                        let mut expected = arg.name.unwrap_or_else(|| n(""));
                        if syms.str(expected).is_empty()
                            && positional
                            && let Some(p) = params.iter().find(|p| !seen.contains(&p.name))
                        {
                            expected = p.name;
                        }
                        seen.insert(expected);
                        assert_eq!(actual.name, expected);
                        assert_eq!(
                            actual.parameter,
                            params.iter().position(|p| p.name == expected)
                        );
                        assert!(std::ptr::eq(actual.value, &arg.value));
                        assert_eq!(actual.pos, arg.pos);
                        let slot = slots(&resolved).unwrap()[index];
                        assert_eq!(
                            (slot.name, slot.index, slot.pos),
                            (expected, index, arg.pos)
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn mixed_calls_keep_inference_defaults_and_callback_context() {
        let syms = ms_syntax::Names::global();
        let p = check(syms, include_str!("../tests/call_arguments/accepted.ms"));
        assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    }

    #[test]
    fn invalid_calls_keep_diagnostic_order() {
        let syms = ms_syntax::Names::global();
        let p = check(syms, include_str!("../tests/call_arguments/rejected.ms"));
        let messages: Vec<_> = p.diagnostics.iter().map(|d| d.message.as_str()).collect();
        assert_eq!(messages.len(), 5, "{messages:?}");
        for (message, prefix) in messages.iter().zip([
            "duplicate argument second",
            "unknown argument mystery",
            "duplicate argument mystery",
            "unknown argument mystery",
            "too many positional arguments",
        ]) {
            assert!(message.starts_with(prefix), "{messages:?}");
        }
        let p = check(syms, include_str!("../tests/call_arguments/missing.ms"));
        let messages: Vec<_> = p.diagnostics.iter().map(|d| d.message.as_str()).collect();
        assert_eq!(messages.len(), 2, "{messages:?}");
        assert!(messages[0].starts_with("missing argument second"));
        assert!(messages[1].starts_with("missing argument third"));
    }

    #[test]
    fn generic_source_method_value_needs_type_arguments() {
        let syms = ms_syntax::Names::global();
        let source = "type Out:\n    n: Int\nfn Out.put[F](value: F) Int:\n    return 1\nfn bare(o: Out) Unit:\n    g := o.put\nfn fixed(o: Out) Unit:\n    g := o.put[Int]\n    n := o.put(1)\n";
        let p = check(syms, source);
        let messages: Vec<_> = p.diagnostics.iter().map(|d| d.message.as_str()).collect();
        assert_eq!(messages.len(), 1, "{messages:?}");
        assert!(messages[0].starts_with("a generic method value requires"));
        assert_eq!(p.diagnostics[0].pos.line, 6);
    }

    #[test]
    fn named_only_constructor_keeps_labels_and_rejects_positional_arguments() {
        let syms = ms_syntax::Names::global();
        let p = check(syms, include_str!("../tests/call_arguments/named_only.ms"));
        let messages: Vec<_> = p.diagnostics.iter().map(|d| d.message.as_str()).collect();
        assert_eq!(messages.len(), 4, "{messages:?}");
        for (message, prefix) in messages.iter().zip([
            "too many positional arguments",
            "too many positional arguments",
            "unknown argument extra",
            "duplicate argument reserve",
        ]) {
            assert!(message.starts_with(prefix), "{messages:?}");
        }
    }

    #[test]
    fn duplicate_parameter_declaration_does_not_change_call_diagnostics() {
        let syms = ms_syntax::Names::global();
        let p = check(
            syms,
            include_str!("../tests/call_arguments/duplicate_parameters.ms"),
        );
        assert_eq!(p.diagnostics.len(), 1, "{:?}", p.diagnostics);
        assert!(
            p.diagnostics[0]
                .message
                .starts_with("duplicate parameter or field first")
        );
    }

    #[test]
    fn recovered_constructor_signature_keeps_original_argument_names() {
        let syms = ms_syntax::Names::global();
        let p = check(
            syms,
            include_str!("../tests/call_arguments/malformed_constructors.ms"),
        );
        let prefixes = [
            "generic type arity mismatch",
            "generic type arity mismatch",
            "too many positional arguments",
            "missing argument values",
            "generic type arity mismatch",
            "unknown argument extra",
            "missing argument values",
            "generic type arity mismatch",
            "duplicate argument values",
            "generic type arity mismatch",
            "generic type arity mismatch",
            "too many positional arguments",
        ];
        assert_eq!(p.diagnostics.len(), prefixes.len(), "{:?}", p.diagnostics);
        for (diagnostic, prefix) in p.diagnostics.iter().zip(prefixes) {
            assert!(diagnostic.message.starts_with(prefix), "{diagnostic:?}");
        }
    }

    #[test]
    fn wide_calls_infer_each_resolved_slot() {
        let syms = ms_syntax::Names::global();
        let width = 2048;
        let params = (0..width)
            .map(|i| format!("_a{i}: T"))
            .collect::<Vec<_>>()
            .join(", ");
        for labeled in [false, true] {
            let args = (0..width)
                .map(|i| {
                    if labeled {
                        format!("_a{}: 0", width - i - 1)
                    } else {
                        "0".to_string()
                    }
                })
                .collect::<Vec<_>>()
                .join(", ");
            let source = include_str!("../tests/call_arguments/wide.ms")
                .replace("_parameters: T", &params)
                .replace("_arguments", &args);
            let p = check(syms, &source);
            assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
        }
    }
}

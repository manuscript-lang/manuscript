//! Calls, constructors, specialization.

use crate::checker::Checker;
use crate::exprs::callee_name;
use crate::hints::*;
use crate::inference::*;
use crate::stmts::case_names;
use crate::syntax::*;
use crate::types::*;
use crate::types::{Case, Param};
use ms_syntax::Pos;
use ms_syntax::ast::*;
use std::collections::{HashMap, HashSet};

/// Resolves labels without changing source syntax or written evaluation order.
/// Only an explicit `name: value` selects a named parameter. Every other value,
/// including a bare identifier, fills the first parameter not supplied by an
/// earlier argument.
pub(crate) fn function_arguments<'a>(args: &'a [Argument], params: &[Param]) -> Vec<Arg<'a>> {
    let mut seen: HashSet<Name> = HashSet::with_capacity(params.len());
    let mut resolved = Vec::with_capacity(args.len());
    for a in args {
        let mut name = a.name.unwrap_or_else(|| n(""));
        if name.as_str().is_empty()
            && let Some(p) = params.iter().find(|p| !seen.contains(&p.name))
        {
            name = p.name;
        }
        seen.insert(name);
        resolved.push(Arg {
            pos: a.pos,
            name,
            value: &a.value,
        });
    }
    resolved
}

/// Constructors use the same binding rule as functions.
fn constructor_arguments<'a>(args: &'a [Argument], params: &[Param]) -> Vec<Arg<'a>> {
    function_arguments(args, params)
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

fn unknown_argument_hint(name: &str, callee: &str, params: &[Param]) -> String {
    let hint = did_you_mean(name, &names_of(params));
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
    format!("; parameters{in_callee}: {}", list(&names_of(params), 12))
}

fn missing_argument_hint(param: &Param, callee: &str) -> String {
    let in_callee = if callee.is_empty() {
        String::new()
    } else {
        format!(" in call to {callee}")
    };
    format!(
        ": {}{in_callee}; add '{}: <{}>'",
        param.ty, param.name, param.ty
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
        let previous = self.checked_arguments.replace(HashMap::new());
        let info = self.call_checked(e, callee, args, const_use, expected);
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
                    format!("this type has no source constructor: {typ} is built in; write a literal or call a standard function that returns it"),
                );
                return i;
            }
            if typ.kind == Kind::Contract {
                typ = self.instantiate(&typ, &[], &[], expected, e.pos);
                let value = [Param {
                    name: n("value"),
                    ty: invalid(),
                }];
                let resolved = constructor_arguments(args, &value);
                i.arguments = slots(&resolved);
                if resolved.len() != 1 || resolved[0].name != "value" {
                    self.type_error(
                        e.pos,
                        format!("contract view requires exactly one receiver; write {typ}(x) or {typ}(value: x)"),
                    );
                    return i;
                }
                let receiver = self.expression(&args[0].value, None);
                if !self.implements(&receiver.t(), &typ) {
                    self.type_error(
                        e.pos,
                        format!(
                            "{} does not implement {typ}; declare 'impl {typ} for {}:' with every operation of the interface",
                            receiver.t(),
                            receiver.t()
                        ),
                    );
                }
                i.ty = Some(typ.clone());
                i.constructor = Some(typ);
                i.native = Some(n("view"));
                i.no_return = receiver.no_return;
                return i;
            }
            if typ.kind == Kind::Alternative {
                self.type_error(
                    e.pos,
                    format!(
                        "construct an alternative case rather than its type; call one of {}'s cases: {}",
                        typ.name,
                        list(&case_names(&typ), 8)
                    ),
                );
                return i;
            }
            let mut fields = constructor_signature(&typ).params.clone();
            if [
                "BigInt",
                "Regex",
                "Timestamp",
                "Instant",
                "Duration",
                "Decimal",
                "HttpHeaders",
                "IpAddress",
                "Cidr",
            ]
            .iter()
            .any(|name| typ.is_std(name))
            {
                self.type_error(
                    e.pos,
                    format!("standard type has no source constructor: {typ}; create it with a literal or the standard function documented for it (ms doc)"),
                );
                return i;
            }
            // `reserve` is named-only: `List[T](n)` stays an error.
            let named_only = typ.is_std("List") && args.iter().any(|a| a.name.is_none());
            let resolved = constructor_arguments(args, if named_only { &[] } else { &fields });
            i.arguments = slots(&resolved);
            typ = self.instantiate(&typ, &fields, &resolved, expected, e.pos);
            let signature = constructor_signature(&typ);
            fields = signature.params.clone();
            if typ.is_std("Set") && args.is_empty() {
                fields.clear();
            }
            i.no_return = self.arguments_for(
                typ.name.as_str(),
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
                cs = case_of(alt, *name);
                if cs.is_none() {
                    self.res_error(
                        e.pos,
                        format!(
                            "unknown alternative case {name} of {}; cases: {}",
                            alt.name,
                            list(&case_names(alt), 8)
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
            if cs.fields.is_empty() {
                self.type_error(
                    e.pos,
                    format!(
                        "nullary cases omit call parentheses; write {0} instead of {0}()",
                        cs.name
                    ),
                );
            }
            let resolved = constructor_arguments(args, &cs.fields);
            i.arguments = slots(&resolved);
            let alt = self.instantiate(&alt, &cs.fields, &resolved, expected, e.pos);
            let cs = case_of(&alt, cs.name).unwrap_or(cs);
            i.no_return = self.arguments_for(cs.name.as_str(), e.pos, &resolved, &cs.fields, &None);
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
        if let Some(s) = symbol.as_ref().filter(|s| s.is_constant() && !const_use) {
            self.type_error(
                e.pos,
                format!(
                    "{} is a constant, not a function; remove the parentheses and write {}",
                    s.name, s.name
                ),
            );
            i.ty = Some(invalid());
            return i;
        }
        if let Some(s) = symbol {
            i.symbol = Some(s.clone());
            i.native = (!s.native.as_str().is_empty()).then_some(s.native);
            let mut sig = s.ty();
            let vars = s.variables();
            if !vars.is_empty() {
                let mut context = CallContext {
                    result: sig.result_ty(),
                    expected: expected.cloned(),
                    pos: e.pos,
                    conflict: false,
                };
                if !explicit {
                    let mut subst = Subst::new();
                    let params = sig.params.clone();
                    let resolved = function_arguments(args, &params);
                    self.infer_arguments(&resolved, &params, &vars, &mut subst, Some(&mut context));
                    for v in &vars {
                        supplied.push(subst.get(&v.id).cloned());
                    }
                }
                if supplied.len() >= required_type_arguments(&vars) {
                    supplied = complete_type_arguments(&vars, &supplied);
                }
                sig = self.specialize(&sig, &vars, &supplied, e.pos, &callee_name(callee));
                if context.conflict {
                    sig = with_result(&sig, invalid());
                }
                i.type_args = supplied;
            } else if explicit && !supplied.is_empty() {
                self.type_error(
                    e.pos,
                    format!(
                        "nongeneric function cannot take type arguments; remove the [...] after {}",
                        s.name
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
                    if c.native_str() != "index" {
                        // An indexed callee (callbacks[0](2)) must not make the call itself lower as an index.
                        i.native = c.native;
                    }
                    signature = c.ty.clone();
                    callable = c;
                    return self.finish_call(e, callee, args, i, signature, callable);
                }
            };
            if c.t().id == "<invalid>" {
                for arg in args {
                    self.expression(&arg.value, None);
                }
                return c;
            }
            c = self.specialize_native_call(e, callee, args, c, expected);
            i.method = c.method.clone();
            if c.native_str() != "index" {
                i.native = c.native;
            }
            signature = c.ty.clone();
            callable = c;
        }
        self.finish_call(e, callee, args, i, signature, callable)
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
            && sig.id == "<invalid>"
        {
            i.ty = Some(sig.clone());
            return i;
        }
        let Some(sig) = signature.filter(|s| s.kind == Kind::Function) else {
            let t = callable.ty.clone();
            self.not_callable(e, callee, t.as_ref());
            return i;
        };
        let resolved = function_arguments(args, &sig.params);
        i.arguments = slots(&resolved);
        i.no_return = callable.no_return
            || self.arguments_for(
                &callee_name(callee),
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
        if result.id == "Never" {
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
        if t.is_some_and(|t| t.to_string().contains("<invalid>")) {
            return;
        }
        self.unknown_type = true;
        let mut message = match callee_name(callee) {
            name if !name.is_empty() => format!("{name} is not a function"),
            _ => "callee is not a function".to_string(),
        };
        if let Some(t) = t {
            message.push_str(&format!(" (it has type {t})"));
        }
        self.type_error(
            e.pos,
            format!("{message}; only functions and methods can be called, so remove the (...) or call a function instead"),
        );
    }

    fn arguments(&mut self, args: &[Arg], params: &[Param], defaults: &Defaults) -> bool {
        let call_name = std::mem::take(&mut self.call_name);
        let call_pos = self.call_pos.take();
        let mut seen: HashSet<Name> = HashSet::new();
        let mut no_return = false;
        for arg in args {
            if arg.name.as_str().is_empty() {
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
                    format!("duplicate argument {}; pass each argument once", arg.name),
                );
            }
            let expected = params
                .iter()
                .find(|p| p.name == arg.name)
                .map(|p| p.ty.clone());
            if expected.is_none() {
                let hint = unknown_argument_hint(arg.name.as_str(), &call_name, params);
                self.type_error(arg.pos, format!("unknown argument {}{hint}", arg.name));
            }
            if expected.is_some() && !call_name.is_empty() {
                self.mismatch_context = Some(format!("argument '{}' of {call_name}", arg.name));
            }
            let v = self.argument_expression(arg.value, expected.as_ref());
            self.mismatch_context = None;
            no_return = no_return || v.no_return;
            seen.insert(arg.name);
        }
        for param in params {
            // An invalid parameter type means an earlier diagnostic already explained this call.
            if param.ty.id == "<invalid>" {
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
                        "missing argument {}{}",
                        param.name,
                        missing_argument_hint(param, &call_name)
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
        let mut subst = Subst::new();
        let mut args: Vec<Option<Ty>> = args.to_vec();
        if args.len() < vars.len() && args.len() >= required_type_arguments(vars) {
            let mut known = Subst::new();
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
                    if !self.label_mismatch {
                        self.type_error(pos, missing_type_argument_hint(name, v.name, vars, &args));
                    }
                    invalid()
                }
            };
            subst.insert(v.id, a);
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
        let vars = def.variables();
        let mut subst = Subst::new();
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
            .map(|f| Param {
                name: f.name,
                ty: sub(&f.ty, &subst),
            })
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
                    if !self.argument_failed_inference(args) {
                        self.type_error(
                            pos,
                            format!("cannot infer constructor type argument {}; write the type arguments, e.g. Box[Int](...), or annotate the binding", v.name),
                        );
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
        let checked = self
            .checked_arguments
            .as_ref()
            .and_then(|m| m.get(&e.id))
            .cloned();
        let mut info = checked.as_ref().and_then(|c| c.info.clone());
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
        let optional = expected.filter(|x| x.is_std("Optional") && x.args.len() == 1);
        let Some(expected_optional) = optional else {
            return match info {
                Some(i) => self.check_expression(e, i, expected),
                None => self.expression(e, expected),
            };
        };
        let checkpoint = self.p.diagnostics.len();
        let info = match info {
            Some(i) => i,
            None => self.infer(e, expected),
        };
        let payload = expected_optional.args[0].clone();
        let actual = info.ty.clone();
        if compatible(&actual, expected_optional) {
            return self.check_expression(e, info, expected);
        }
        let payload_ok = compatible(&actual, &payload)
            || actual
                .as_ref()
                .is_some_and(|a| self.error_assignable(a, &payload));
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

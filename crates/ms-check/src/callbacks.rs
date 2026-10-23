//! Function expressions.

use crate::checker::{CallbackReturns, Checker, Scope};
use crate::inference::{callback_context, inference_known_opt, inference_type_known};
use crate::syntax::*;
use crate::types::Param;
use crate::types::*;
use ms_syntax::ast::*;
use std::collections::{HashMap, HashSet};

impl Checker {
    /// Checks a function expression against the context that expects it.
    pub(crate) fn callback(&mut self, e: &Expr, l: &Lambda, expected: Option<&Ty>) -> Info {
        let mut context = callback_context(expected);
        if context
            .as_ref()
            .is_some_and(|c| c.params.len() != l.params.len())
        {
            self.type_error(
                e.pos,
                "callback parameter count does not match its context; the callback takes exactly the parameters its context declares",
            );
            context = None;
        }
        let mut params: Vec<Param> = Vec::with_capacity(l.params.len());
        let mut seen: HashSet<Name> = HashSet::new();
        let mut defaults: HashSet<Name> = HashSet::new();
        for (index, param) in l.params.iter().enumerate() {
            if !seen.insert(param.name) {
                self.type_error(
                    param.pos,
                    format!(
                        "duplicate parameter or field {}; each name may appear once, so rename one",
                        param.name
                    ),
                );
            }
            let typ = if param.ty.is_some() {
                self.resolve(param.ty.as_ref())
            } else if let Some(c) = context
                .as_ref()
                .filter(|c| inference_type_known(&c.params[index].ty, &self.inference_variables))
            {
                c.params[index].ty.clone()
            } else {
                self.type_error(
                    param.pos,
                    format!(
                        "cannot infer callback parameter {}; provide a type or a known function context",
                        param.name
                    ),
                );
                invalid()
            };
            params.push(Param {
                name: param.name,
                ty: typ,
            });
            if param.default.is_some() {
                defaults.insert(param.name);
            }
        }
        let mut result: Option<Ty> = None;
        if let Some(r) = &l.result {
            result = Some(self.resolve(Some(r)));
        } else if let Some(c) = &context
            && inference_known_opt(&c.result, &self.inference_variables)
        {
            result = c.result.clone();
        }
        let old_scope = self.scope.clone();
        let old_result = self.result.clone();
        let old_function = self.function;
        let old_loops = self.loops;
        let old_returns = self.return_inference.take();
        self.scope = Scope::new(Some(old_scope.clone()));
        self.result = result.clone();
        if result.is_none() {
            self.result = Some(primitive("<inferred>"));
            let mut frame = CallbackReturns::default();
            if let Some(c) = &context {
                self.result = c.result.clone();
                frame.context = c.result.clone();
            }
            self.return_inference = Some(frame);
        }
        self.serial += 1;
        self.function = self.serial;
        self.loops = 0;
        self.captures.insert(self.function, HashMap::new());
        let mut bindings: Vec<BindingRef> = Vec::new();
        let mut bound: HashSet<Name> = HashSet::new();
        for (index, param) in params.iter().enumerate() {
            if let Some(default) = &l.params[index].default {
                self.expression(default, Some(&param.ty));
            }
            // A repeated name was reported while collecting the parameters.
            let b = self.bind_reporting(
                param.name,
                &param.ty,
                l.params[index].mutable,
                l.params[index].pos,
                !bound.contains(&param.name),
            );
            bindings.push(b);
            bound.insert(param.name);
        }
        self.m().facts_mut().lambda_params.insert(e.id, bindings);
        let (fall, _) = self.block(&l.body, false);
        let result = match result {
            None => {
                if fall {
                    self.return_add(&unit(), e.pos);
                }
                let frame = self.return_inference.as_ref();
                match frame.and_then(|f| f.ty.clone()) {
                    Some(t) => t,
                    None if frame.is_some_and(|f| f.unresolved) => invalid(),
                    None => never(),
                }
            }
            Some(r) => {
                if fall && r.id != "Unit" && r.id != "<invalid>" {
                    self.type_error(
                        e.pos,
                        "reachable fallthrough in anonymous function; end every path with a 'return'",
                    );
                }
                r
            }
        };
        // Context labels belong to callers; source names remain local bindings.
        // Preserve invariant parameter types and declaration order.
        if let Some(c) = &context {
            for (index, p) in params.iter_mut().enumerate() {
                p.name = c.params[index].name;
            }
            let mut renamed: HashSet<Name> = HashSet::new();
            for (index, param) in l.params.iter().enumerate() {
                if defaults.contains(&param.name) {
                    renamed.insert(params[index].name);
                }
            }
            defaults = renamed;
        }
        let defaults = (!defaults.is_empty()).then(|| std::rc::Rc::new(defaults));
        let mut info = Info::of(function_with(params, result, defaults));
        if let Some(frame) = &self.return_inference {
            info.inference_deferred = frame.unresolved || frame.context_dependent;
        }
        let mut captured: Vec<BindingRef> = self
            .captures
            .get(&self.function)
            .map(|m| m.values().cloned().collect())
            .unwrap_or_default();
        captured.sort_by_key(|b| b.uid);
        for binding in captured {
            if old_function != binding.function
                && let Some(outer) = self.captures.get_mut(&old_function)
            {
                outer.insert(binding.uid, binding.clone());
            }
            info.captures.push(binding);
        }
        self.scope = old_scope;
        self.result = old_result;
        self.function = old_function;
        self.loops = old_loops;
        self.return_inference = old_returns;
        info
    }
}

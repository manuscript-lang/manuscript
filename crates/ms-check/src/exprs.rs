//! Expression checking.

use crate::checker::Checker;
use crate::hints::*;
use crate::inference::inference_type_known;
use crate::stdlib;
use crate::suggestions;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::rc::Rc;

fn decimal_valid(text: &str) -> bool {
    let raw = text.strip_suffix('d').unwrap_or(text);
    let raw = raw.strip_prefix(['-', '+']).unwrap_or(raw);
    let (mantissa, exponent_text) = match raw.find(['e', 'E']) {
        Some(at) => (&raw[..at], &raw[at + 1..]),
        None => (raw, "0"),
    };
    let digits = exponent_text
        .strip_prefix(['-', '+'])
        .unwrap_or(exponent_text);
    if digits.is_empty() || mantissa.is_empty() || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return false;
    }
    let mut fraction = 0usize;
    let mut coefficient = mantissa.to_string();
    if let Some(at) = mantissa.find('.') {
        if at == 0 || at == mantissa.len() - 1 {
            return false;
        }
        fraction = mantissa.len() - at - 1;
        coefficient = format!("{}{}", &mantissa[..at], &mantissa[at + 1..]);
    }
    if !coefficient.bytes().all(|c| c.is_ascii_digit()) {
        return false;
    }
    let coefficient = coefficient.trim_start_matches('0');
    // Zero is exact regardless of written exponent.
    if coefficient.is_empty() {
        return true;
    }
    let Ok(exponent) = exponent_text.parse::<i32>() else {
        return false;
    };
    let trimmed = coefficient.trim_end_matches('0');
    let quantum =
        i64::from(exponent) - fraction as i64 + (coefficient.len() - trimmed.len()) as i64;
    trimmed.len() <= 34 && quantum >= -6176 && quantum + trimmed.len() as i64 - 1 <= 6144
}

fn is_ordering(op: BinaryOp) -> bool {
    matches!(
        op,
        BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge
    )
}

/// Whether a type is an integer of any width.
pub(crate) fn integer(t: &Ty) -> bool {
    int_bits(t).is_some()
}

/// Whether a type is an integer or float of any width, or Decimal.
pub(crate) fn numeric(t: &Ty) -> bool {
    integer(t) || float_bits(t).is_some() || t.is_std("Decimal") || t.is_std("BigInt")
}

/// An unsuffixed number literal, possibly negated.
pub(crate) fn is_plain_literal(e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Number(t) => !t.ends_with('d'),
        ExprKind::Unary {
            op: UnaryOp::Neg,
            operand,
        } => is_plain_literal(operand),
        _ => false,
    }
}

/// Whether `e` is a plain literal or arithmetic over plain literals only, and if so whether its
/// literals are fractional. Mixed integer and fractional literals have no common kind.
fn literal_tree_fractional(e: &Expr) -> Option<bool> {
    match &e.kind {
        ExprKind::Number(t) if !t.ends_with('d') => Some(t.contains(['.', 'e', 'E'])),
        ExprKind::Unary {
            op: UnaryOp::Neg,
            operand,
        } => literal_tree_fractional(operand),
        ExprKind::Binary {
            op: BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div | BinaryOp::Rem,
            left,
            right,
        } => {
            let l = literal_tree_fractional(left)?;
            (l == literal_tree_fractional(right)?).then_some(l)
        }
        _ => None,
    }
}

/// The sized number type a literal operand takes from the other operand, if any. Only a literal
/// (or arithmetic over literals) of the same kind adopts it, so a mismatch keeps the ordinary
/// operand-type diagnostic.
pub(crate) fn literal_hint<'a>(literal: &Expr, other: &'a Ty) -> Option<&'a Ty> {
    if let ExprKind::List(items) = &literal.kind {
        // A list of plain literals takes the element type of a `List` of a sized number.
        let element = (other.is_std("List") && other.args.len() == 1).then(|| &other.args[0])?;
        let all = !items.is_empty() && items.iter().all(|i| literal_hint(i, element).is_some());
        return all.then_some(other);
    }
    let fractional = literal_tree_fractional(literal)?;
    let sized_int = int_bits(other).is_some() && other.id != "Int";
    let sized_float = float_bits(other).is_some() && other.id != "Float";
    ((!fractional && sized_int) || (fractional && sized_float)).then_some(other)
}

/// Whether the decimal integer literal `text`, negated when `negated`, fits the integer type `t`.
fn int_literal_fits(text: &str, negated: bool, t: &Ty) -> bool {
    let Ok(v) = text.parse::<i128>() else {
        return false;
    };
    let v = if negated { -v } else { v };
    int_range(t).is_some_and(|(lo, hi)| (lo..=hi).contains(&v))
}

fn is_time_operand(types: &[&Ty]) -> bool {
    types
        .iter()
        .any(|t| t.is_std("Duration") || t.is_std("Instant"))
}

const TIME_ARITHMETIC: [(BinaryOp, &str, &str, &str); 5] = [
    (BinaryOp::Add, "Duration", "Duration", "Duration"),
    (BinaryOp::Sub, "Duration", "Duration", "Duration"),
    (BinaryOp::Add, "Instant", "Duration", "Instant"),
    (BinaryOp::Sub, "Instant", "Duration", "Instant"),
    (BinaryOp::Sub, "Instant", "Instant", "Duration"),
];

/// Names the use after the "expected X, found Y" head: "... (in <context>); hint".
fn with_mismatch_context(message: String, context: &str) -> String {
    match message.split_once("; ") {
        Some((head, rest)) => format!("{head} (in {context}); {rest}"),
        None => format!("{message} (in {context})"),
    }
}

fn unknown_expected(expected: Option<&Ty>) -> bool {
    expected.is_some_and(|t| t.kind == Kind::Primitive && t.id == "<invalid>")
}

fn finish_info(mut i: Info) -> Info {
    if i.ty.as_ref().is_some_and(|t| t.id == "Never") {
        i.no_return = true;
    }
    i
}

impl Checker {
    /// Checks an expression against an expected type.
    pub(crate) fn expression(&mut self, e: &Expr, expected: Option<&Ty>) -> Info {
        if let Some(x) = expected
            && x.is_std("Optional")
            && x.args.len() == 1
            && !matches!(e.kind, ExprKind::Lambda(_))
        {
            let mut info = self.argument_expression(e, expected);
            if let Some(w) = info.optional_argument.take() {
                info.wrap_some = Some(w);
                self.set_info(e, info.clone());
            }
            return info;
        }
        let context = self.mismatch_context.take();
        let i = self.infer(e, expected);
        self.mismatch_context = context;
        self.check_expression(e, i, expected)
    }

    /// Checks an expression whose use is named in a mismatch diagnostic.
    pub(crate) fn expression_in(
        &mut self,
        e: &Expr,
        expected: Option<&Ty>,
        context: String,
    ) -> Info {
        self.mismatch_context = Some(context);
        self.expression(e, expected)
    }

    pub(crate) fn check_expression(
        &mut self,
        e: &Expr,
        mut i: Info,
        expected: Option<&Ty>,
    ) -> Info {
        let context = self.mismatch_context.take();
        if i.ty.is_none() {
            i.ty = Some(invalid());
        }
        let actual = i.t();
        if actual.id == "Never" {
            i.no_return = true;
        }
        if let Some(exp) = expected {
            if actual.id != "<invalid>"
                && exp.id != "<invalid>"
                && !compatible(&Some(actual.clone()), exp)
            {
                if self.interface_assignable(&actual, exp) {
                    i.error_source = Some(actual.clone());
                    i.scoped_error = exp.is_std("Error") && self.error_needs_scope(&actual);
                    i.ty = Some(exp.clone());
                } else if self.error_assignable(&actual, exp) {
                    i.error_source = Some(actual.clone());
                    let mut cause = actual.clone();
                    if cause.is_std("Result") && cause.args.len() == 2 {
                        cause = cause.args[1].clone();
                    }
                    i.scoped_error = self.error_needs_scope(&cause);
                    i.ty = Some(exp.clone());
                } else {
                    let mut msg = self.assignment_mismatch(&actual, exp);
                    if let Some(context) = context {
                        msg = with_mismatch_context(msg, &context);
                    }
                    let fix = suggestions::conversion_fix(
                        &self.m().source,
                        e,
                        actual.id.as_str(),
                        exp.id.as_str(),
                    );
                    self.type_error_with_fix(e.pos, msg, fix);
                }
            }
            if exp.kind == Kind::Function && same(&i.t(), exp) {
                i.ty = Some(exp.clone());
            }
        }
        if !matches!(e.kind, ExprKind::Lambda(_)) {
            let mut breaks = i.breaks;
            let mut child = |c: &Checker, value: &Expr| {
                if let Some(info) = c.info_of(value) {
                    breaks = breaks || info.breaks;
                }
            };
            match &e.kind {
                ExprKind::Member { left, .. } => child(self, left),
                ExprKind::Apply { left, value, .. } => {
                    child(self, left);
                    if let Some(v) = value {
                        child(self, v);
                    }
                }
                ExprKind::Index { left, index } => {
                    child(self, left);
                    child(self, index);
                }
                ExprKind::Unary { operand, .. } => child(self, operand),
                ExprKind::Binary { left, right, .. } => {
                    child(self, left);
                    child(self, right);
                }
                ExprKind::Call { callee, args } => {
                    child(self, callee);
                    for a in args {
                        child(self, &a.value);
                    }
                }
                ExprKind::Match { scrutinee, .. } => child(self, scrutinee),
                ExprKind::List(items) => {
                    for x in items {
                        child(self, x);
                    }
                }
                ExprKind::Map(entries) => {
                    for en in entries {
                        child(self, &en.key);
                        child(self, &en.value);
                    }
                }
                ExprKind::Text(parts) => {
                    for part in parts {
                        if let TextPart::Interp(x) = part {
                            child(self, x);
                        }
                    }
                }
                _ => {}
            }
            i.breaks = breaks;
        }
        self.set_info(e, i.clone());
        i
    }

    /// Infers an expression's facts without committing them.
    pub(crate) fn infer(&mut self, e: &Expr, expected: Option<&Ty>) -> Info {
        self.capture_scope(e);
        let mut i = Info::default();
        match &e.kind {
            ExprKind::Number(text) => {
                return self.infer_number(
                    e,
                    &ms_syntax::number::canonical(text.as_str()),
                    expected,
                    false,
                    i,
                );
            }
            ExprKind::Bool(_) => i.ty = Some(bool_()),
            ExprKind::Unit => i.ty = Some(unit()),
            ExprKind::Text(parts) => return self.infer_text(parts, i),
            ExprKind::Name(name) => return self.infer_name(e, *name, expected, i),
            ExprKind::Index { left, index } => return self.index(e, left, index),
            ExprKind::Match { .. } => return self.match_expression(e, expected, false),
            ExprKind::Apply { left, types, value } => {
                return self.infer_apply(e, left, types, value.as_deref(), expected, i);
            }
            ExprKind::Member { left, name } => {
                return self.infer_member(e, left, *name, expected, i);
            }
            ExprKind::Call { callee, args } => return self.call(e, callee, args, false, expected),
            ExprKind::Lambda(l) => return self.callback(e, l, expected),
            ExprKind::List(items) => return self.infer_list(e, items, expected, i),
            ExprKind::Map(entries) => return self.infer_map_literal(e, entries, expected, i),
            ExprKind::Unary { op, operand } => {
                return self.infer_unary(e, *op, operand, expected, i);
            }
            ExprKind::Binary { op, left, right } => {
                return self.infer_binary(e, *op, left, right, expected, i);
            }
        }
        finish_info(i)
    }

    fn infer_number(
        &mut self,
        e: &Expr,
        text: &str,
        expected: Option<&Ty>,
        negated: bool,
        mut i: Info,
    ) -> Info {
        if text.ends_with('d') {
            let ok = self
                .sym(n("Decimal"))
                .zip(stdlib::standard_symbol("Decimal"))
                .is_some_and(|(a, b)| Rc::ptr_eq(&a, &b));
            if !ok {
                self.res_error_name(
                    e.pos,
                    text.len(),
                    "Decimal literal requires the canonical Decimal import; add: from \"@std/decimal.ms\" import Decimal".to_string(),
                );
            }
            i.ty = Some(standard("Decimal", vec![]));
            if !decimal_valid(text) {
                self.type_error(
                    e.pos,
                    "Decimal literal is outside the exact 34-digit representable grid; shorten it to 34 significant digits",
                );
            }
        } else if text.contains(['.', 'e', 'E']) {
            // An expected sized float type gives the literal that type.
            let narrow = expected.filter(|t| float_bits(t) == Some(32) && t.id != "Float");
            match (text.parse::<f64>(), narrow) {
                (Ok(v), Some(_)) if (v as f32).is_infinite() => self.type_error(
                    e.pos,
                    "Float literal is outside finite binary32 range; use a smaller magnitude (about 3.4e38 at most)",
                ),
                (Ok(v), None) if v.is_infinite() => self.type_error(
                    e.pos,
                    "Float literal is outside finite binary64 range; use a smaller magnitude (about 1.8e308 at most)",
                ),
                (Err(_), _) => self.type_error(
                    e.pos,
                    "Float literal is outside finite binary64 range; use a smaller magnitude (about 1.8e308 at most)",
                ),
                _ => {}
            }
            i.ty = Some(narrow.cloned().unwrap_or_else(|| primitive("Float")));
        } else {
            // An expected sized integer type gives the literal that type.
            let sized = expected.filter(|t| int_bits(t).is_some() && t.id != "Int");
            match sized {
                Some(t) => {
                    if !int_literal_fits(text, negated, t) {
                        let (lo, hi) = int_range(t).unwrap_or_default();
                        self.type_error(
                            e.pos,
                            format!(
                                "literal {}{text} is out of range for {t}; use a value between {} and {}",
                                if negated { "-" } else { "" },
                                lo, hi
                            ),
                        );
                    }
                    i.ty = Some(t.clone());
                }
                None => {
                    if text.parse::<i64>().is_err() {
                        self.type_error(
                            e.pos,
                            "Int literal is outside signed 64-bit range; use a value between -9223372036854775808 and 9223372036854775807, or BigInt",
                        );
                    }
                    i.ty = Some(primitive("Int"));
                }
            }
        }
        finish_info(i)
    }

    fn infer_text(&mut self, parts: &[TextPart], mut i: Info) -> Info {
        i.ty = Some(string());
        for part in parts {
            if let TextPart::Interp(x) = part {
                let p = self.expression(x, None);
                i.no_return = i.no_return || p.no_return;
            }
        }
        finish_info(i)
    }

    fn infer_name(&mut self, e: &Expr, name: Name, expected: Option<&Ty>, mut i: Info) -> Info {
        if name == "fixture" && self.scope.binding(name).is_none() {
            self.res_error(
                e.pos,
                "fixture is available only in tests with a local make_fixture factory; declare fn make_fixture() returning a concrete TestHooks implementer in this file",
            );
            i.ty = Some(invalid());
            return i;
        }
        if let Some(b) = self.scope.binding(name) {
            i.ty = Some(b.ty.clone());
            i.binding = Some(b.clone());
            if b.function != self.function
                && let Some(captured) = self.captures.get_mut(&self.function)
            {
                captured.insert(b.uid, b.clone());
            }
            return i;
        }
        if let Some(s) = self.sym(name) {
            if s.kind == SymKind::Type {
                self.type_error(
                    e.pos,
                    format!(
                        "type name requires a constructor call; write {name}(field: value, ...) to build a value"
                    ),
                );
                i.ty = Some(invalid());
            } else if s.is_constant() {
                // A constant stands for its initializer: check the use as a call.
                self.constant_type(&s);
                self.m().facts_mut().const_use.insert(e.id);
                return self.call(e, e, &[], true, expected);
            } else {
                i.ty = s.ty_opt();
                i.symbol = Some(s.clone());
                if !s.variables().is_empty() {
                    self.type_error(
                        e.pos,
                        format!(
                            "a generic function value requires explicit specialization; write {name}[Type] or call it with arguments"
                        ),
                    );
                    i.ty = Some(invalid());
                } else if s
                    .decl
                    .as_ref()
                    .is_some_and(|d| d.fn_params().iter().any(|p| p.mutable))
                {
                    self.type_error(
                        e.pos,
                        format!(
                            "{name} has a var parameter, so it cannot be a function value: calls through a function value cannot mark an argument var; take the parameter by value (var copy = param inside the body) or call {name} from a lambda"
                        ),
                    );
                    i.ty = Some(invalid());
                }
            }
            return i;
        }
        let (typ, cs, ambiguous) = self.find_case(name, e.pos);
        if ambiguous {
            i.ty = Some(invalid());
        } else if let (Some(typ), Some(cs)) = (typ, cs.filter(|c| c.fields.is_empty())) {
            let constructor = self.instantiate(&typ, &[], &[], expected, e.pos);
            i.case = Some(cs.name);
            i.ty = Some(constructor.clone());
            i.constructor = Some(constructor);
        } else {
            let msg = self.unknown_name(name);
            self.res_error_name(e.pos, name.len(), msg);
        }
        finish_info(i)
    }

    fn infer_apply(
        &mut self,
        e: &Expr,
        left: &Expr,
        types: &[TypeRef],
        value: Option<&Expr>,
        expected: Option<&Ty>,
        mut i: Info,
    ) -> Info {
        let _ = expected;
        if let Some(callable) = self.native_callable(e) {
            let args = self.resolve_arguments(types);
            i = callable.clone();
            if callable.t().id == "<invalid>" {
                return i;
            }
            let variables = callable
                .method
                .as_ref()
                .map(|m| m.variables.clone())
                .unwrap_or_default();
            let opt_args: Vec<Option<Ty>> = args.into_iter().map(Some).collect();
            i.ty =
                Some(self.specialize(&callable.t(), &variables, &opt_args, e.pos, &callee_name(e)));
            self.set_info(left, i.clone());
            return i;
        }
        if let Some(s) = self.function_symbol(left) {
            let args = self.resolve_arguments(types);
            let mut supplied: Vec<Option<Ty>> = args.into_iter().map(Some).collect();
            let vars = s.variables();
            if supplied.len() >= required_type_arguments(&vars) {
                supplied = complete_type_arguments(&vars, &supplied);
            }
            i.symbol = Some(s.clone());
            i.ty = Some(self.specialize(&s.ty(), &vars, &supplied, e.pos, &callee_name(e)));
            i.type_args = supplied;
        } else if let Some(typ) = self.type_expression(e) {
            self.type_error(
                e.pos,
                "type application requires construction; add (field: value, ...) after the type arguments",
            );
            i.ty = Some(typ);
        } else {
            if let Some(v) = value {
                return self.index(e, left, v);
            }
            if let ExprKind::Name(nm) = &left.kind
                && self.scope.binding(*nm).is_none()
                && self.sym(*nm).is_none()
            {
                let msg = self.unknown_name(*nm);
                self.res_error_name(left.pos, nm.len(), msg);
                i.ty = Some(invalid());
                return i;
            }
            self.res_error(
                e.pos,
                "brackets require type arguments on a generic declaration or one Int index on a List",
            );
        }
        finish_info(i)
    }

    fn infer_member(
        &mut self,
        e: &Expr,
        left: &Expr,
        name: Name,
        expected: Option<&Ty>,
        mut i: Info,
    ) -> Info {
        if let Some(typ) = self.type_expression(left) {
            if typ.kind == Kind::Contract {
                let msg = self.interface_type_member(&typ);
                self.res_error(e.pos, msg);
                return i;
            }
            if let Some(cs) = case_of(&typ, name).filter(|c| c.fields.is_empty()) {
                let constructor = self.instantiate(&typ, &[], &[], expected, e.pos);
                i.ty = Some(constructor.clone());
                i.constructor = Some(constructor);
                i.case = Some(cs.name);
                return i;
            }
            self.res_error(
                e.pos,
                format!(
                    "unknown or non-nullary alternative case {name} of {}; cases: {} (cases with payloads need call syntax)",
                    typ.name,
                    list(&crate::stmts::case_names(&typ), 12)
                ),
            );
            i.ty = Some(invalid());
            return i;
        }
        let arity = self
            .call_arity
            .filter(|(callee, _)| *callee == e.id)
            .map(|(_, count)| count);
        let receiver = self.expression(left, None);
        i.no_return = receiver.no_return;
        let rt = receiver.t();
        if rt.id == "<invalid>" {
            return i;
        }
        if rt.kind == Kind::Record
            && name != "to_string"
            && let Some(f) = field_of(&rt, name)
        {
            i.ty = Some(f.ty);
            return i;
        }
        if rt.id == "Int" && matches!(name.as_str(), "seconds" | "milliseconds" | "minutes") {
            i.ty = Some(standard("Duration", vec![]));
            i.native = Some(name);
            return i;
        }
        // `m[key] = value` is `m.add(key, value)` and `xs[i] = value` is `xs.set(i, value)`.
        let index_set = name == ms_syntax::parser::INDEX_SET;
        let name = match index_set {
            true if rt.is_std("Map") => n("add"),
            true => n("set"),
            false => name,
        };
        let mut methods = self.methods(&rt, name);
        // Operations that share a name are told apart by how many arguments the call passes.
        if let Some(count) = arity {
            let fitting = |candidates: &[MethodRef]| -> Vec<MethodRef> {
                candidates
                    .iter()
                    .filter(|m| accepts_arguments(&m.ty, count))
                    .cloned()
                    .collect()
            };
            if methods.len() > 1 {
                let found = fitting(&methods);
                if found.len() == 1 {
                    methods = found;
                }
            } else if methods.len() == 1 && fitting(&methods).is_empty() {
                // A native operation does not take this many arguments: a source operation of the same name may.
                let found = fitting(&self.implemented_methods(&rt, name));
                if found.len() == 1 {
                    methods = found;
                }
            }
        }
        if index_set && methods.is_empty() {
            self.type_error(
                e.pos,
                "index assignment requires a List[T] or Map[K, V]; Bytes and String are immutable, build a new value instead",
            );
            i.ty = Some(invalid());
            return i;
        }
        if methods.len() > 1 {
            let msg = self.ambiguous_member(&rt, name, &methods);
            self.res_error(e.pos, msg);
            i.ty = Some(invalid());
            return i;
        }
        if methods.len() != 1 {
            let msg = self.unknown_member(&rt, name);
            self.res_error(e.pos, msg);
            // Later diagnostics that only restate the missing member are noise.
            i.ty = Some(invalid());
            return i;
        }
        let m = methods[0].clone();
        i.ty = Some(m.ty.clone());
        i.native = if m.native.as_str().is_empty() {
            None
        } else {
            Some(m.native)
        };
        if !m.native.as_str().is_empty() && m.native != "contract" && !m.variables.is_empty() {
            self.type_error(
                e.pos,
                "a generic method value requires explicit specialization; write the type arguments or call it with arguments",
            );
        }
        i.method = Some(m);
        finish_info(i)
    }

    fn infer_list(&mut self, e: &Expr, items: &[Expr], expected: Option<&Ty>, mut i: Info) -> Info {
        let canonical = self
            .sym(n("List"))
            .zip(stdlib::standard_symbol("List"))
            .is_some_and(|(a, b)| Rc::ptr_eq(&a, &b));
        if !canonical {
            self.res_error(
                e.pos,
                "list literal requires the canonical List type; rename the shadowing List declaration or binding",
            );
        }
        let mut element: Option<Ty> = None;
        if let Some(exp) = expected
            && exp.is_std("List")
            && exp.args.len() == 1
            && inference_type_known(&exp.args[0], &self.inference_variables)
        {
            element = Some(exp.args[0].clone());
        }
        let mut independent: Vec<Option<Info>> = vec![None; items.len()];
        if element.is_none() {
            element = self.independent_items(items, 0, 1, &mut independent);
        }
        let element = match element {
            Some(t) => t,
            None => {
                if unknown_expected(expected) {
                    return self.unknown_literal(items, expected, &independent, i);
                }
                if !self.unknown_type {
                    self.type_error(
                        e.pos,
                        "cannot infer list element type; add an annotation, e.g. let xs: List[Int] = []",
                    );
                }
                invalid()
            }
        };
        self.literal_items(items, &independent, std::slice::from_ref(&element), &mut i);
        i.ty = Some(standard("List", vec![element]));
        finish_info(i)
    }

    fn infer_map_literal(
        &mut self,
        e: &Expr,
        entries: &[MapEntry],
        expected: Option<&Ty>,
        mut i: Info,
    ) -> Info {
        let canonical = self
            .sym(n("Map"))
            .zip(stdlib::standard_symbol("Map"))
            .is_some_and(|(a, b)| Rc::ptr_eq(&a, &b));
        if !canonical {
            self.res_error(
                e.pos,
                "map literal requires the canonical Map type; rename the shadowing Map declaration or binding",
            );
        }
        let mut types: [Option<Ty>; 2] = [None, None];
        if let Some(exp) = expected
            && exp.is_std("Map")
            && exp.args.len() == 2
            && inference_type_known(&exp.args[0], &self.inference_variables)
            && inference_type_known(&exp.args[1], &self.inference_variables)
        {
            types[0] = Some(exp.args[0].clone());
            types[1] = Some(exp.args[1].clone());
        }
        let items: Vec<&Expr> = entries.iter().flat_map(|en| [&en.key, &en.value]).collect();
        let mut independent: Vec<Option<Info>> = vec![None; items.len()];
        // The key (0) and value (1) types are inferred in turn from alternating items.
        #[allow(clippy::needless_range_loop)]
        for index in 0..2 {
            if types[index].is_none() {
                types[index] = self.independent_refs(&items, index, 2, &mut independent);
            }
            if types[index].is_none() {
                if unknown_expected(expected) {
                    return self.unknown_literal_refs(&items, expected, &independent, i);
                }
                self.type_error(
                    e.pos,
                    "cannot infer map key or value type; add an annotation, e.g. let m: Map[String, Int] = {}",
                );
                types[index] = Some(invalid());
            }
        }
        let resolved: Vec<Ty> = types.iter().map(|t| t.clone().expect("type")).collect();
        self.literal_refs(&items, &independent, &resolved, &mut i);
        let map_type = standard("Map", resolved);
        i.ty = Some(map_type.clone());
        // Key and value types were checked where they were written or
        // instantiated; rechecking them makes nested literals quartic in depth.
        self.bounds_hold(&map_type, e.pos);
        finish_info(i)
    }

    fn independent_items(
        &mut self,
        items: &[Expr],
        offset: usize,
        stride: usize,
        checked: &mut [Option<Info>],
    ) -> Option<Ty> {
        let refs: Vec<&Expr> = items.iter().collect();
        self.independent_refs(&refs, offset, stride, checked)
    }

    /// Checks the literal items at offset, offset+stride, ... that have a type
    /// without context, records their information, and returns the first type
    /// other than Never.
    fn independent_refs(
        &mut self,
        items: &[&Expr],
        offset: usize,
        stride: usize,
        checked: &mut [Option<Info>],
    ) -> Option<Ty> {
        let mut typ: Option<Ty> = None;
        let mut at = offset;
        while at < items.len() {
            if !self.contextual(items[at]) {
                let v = self.expression(items[at], None);
                if typ.is_none() && v.t().id != "Never" {
                    let t = v.t();
                    typ = Some(if t.kind == Kind::Function {
                        required_type(&t)
                    } else {
                        t
                    });
                }
                checked[at] = Some(v);
            }
            at += stride;
        }
        typ
    }

    fn literal_items(
        &mut self,
        items: &[Expr],
        checked: &[Option<Info>],
        types: &[Ty],
        i: &mut Info,
    ) {
        let refs: Vec<&Expr> = items.iter().collect();
        self.literal_refs(&refs, checked, types, i);
    }

    /// Checks literal items against their inferred or expected type. An item
    /// whose independent type is that very type is not checked again: repeating
    /// its whole subtree makes nested literals cubic in their depth. Map keys
    /// and values alternate through types.
    fn literal_refs(
        &mut self,
        items: &[&Expr],
        checked: &[Option<Info>],
        types: &[Ty],
        i: &mut Info,
    ) {
        for (at, item) in items.iter().enumerate() {
            let typ = &types[at % types.len()];
            let v = match &checked[at] {
                Some(v) if v.ty.as_ref().is_some_and(|t| Rc::ptr_eq(t, typ)) => v.clone(),
                _ => self.expression_in(
                    item,
                    Some(typ),
                    format!(
                        "entry {} of the literal, whose entries share one type",
                        at + 1
                    ),
                ),
            };
            i.no_return = i.no_return || v.no_return;
        }
    }

    fn unknown_literal(
        &mut self,
        items: &[Expr],
        expected: Option<&Ty>,
        checked: &[Option<Info>],
        i: Info,
    ) -> Info {
        let refs: Vec<&Expr> = items.iter().collect();
        self.unknown_literal_refs(&refs, expected, checked, i)
    }

    /// Finishes a literal nested where an enclosing literal or annotation
    /// already reported an unknown type. Its contextual items are checked
    /// without repeating that diagnostic once per nesting level.
    fn unknown_literal_refs(
        &mut self,
        items: &[&Expr],
        expected: Option<&Ty>,
        checked: &[Option<Info>],
        mut i: Info,
    ) -> Info {
        for (at, item) in items.iter().enumerate() {
            let v = match &checked[at] {
                Some(v) => v.clone(),
                None => self.expression(item, expected),
            };
            i.no_return = i.no_return || v.no_return;
        }
        i.ty = expected.cloned();
        finish_info(i)
    }

    fn infer_unary(
        &mut self,
        e: &Expr,
        op: UnaryOp,
        operand: &Expr,
        expected: Option<&Ty>,
        mut i: Info,
    ) -> Info {
        if op == UnaryOp::Neg
            && let ExprKind::Number(t) = &operand.kind
            && ms_syntax::number::canonical(t.as_str()) == "9223372036854775808"
        {
            i.ty = Some(int());
            self.set_info(
                operand,
                Info {
                    ty: Some(int()),
                    ..Info::default()
                },
            );
            return i;
        }
        // A negated literal takes its sized type from the expected type; -128 fits Int8.
        if op == UnaryOp::Neg
            && let ExprKind::Number(t) = &operand.kind
            && !t.ends_with('d')
        {
            let literal = self.infer_number(
                operand,
                &ms_syntax::number::canonical(t.as_str()),
                expected,
                true,
                Info::default(),
            );
            self.set_info(operand, literal.clone());
            i.ty = literal.ty.clone();
            return finish_info(i);
        }
        let hint = expected
            .filter(|_| op == UnaryOp::Neg && matches!(operand.kind, ExprKind::Binary { .. }))
            .filter(|t| literal_hint(operand, t).is_some());
        let v = self.expression(operand, hint);
        i.no_return = v.no_return;
        let vt = v.t();
        match op {
            UnaryOp::Not => {
                if !compatible(&Some(vt.clone()), &bool_()) {
                    self.type_error(
                        e.pos,
                        format!(
                            "not requires Bool, found {vt}; compare explicitly, e.g. not (x == 0)"
                        ),
                    );
                }
                i.ty = Some(bool_());
            }
            UnaryOp::Try => self.check_try(e, &v, &mut i),
            UnaryOp::Neg | UnaryOp::Plus => {
                if op == UnaryOp::Neg && int_unsigned(&vt) {
                    self.type_error(
                        e.pos,
                        format!("unary - is not defined for {vt}; subtract from zero with a wider signed type, e.g. 0 - x.to_int()"),
                    );
                }
                if !numeric(&vt) {
                    self.type_error(
                        e.pos,
                        format!("numeric sign requires an independently known numeric operand, found {vt}; apply + or - to Int, Float, Decimal, or BigInt"),
                    );
                }
                i.ty = Some(vt);
            }
        }
        finish_info(i)
    }

    /// Types `try operand`: the operand must be a Result whose error the
    /// enclosing function can return, either unchanged or through an Error
    /// boundary.
    fn check_try(&mut self, e: &Expr, operand: &Info, i: &mut Info) {
        let result = operand.t();
        if !result.is_std("Result") || result.args.len() != 2 {
            self.type_error(
                e.pos,
                format!("try requires Result, found {result}; apply try only to a call returning Result[T, E]"),
            );
            return;
        }
        if let Some(r) = self.return_inference.as_mut() {
            r.context_dependent = true;
        }
        i.ty = Some(result.args[0].clone());
        let enclosing = self.result_ty();
        if !enclosing.is_std("Result") || enclosing.args.len() != 2 {
            self.type_error(
                e.pos,
                "try requires an enclosing Result; declare this function to return Result[T, E], or use 'if let', '.get(default)', or '.get()'",
            );
            return;
        }
        let failure = result.args[1].clone();
        let returned = enclosing.args[1].clone();
        if same(&returned, &failure) {
            return;
        }
        if !self.error_assignable(&failure, &returned) {
            self.type_error(
                e.pos,
                format!("try requires the same error type or an Error boundary implemented by the specific error; this function returns {enclosing} but the operand fails with {failure}, so change the return error type or implement Error for it"),
            );
            return;
        }
        i.propagated_error = Some(failure.clone());
        i.scoped_propagation = self.error_needs_scope(&failure);
    }

    fn infer_binary(
        &mut self,
        e: &Expr,
        op: BinaryOp,
        left: &Expr,
        right: &Expr,
        expected: Option<&Ty>,
        mut i: Info,
    ) -> Info {
        if matches!(op, BinaryOp::Eq | BinaryOp::Ne) && (is_none_name(left) || is_none_name(right))
        {
            let other = if is_none_name(left) { right } else { left };
            let other = self.expression(other, None);
            if !invalid_ty(&other.t()) {
                self.type_error(
                    e.pos,
                    "none has no type of its own here; test absence with is_none() or is_some() (or compare with some(value))",
                );
            }
            i.ty = Some(bool_());
            return i;
        }
        // An unsuffixed literal beside a sized number takes that number's type: `x / 2`, `x == 0`.
        // Arithmetic over literals alone takes the expected sized number type: `let x: Float32 = 0.1 + 0.2`.
        let arithmetic = matches!(
            op,
            BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div | BinaryOp::Rem
        );
        let (a, b) = if let Some(hint) = expected
            .filter(|_| arithmetic)
            .filter(|t| literal_hint(left, t).is_some() && literal_hint(right, t).is_some())
        {
            (
                self.expression(left, Some(hint)),
                self.expression(right, Some(hint)),
            )
        } else if literal_tree_fractional(left).is_some()
            && literal_tree_fractional(right).is_none()
        {
            let b = self.expression(right, None);
            let bt = b.t();
            (self.expression(left, literal_hint(left, &bt)), b)
        } else {
            let a = self.expression(left, None);
            let at = a.t();
            (a, self.expression(right, literal_hint(right, &at)))
        };
        let (at, bt) = (a.t(), b.t());
        let logical = matches!(op, BinaryOp::And | BinaryOp::Or);
        i.no_return = a.no_return || (!logical && b.no_return);
        if logical {
            i.ty = Some(bool_());
            if (!compatible(&Some(at.clone()), &bool_())
                || !compatible(&Some(bt.clone()), &bool_()))
                && !invalid_ty(&at)
                && !invalid_ty(&bt)
            {
                self.type_error(
                    e.pos,
                    format!("logical operands require Bool, found {at} and {bt}; compare explicitly, e.g. x != 0"),
                );
            }
            return i;
        }
        if matches!(op, BinaryOp::Add | BinaryOp::Sub) && is_time_operand(&[&at, &bt]) {
            self.check_time_arithmetic(e, op, &at, &bt, &mut i);
            return i;
        }
        let mut common = at.clone();
        if common.id == "Never" {
            common = bt.clone();
        }
        let comparison = matches!(op, BinaryOp::Eq | BinaryOp::Ne) || is_ordering(op);
        if invalid_ty(&at) || invalid_ty(&bt) {
            // An operand already reported its own error; do not restate it.
            i.ty = Some(if comparison { bool_() } else { invalid() });
            return i;
        }
        if common.id == "Never"
            || !compatible(&Some(at.clone()), &common)
            || !compatible(&Some(bt.clone()), &common)
        {
            let mut hint = optional_use_hint(&at, &bt);
            if hint.is_empty() {
                hint = optional_use_hint(&bt, &at);
            }
            if hint.is_empty() {
                hint = result_use_hint(&at, &bt);
            }
            if hint.is_empty() {
                hint = result_use_hint(&bt, &at);
            }
            if hint.is_empty() {
                hint = int_float_mix_hint(&at, &bt);
            }
            if hint.is_empty() {
                hint = "convert one side so both have one type (e.g. interpolate into text with f\"{value}\", or convert between Int and Float)".to_string();
            }
            let source = self.m().source.clone();
            let fix = match (at.id.as_str(), bt.id.as_str()) {
                ("Int", "Float") => suggestions::to_float(&source, left),
                ("Float", "Int") => suggestions::to_float(&source, right),
                _ => None,
            };
            self.type_error_with_fix(
                e.pos,
                format!(
                    "operator operands require the same independently known type, found {at} {} {bt}; {hint}",
                    op.as_str()
                ),
                fix,
            );
            self.unknown_type = true; // later "<invalid>" diagnostics only restate this one
            i.ty = Some(if comparison { bool_() } else { invalid() });
            return i;
        }
        match op {
            BinaryOp::Eq | BinaryOp::Ne => {
                i.ty = Some(bool_());
                if !self.property(&common, "Equal", None) {
                    self.type_error(
                        e.pos,
                        format!("equality requires Equal operands; {common} has no equality, so add 'impl Equal for {common}:' or compare fields"),
                    );
                }
            }
            _ if is_ordering(op) => {
                i.ty = Some(bool_());
                if !numeric(&common)
                    && common.id != "String"
                    && !common.is_std("Duration")
                    && !common.is_std("Instant")
                {
                    self.type_error(
                        e.pos,
                        format!("ordering requires numeric, String, or time operands, found {common}; compare a numeric field or convert first"),
                    );
                }
            }
            _ => {
                i.ty = Some(common.clone());
                if common.id != "<invalid>"
                    && !numeric(&common)
                    && !(common.id == "String" && op == BinaryOp::Add)
                    && !(common.is_std("Duration") && matches!(op, BinaryOp::Add | BinaryOp::Sub))
                {
                    self.type_error(e.pos, "arithmetic requires numeric operands");
                }
                self.constant_arithmetic(e, op, left, right, &common);
                if op == BinaryOp::Rem && !integer(&common) && !common.is_std("BigInt") {
                    self.type_error(
                        e.pos,
                        format!("remainder requires integer operands, found {common}; convert to Int or use math functions"),
                    );
                }
            }
        }
        finish_info(i)
    }

    fn check_time_arithmetic(
        &mut self,
        e: &Expr,
        op: BinaryOp,
        left: &Ty,
        right: &Ty,
        i: &mut Info,
    ) {
        let mut matches = 0;
        for (row_op, l, r, result) in TIME_ARITHMETIC {
            if row_op == op
                && compatible(&Some(left.clone()), &standard(l, vec![]))
                && compatible(&Some(right.clone()), &standard(r, vec![]))
            {
                i.ty = Some(standard(result, vec![]));
                matches += 1;
            }
        }
        if matches != 1 {
            self.type_error(
                e.pos,
                "known operands must select exactly one time arithmetic operation; allowed: Duration±Duration, Instant±Duration, Instant-Instant",
            );
        }
    }
}

/// The dotted name of a callee (`a.b.c`), or the empty string.
pub(crate) fn callee_name(e: &Expr) -> String {
    match &e.kind {
        ExprKind::Name(n) => n.to_string(),
        ExprKind::Member { left, name } => {
            let l = callee_name(left);
            if l.is_empty() {
                name.to_string()
            } else {
                format!("{l}.{name}")
            }
        }
        ExprKind::Apply { left, .. } => callee_name(left),
        _ => String::new(),
    }
}

fn is_none_name(e: &Expr) -> bool {
    matches!(&e.kind, ExprKind::Name(n) if n.as_str() == "none")
}

/// Whether a call with `count` arguments can fill the parameters of `callable`, leaving out only omittable ones.
pub(crate) fn accepts_arguments(callable: &Ty, count: usize) -> bool {
    let omittable = callable.defaults.as_ref().map_or(0, |d| d.len());
    let total = callable.params.len();
    total.saturating_sub(omittable) <= count && count <= total
}

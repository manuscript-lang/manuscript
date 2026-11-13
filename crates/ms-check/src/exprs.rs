//! Expression checking.

use crate::checker::Checker;
use crate::hints::*;
use crate::inference::inference_type_known;
use crate::suggestions;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::Cause;
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
    // A type parameter bounded by a type set is numeric when every member is.
    (t.kind == Kind::Variable
        && t.bounds()
            .iter()
            .any(|b| b.is(Builtin::TypeSet) && !b.args.is_empty() && b.args.iter().all(numeric)))
        || integer(t)
        || float_bits(t).is_some()
        || t.is(Builtin::Decimal)
        || t.is(Builtin::BigInt)
}

/// An unsuffixed number literal, possibly signed.
pub(crate) fn is_plain_literal(syms: ms_syntax::Names, e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Number(t) => {
            !ms_syntax::number::is_decimal(&ms_syntax::number::canonical(syms.str(t)))
        }
        ExprKind::Unary {
            op: UnaryOp::Neg | UnaryOp::Plus,
            operand,
        } => is_plain_literal(syms, operand),
        _ => false,
    }
}

/// The sized number type a literal operand takes from the other operand, if any. Only a literal
/// (or arithmetic over literals) of the same kind adopts it, so a mismatch keeps the ordinary
/// operand-type diagnostic.
impl Checker {
    pub(crate) fn literal_hint<'a>(&self, literal: &Expr, other: &'a Ty) -> Option<&'a Ty> {
        if let ExprKind::List(items) = &literal.kind {
            // A list of plain literals takes the element type of a `List` of a sized number.
            let element =
                (other.is(Builtin::List) && other.args.len() == 1).then(|| &other.args[0])?;
            let all = !items.is_empty()
                && items
                    .iter()
                    .all(|i| self.literal_hint(i, element).is_some());
            return all.then_some(other);
        }
        let fractional = self.literal_tree_fractional(literal)?;
        let sized_int = int_bits(other).is_some() && !other.is(Builtin::Int);
        let sized_float = float_bits(other).is_some() && !other.is(Builtin::Float);
        ((!fractional && sized_int) || (fractional && sized_float)).then_some(other)
    }
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
        .any(|t| t.is(Builtin::Duration) || t.is(Builtin::Instant))
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
    expected.is_some_and(|t| t.is_invalid())
}

/// Whether `name` is a source-location constant (`__LINE__`, `__FILE__`).
pub(crate) fn is_source_location(syms: ms_syntax::Names, name: Name) -> bool {
    matches!(syms.str(name), "__LINE__" | "__FILE__")
}

fn finish_info(mut i: Info) -> Info {
    if i.ty.as_ref().is_some_and(|t| t.is_never()) {
        i.no_return = true;
    }
    i
}

impl Checker {
    /// Checks an expression against an expected type.
    pub(crate) fn expression(&mut self, e: &Expr, expected: Option<&Ty>) -> Info {
        if let Some(x) = expected
            && x.is(Builtin::Optional)
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
        if let Some(x) = expected
            && x.is(Builtin::Optional)
            && x.args.len() == 1
            && matches!(e.kind, ExprKind::Lambda(_))
        {
            // A function literal checks against the payload signature and wraps like any plain value.
            let payload = x.args[0].clone();
            let mut info = self.expression(e, Some(&payload));
            info.wrap_some = Some(x.clone());
            self.set_info(e, info.clone());
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
        if actual.is_never() {
            i.no_return = true;
        }
        if let Some(exp) = expected {
            // A part left invalid by an inference failure was reported already ("cannot infer
            // callback parameter", "cannot infer list element type"); restating it would print
            // `<invalid>` to the user.
            let inference_reported = (invalid_type(&Some(actual.clone()))
                || invalid_type(&Some(exp.clone())))
                && self
                    .p
                    .diagnostics
                    .iter()
                    .any(|d| d.cause.is_inference() && d.pos.line == e.pos.line);
            if !actual.is_invalid()
                && !exp.is_invalid()
                && !inference_reported
                && !compatible(&Some(actual.clone()), exp)
            {
                if self.interface_assignable(&actual, exp) {
                    i.interface_source = Some(actual.clone());
                    i.ty = Some(exp.clone());
                } else if reads_where_var_expected(&actual, exp) {
                    i.function_source = Some(actual.clone());
                    i.ty = Some(exp.clone());
                } else {
                    let mut msg = self.assignment_mismatch(&actual, exp);
                    if let Some(context) = context {
                        msg = with_mismatch_context(msg, &context);
                    }
                    let fix = if suggestions::promise_wait_fits(self.syms, &actual, exp) {
                        suggestions::append_call(&self.m().source, e, "wait()")
                    } else {
                        suggestions::conversion_fix(
                            &self.m().source,
                            e,
                            self.syms.str(actual.id),
                            self.syms.str(exp.id),
                        )
                    };
                    self.type_error_with_fix(e.pos, Cause::Mismatch, msg, fix);
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
                ExprKind::Probe(target) => child(self, target),
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
                    &ms_syntax::number::canonical(self.syms.str(text)),
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
            ExprKind::Probe(target) => return self.probe(e, target),
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
        if ms_syntax::number::is_decimal(text) {
            let ok = self
                .sym(n("Decimal"))
                .zip(self.session.standard_symbol("Decimal"))
                .is_some_and(|(a, b)| Rc::ptr_eq(&a, &b));
            if !ok && !self.unknown_reported(n("Decimal")) {
                // Reported as a missing `Decimal`, so later literals in the file stay quiet.
                self.error_fixed_caused(
                    e.pos,
                    text.len(),
                    ms_syntax::Phase::Resolution,
                    Cause::Unknown(n("Decimal")),
                    "Decimal literal requires the canonical Decimal import; add: import Decimal from \"@std/math/decimal.ms\"".to_string(),
                );
            }
            i.ty = Some(self.session.standard("Decimal", vec![]));
            if !decimal_valid(text) {
                self.type_error(
                    e.pos,
                    "Decimal literal is outside the exact 34-digit representable grid; shorten it to 34 significant digits",
                );
            }
        } else if ms_syntax::number::is_fractional(text) {
            // An expected sized float type gives the literal that type.
            let narrow = expected.filter(|t| float_bits(t) == Some(32) && !t.is(Builtin::Float));
            match (text.parse::<f64>(), narrow) {
                (Ok(_), Some(_)) if ms_syntax::number::float32(text).is_none_or(f64::is_infinite) => self.type_error(
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
            // A zero takes the type of a numeric type set's parameter: `0` is the zero of every member.
            if text == "0"
                && let Some(t) = expected.filter(|t| t.kind == Kind::Variable && numeric(t))
            {
                i.ty = Some(t.clone());
                return finish_info(i);
            }
            // An expected sized integer type gives the literal that type.
            let sized = expected.filter(|t| int_bits(t).is_some() && !t.is(Builtin::Int));
            match sized {
                Some(t) => {
                    if !int_literal_fits(text, negated, t) {
                        let (lo, hi) = int_range(t).unwrap_or_default();
                        self.type_error(
                            e.pos,
                            format!(
                                "literal {}{text} is out of range for {t_t}; use a value between {} and {}",
                                if negated { "-" } else { "" },
                                lo, hi
                            , t_t = t.display(self.syms)),
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
        if self.syms.str(name) == "fixture" && self.scope.binding(name).is_none() {
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
                        "type name requires a constructor call; write {name_t}(field: value, ...) to build a value"
                    , name_t = self.syms.str(name)),
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
                            "a generic function value requires explicit specialization; write {name_t}[Type] or call it with arguments"
                        , name_t = self.syms.str(name)),
                    );
                    i.ty = Some(invalid());
                } else if s.decl.as_ref().is_some_and(|d| {
                    let ps = d.fn_params();
                    ps.iter().any(|p| p.mutable) && ps.iter().any(|p| p.default.is_some())
                }) {
                    // A function value fills omitted parameters in a thunk that cannot also
                    // pass a changed one by address.
                    self.type_error(
                        e.pos,
                        format!(
                            "{name_t} has both a var parameter and a parameter default, so it cannot be a function value; call {name_t} from a closure that supplies the default"
                        , name_t = self.syms.str(name)),
                    );
                    i.ty = Some(invalid());
                }
            }
            return i;
        }
        // Source-location constants: the lowering fills them from the use site.
        if is_source_location(self.syms, name) {
            i.ty = Some(if self.syms.str(name) == "__LINE__" {
                int()
            } else {
                string()
            });
            i.native = Native::Builtin(name);
            return finish_info(i);
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
            self.unknown_error(e.pos, name, msg);
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
            if callable.t().is_invalid() {
                return i;
            }
            let variables = callable
                .method
                .as_ref()
                .map(|m| m.variables.clone())
                .unwrap_or_default();
            let mut opt_args: Vec<Option<Ty>> = args.into_iter().map(Some).collect();
            if opt_args.len() >= required_type_arguments(&variables) {
                opt_args = complete_type_arguments(&variables, &opt_args);
            }
            i.ty = Some(self.specialize(
                &callable.t(),
                &variables,
                &opt_args,
                e.pos,
                &callee_name(self.syms, e),
            ));
            if !callable.native.is_bodiless() {
                i.type_args = opt_args;
            }
            self.set_info(left, i.clone());
            return i;
        }
        // `table[i]` on a module-level constant indexes its value; only functions take type arguments.
        let function = self
            .function_symbol(left)
            .filter(|s| !(s.is_constant() && value.is_some()));
        if let Some(s) = function {
            let args = self.resolve_arguments(types);
            let mut supplied: Vec<Option<Ty>> = args.into_iter().map(Some).collect();
            let vars = s.variables();
            if supplied.len() >= required_type_arguments(&vars) {
                supplied = complete_type_arguments(&vars, &supplied);
            }
            i.symbol = Some(s.clone());
            i.ty = Some(self.specialize(
                &s.ty(self.syms),
                &vars,
                &supplied,
                e.pos,
                &callee_name(self.syms, e),
            ));
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
                self.unknown_error(left.pos, *nm, msg);
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
            if typ.is(Builtin::Optional) {
                self.res_error(
                    e.pos,
                    "Optional has no qualified cases; write none or the plain value where a T? is expected, and put the type on the binding, e.g. x: Int? := none",
                );
                i.ty = Some(invalid());
                return i;
            }
            if let Some(cs) = case_of(&typ, name).filter(|c| c.fields.is_empty()) {
                self.opaque_denied(
                    e.pos,
                    &typ,
                    &format!(
                        "case {name_t} cannot be built here",
                        name_t = self.syms.str(name)
                    ),
                );
                let constructor = self.instantiate(&typ, &[], &[], expected, e.pos);
                i.ty = Some(constructor.clone());
                i.constructor = Some(constructor);
                i.case = Some(cs.name);
                return i;
            }
            let names = crate::stmts::case_names(self.syms, &typ);
            if names.is_empty() {
                self.res_error(
                    e.pos,
                    format!(
                        "{} has no member {}; a type name is followed only by an enum case",
                        self.syms.str(typ.name),
                        self.syms.str(name)
                    ),
                );
            } else {
                self.res_error(
                    e.pos,
                    format!(
                        "unknown or non-nullary alternative case {name_t} of {}; cases: {} (cases with payloads need call syntax)",
                        self.syms.str(typ.name),
                        list(&names, 12),
                        name_t = self.syms.str(name)
                    ),
                );
            }
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
        if rt.is_invalid() {
            return i;
        }
        if rt.kind == Kind::Type
            && self.syms.str(name) != "to_string"
            && let Some(f) = field_of(&rt, name)
        {
            self.opaque_denied(
                e.pos,
                &rt,
                &format!("field {name_t} is hidden", name_t = self.syms.str(name)),
            );
            i.ty = Some(f.ty);
            return i;
        }
        // `m[key] = value` is `m.add(key, value)` and `xs[i] = value` is `xs.set(i, value)`.
        let index_set = self.syms.str(name) == ms_syntax::parser::INDEX_SET;
        let name = match index_set {
            true if rt.is(Builtin::Map) => n("add"),
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
            let mut msg = self.unknown_member(&rt, name);
            if rt.is_source_type(self.syms, suggestions::PROMISE_MODULE, "Promise") {
                // A call that used to wait now returns a promise: `read(p).length()` is `read(p).wait().length()`.
                msg.push_str("; a Promise has `wait()` and `done()`: call `wait()` first");
                let fix = suggestions::append_call(&self.m().source, left, "wait()");
                self.res_error_with_fix(e.pos, msg, fix);
            } else {
                let cause = Cause::UnknownMember {
                    name,
                    optional_receiver: rt.is(Builtin::Optional),
                };
                let len = self.syms.str(name).len();
                self.error_fixed_caused(e.pos, len, ms_syntax::Phase::Resolution, cause, msg);
            }
            // Later diagnostics that only restate the missing member are noise.
            i.ty = Some(invalid());
            return i;
        }
        let m = methods[0].clone();
        i.ty = Some(m.ty.clone());
        i.native = m.native;
        let native = m.native.is_bodiless();
        let source_generic = arity.is_none() && !native && !m.variables.is_empty();
        if (native && !m.variables.is_empty()) || source_generic {
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
            .zip(self.session.standard_symbol("List"))
            .is_some_and(|(a, b)| Rc::ptr_eq(&a, &b));
        if !canonical {
            self.res_error(
                e.pos,
                "list literal requires the canonical List type; rename the shadowing List declaration or binding",
            );
        }
        let mut element: Option<Ty> = None;
        if let Some(exp) = expected
            && exp.is(Builtin::List)
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
                    self.type_error_with_cause(
                        e.pos,
                        Cause::CannotInfer,
                        "cannot infer list element type; add an annotation, e.g. xs: List[Int] := []",
                    );
                }
                invalid()
            }
        };
        self.literal_items(items, &independent, std::slice::from_ref(&element), &mut i);
        i.ty = Some(self.session.standard("List", vec![element]));
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
            .zip(self.session.standard_symbol("Map"))
            .is_some_and(|(a, b)| Rc::ptr_eq(&a, &b));
        if !canonical {
            self.res_error(
                e.pos,
                "map literal requires the canonical Map type; rename the shadowing Map declaration or binding",
            );
        }
        let mut types: [Option<Ty>; 2] = [None, None];
        if let Some(exp) = expected
            && exp.is(Builtin::Map)
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
                self.type_error_with_cause(
                    e.pos,
                    Cause::CannotInfer,
                    "cannot infer map key or value type; add an annotation, e.g. m: Map[String, Int] := {}",
                );
                types[index] = Some(invalid());
            }
        }
        let resolved: Vec<Ty> = types.iter().map(|t| t.clone().expect("type")).collect();
        self.literal_refs(&items, &independent, &resolved, &mut i);
        let map_type = self.session.standard("Map", resolved);
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
                if typ.is_none() && !v.t().is_never() {
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
            && ms_syntax::number::canonical(self.syms.str(t)) == "9223372036854775808"
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
            && !ms_syntax::number::is_decimal(&ms_syntax::number::canonical(self.syms.str(t)))
        {
            let literal = self.infer_number(
                operand,
                &ms_syntax::number::canonical(self.syms.str(t)),
                expected,
                true,
                Info::default(),
            );
            self.set_info(operand, literal.clone());
            i.ty = literal.ty.clone();
            return finish_info(i);
        }
        let hint = expected
            .filter(|_| matches!(op, UnaryOp::Neg | UnaryOp::Plus))
            .filter(|t| self.literal_hint(operand, t).is_some());
        let v = self.expression(operand, hint);
        i.no_return = v.no_return;
        let vt = v.t();
        match op {
            UnaryOp::Not => {
                if !compatible(&Some(vt.clone()), &bool_()) {
                    self.type_error(
                        e.pos,
                        format!(
                            "not requires Bool, found {vt_t}; compare explicitly, e.g. not (x == 0)"
                        , vt_t = vt.display(self.syms)),
                    );
                }
                i.ty = Some(bool_());
            }
            UnaryOp::Try => self.check_try(e, &v, &mut i),
            UnaryOp::Neg | UnaryOp::Plus => {
                if op == UnaryOp::Neg && int_unsigned(&vt) {
                    self.type_error(
                        e.pos,
                        format!("unary - is not defined for {vt_t}; subtract from zero with a wider signed type, e.g. 0 - x.to_int()", vt_t = vt.display(self.syms)),
                    );
                }
                if !numeric(&vt) {
                    self.type_error(
                        e.pos,
                        format!("numeric sign requires an independently known numeric operand, found {vt_t}; apply + or - to Int, Float, Decimal, or BigInt", vt_t = vt.display(self.syms)),
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
        if !result.is(Builtin::Result) || result.args.len() != 2 {
            if result.is_source_type(self.syms, suggestions::PROMISE_MODULE, "Promise")
                && let ExprKind::Unary { operand: inner, .. } = &e.kind
            {
                // A call that used to wait now returns a promise: `try read(p)` is `try read(p).wait()`.
                let fix = suggestions::append_call(&self.m().source, inner, "wait()");
                self.type_error_with_fix(
                    e.pos,
                    Cause::Other,
                    format!("'?' requires a Result, found {result_t}; a promise gives its result from wait(), so write `...wait()?`", result_t = result.display(self.syms)),
                    fix,
                );
                return;
            }
            self.type_error(
                e.pos,
                format!("'?' requires a Result, found {result_t}; apply '?' only to a call returning Result[T, E], and use '?.', 'if value := x', or '.get(default)' for an Optional", result_t = result.display(self.syms)),
            );
            return;
        }
        if let Some(r) = self.return_inference.as_mut() {
            r.context_dependent = true;
        }
        i.ty = Some(result.args[0].clone());
        let enclosing = self.result_ty();
        if !enclosing.is(Builtin::Result) || enclosing.args.len() != 2 {
            self.type_error(
                e.pos,
                "'?' requires an enclosing Result; declare this function to return Result[T, E], or use 'if value := x', '.get(default)', or '.get()'",
            );
            return;
        }
        let failure = result.args[1].clone();
        let returned = enclosing.args[1].clone();
        if same(&returned, &failure) {
            return;
        }
        self.type_error(
            e.pos,
            format!("'?' requires the same error type; this function returns {enclosing_t} but the operand fails with {failure_t}, so change the return error type or translate the error with map_error", enclosing_t = enclosing.display(self.syms), failure_t = failure.display(self.syms)),
        );
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
        if matches!(op, BinaryOp::Eq | BinaryOp::Ne)
            && (self.names_none(left) || self.names_none(right))
        {
            let other = if self.names_none(left) { right } else { left };
            let other = self.expression(other, None);
            if !invalid_ty(&other.t()) {
                self.type_error(
                    e.pos,
                    "none has no type of its own here; test absence with is_none() or is_some(), or compare with the plain value, e.g. x == 3",
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
        let (a, b) = if let Some(hint) = expected.filter(|_| arithmetic).filter(|t| {
            self.literal_hint(left, t).is_some() && self.literal_hint(right, t).is_some()
        }) {
            (
                self.expression(left, Some(hint)),
                self.expression(right, Some(hint)),
            )
        } else if self.literal_tree_fractional(left).is_some()
            && self.literal_tree_fractional(right).is_none()
        {
            let b = self.expression(right, None);
            let bt = b.t();
            (self.expression(left, self.literal_hint(left, &bt)), b)
        } else {
            let a = self.expression(left, None);
            let at = a.t();
            // `opt == 3` compares as `opt == Int?`; the plain side wraps without `some`.
            let wraps = matches!(op, BinaryOp::Eq | BinaryOp::Ne)
                && at.is(Builtin::Optional)
                && at.args.len() == 1;
            let hint = if wraps {
                Some(&at)
            } else {
                self.literal_hint(right, &at)
            };
            (a, self.expression(right, hint))
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
                    format!("logical operands require Bool, found {at_t} and {bt_t}; compare explicitly, e.g. x != 0", at_t = at.display(self.syms), bt_t = bt.display(self.syms)),
                );
            }
            return i;
        }
        if matches!(op, BinaryOp::Add | BinaryOp::Sub) && is_time_operand(&[&at, &bt]) {
            self.check_time_arithmetic(e, op, &at, &bt, &mut i);
            return i;
        }
        let mut common = at.clone();
        if common.is_never() {
            common = bt.clone();
        }
        let comparison = matches!(op, BinaryOp::Eq | BinaryOp::Ne) || is_ordering(op);
        if invalid_ty(&at) || invalid_ty(&bt) {
            // An operand already reported its own error; do not restate it.
            i.ty = Some(if comparison { bool_() } else { invalid() });
            return i;
        }
        let wrapped_operand = matches!(op, BinaryOp::Eq | BinaryOp::Ne)
            && common.is(Builtin::Optional)
            && common.args.len() == 1
            && compatible(&Some(bt.clone()), &common.args[0]);
        if common.is_never()
            || !compatible(&Some(at.clone()), &common)
            || !(wrapped_operand || compatible(&Some(bt.clone()), &common))
        {
            let mut hint = optional_use_hint(self.syms, &at, &bt);
            if hint.is_empty() {
                hint = optional_use_hint(self.syms, &bt, &at);
            }
            if hint.is_empty() {
                hint = result_use_hint(&at, &bt);
            }
            if hint.is_empty() {
                hint = result_use_hint(&bt, &at);
            }
            if hint.is_empty() {
                hint = int_float_mix_hint(self.syms, &at, &bt);
            }
            if hint.is_empty() {
                hint = "convert one side so both have one type (e.g. interpolate into text with \"{value}\", or convert between Int and Float)".to_string();
            }
            let source = self.m().source.clone();
            let compound = suggestions::is_compound_operator(&source, e.pos, op.as_str());
            let fix = match (self.syms.str(at.id), self.syms.str(bt.id)) {
                ("Int", "Float") if !compound => suggestions::to_float(&source, left),
                ("Float", "Int") => suggestions::to_float(&source, right),
                _ => None,
            };
            self.type_error_with_fix(
                e.pos,
                Cause::Other,
                format!(
                    "operator operands require the same independently known type, found {at_t} {} {bt_t}; {hint}",
                    op.as_str()
                , at_t = at.display(self.syms), bt_t = bt.display(self.syms)),
                fix,
            );
            self.unknown_type = true; // later "<invalid>" diagnostics only restate this one
            i.ty = Some(if comparison { bool_() } else { invalid() });
            return i;
        }
        match op {
            BinaryOp::Eq | BinaryOp::Ne => {
                i.ty = Some(bool_());
                if !self.property(&common, crate::contracts::Property::Equal, None) {
                    self.type_error(
                        e.pos,
                        format!("equality requires Equal operands; {common_t} has no equality, so give it 'fn {common_t}.equals(other: {common_t}) Bool' or compare fields", common_t = common.display(self.syms)),
                    );
                }
            }
            _ if is_ordering(op) => {
                i.ty = Some(bool_());
                if !numeric(&common)
                    && !common.is(Builtin::String)
                    && !common.is(Builtin::Duration)
                    && !common.is(Builtin::Instant)
                {
                    self.type_error(
                        e.pos,
                        format!("ordering requires numeric, String, or time operands, found {common_t}; compare a numeric field or convert first", common_t = common.display(self.syms)),
                    );
                }
            }
            _ => {
                i.ty = Some(common.clone());
                if !common.is_invalid()
                    && !numeric(&common)
                    && !(common.is(Builtin::String) && op == BinaryOp::Add)
                    && !(common.is(Builtin::Duration)
                        && matches!(op, BinaryOp::Add | BinaryOp::Sub))
                {
                    self.type_error(e.pos, "arithmetic requires numeric operands");
                }
                self.constant_arithmetic(e, op, left, right, &common);
                if op == BinaryOp::Rem && !integer(&common) && !common.is(Builtin::BigInt) {
                    self.type_error(
                        e.pos,
                        format!("remainder requires integer operands, found {common_t}; convert to Int or use math functions", common_t = common.display(self.syms)),
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
                && compatible(&Some(left.clone()), &self.session.time_type(l))
                && compatible(&Some(right.clone()), &self.session.time_type(r))
            {
                i.ty = Some(self.session.time_type(result));
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
pub(crate) fn callee_name(syms: ms_syntax::Names, e: &Expr) -> String {
    match &e.kind {
        ExprKind::Name(n) => syms.str(n).to_string(),
        ExprKind::Member { left, name } => {
            let l = callee_name(syms, left);
            if l.is_empty() {
                syms.str(name).to_string()
            } else {
                format!("{l}.{name_t}", name_t = syms.str(name))
            }
        }
        ExprKind::Apply { left, .. } => callee_name(syms, left),
        _ => String::new(),
    }
}

/// Whether a call with `count` arguments can fill the parameters of `callable`, leaving out only omittable ones.
pub(crate) fn accepts_arguments(callable: &Ty, count: usize) -> bool {
    let omittable = callable.defaults.as_ref().map_or(0, |d| d.len());
    let total = callable.params.len();
    total.saturating_sub(omittable) <= count && count <= total
}

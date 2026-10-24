//! Diagnostic wording helpers.
//!
//! Diagnostics read "<cause>; <fix>". The cause comes first and keeps the
//! stable wording rule codes classify; the fix names concrete source to write.

use crate::checker::Checker;
use crate::stdlib;
use crate::types::*;
use ms_syntax::ast::Import;
use std::collections::HashSet;

/// Returns the candidate most similar to `name`, or "" when none is near
/// enough to be a plausible misspelling.
pub fn closest(name: &str, candidates: &[String]) -> String {
    let mut best = String::new();
    let mut best_distance = 0usize;
    if name.len() < 3 {
        return best;
    }
    let limit = name.len().div_ceil(3).min(3);
    let lname = name.to_lowercase();
    for candidate in candidates {
        if candidate == name {
            continue;
        }
        let d = edit_distance(&lname, &candidate.to_lowercase());
        if d <= limit
            && (best.is_empty()
                || d < best_distance
                || (d == best_distance && candidate.as_str() < best.as_str()))
        {
            best = candidate.clone();
            best_distance = d;
        }
    }
    best
}

/// Levenshtein distance over scalar values.
pub fn edit_distance(a: &str, b: &str) -> usize {
    let x: Vec<char> = a.chars().collect();
    let y: Vec<char> = b.chars().collect();
    let mut previous: Vec<usize> = (0..=y.len()).collect();
    for i in 1..=x.len() {
        let mut current = vec![0usize; y.len() + 1];
        current[0] = i;
        for j in 1..=y.len() {
            let cost = usize::from(x[i - 1] != y[j - 1]);
            current[j] = (previous[j] + 1)
                .min(current[j - 1] + 1)
                .min(previous[j - 1] + cost);
        }
        previous = current;
    }
    previous[y.len()]
}

/// `; did you mean 'x'?` for a near miss, else "".
pub fn did_you_mean(name: &str, candidates: &[String]) -> String {
    let m = closest(name, candidates);
    if m.is_empty() {
        String::new()
    } else {
        format!("; did you mean '{m}'?")
    }
}

/// Renders at most `limit` sorted names.
pub fn list(names: &[String], limit: usize) -> String {
    let mut names = unique_sorted(names);
    let mut more = "";
    if names.len() > limit {
        more = ", ...";
        names.truncate(limit);
    }
    format!("{}{}", names.join(", "), more)
}

/// Sorted, de-duplicated, non-empty names.
pub fn unique_sorted(names: &[String]) -> Vec<String> {
    let mut seen: HashSet<&str> = HashSet::new();
    let mut out: Vec<String> = Vec::new();
    for name in names {
        if !name.is_empty() && seen.insert(name.as_str()) {
            out.push(name.clone());
        }
    }
    out.sort();
    out
}

/// Strings of symbol names.
pub fn names_of(params: &[Param]) -> Vec<String> {
    params.iter().map(|p| p.name.to_string()).collect()
}

/// The cases a match has not covered.
pub fn missing_cases(cases: &[Case], seen: &HashSet<Name>) -> Vec<String> {
    cases
        .iter()
        .filter(|c| !seen.contains(&c.name))
        .map(|c| c.name.to_string())
        .collect()
}

/// The arm heads a match still needs, e.g. `B(x):`, binding payload fields by name.
pub fn missing_arms(cases: &[Case], seen: &HashSet<Name>) -> String {
    let arms: Vec<String> = cases
        .iter()
        .filter(|c| !seen.contains(&c.name))
        .map(|c| {
            if c.fields.is_empty() {
                format!("'{}:'", c.name)
            } else {
                format!("'{}({}):'", c.name, names_of(&c.fields).join(", "))
            }
        })
        .collect();
    let shown = arms.len().min(12);
    let more = if arms.len() > shown { ", ..." } else { "" };
    format!("{}{more}", arms[..shown].join(", "))
}

/// `Name[T1, T2]` for an arity.
pub fn type_sketch(name: &str, arity: usize) -> String {
    if arity == 0 {
        return format!("{name} with no type arguments");
    }
    let args: Vec<String> = (0..arity)
        .map(|i| format!("T{}", char::from(b'1' + i as u8)))
        .collect();
    format!("{name}[{}]", args.join(", "))
}

/// Names the standard module that exports `name`, if any.
pub fn import_hint(name: &str) -> String {
    if let Some(symbol) = stdlib::standard_symbol(name)
        && stdlib::is_prelude_symbol(&symbol)
    {
        return format!(
            "; use the prelude {name} declaration directly; rename any shadowing binding or declaration"
        );
    }
    for module in stdlib::standard_module_names() {
        if stdlib::standard_exports(module).contains_key(&n(name)) {
            return format!("; add: import {name} from \"{module}\"");
        }
    }
    String::new()
}

const MEMBER_SYNONYMS: &[(&str, &[&str])] = &[
    ("len", &["length", "byte_length", "scalar_length"]),
    ("size", &["length", "byte_length", "scalar_length"]),
    ("count", &["length", "byte_length", "scalar_length"]),
    ("length", &["byte_length", "scalar_length"]),
    ("push", &["append", "add"]),
    ("add", &["append"]),
    ("insert", &["append", "add"]),
    ("delete", &["remove"]),
    ("decode", &["to_string"]),
    ("toString", &["to_string"]),
    ("to_text", &["to_string"]),
];

fn synonym_hint(name: &str, available: &[String]) -> String {
    let mut found: Vec<String> = Vec::new();
    for (key, candidates) in MEMBER_SYNONYMS {
        if *key != name {
            continue;
        }
        for candidate in *candidates {
            for a in available {
                if a == candidate {
                    found.push(format!("'{candidate}'"));
                }
            }
        }
    }
    if found.is_empty() {
        String::new()
    } else {
        format!("; did you mean {}?", found.join(" or "))
    }
}

/// `(a: Int, b: String) Bool` for a function type.
pub fn signature_text(t: &Ty) -> String {
    if t.kind != Kind::Function {
        return String::new();
    }
    let parts: Vec<String> = t
        .params
        .iter()
        .map(|p| format!("{}: {}", p.name, p.ty))
        .collect();
    format!("({}) {}", parts.join(", "), t.result_ty())
}

/// Explains a function passed where names differ.
pub fn label_mismatch_hint(actual: &Ty, expected: &Ty) -> String {
    if actual.kind != Kind::Function || expected.kind != Kind::Function {
        return String::new();
    }
    if actual.params.len() != expected.params.len() {
        return String::new();
    }
    for (i, p) in actual.params.iter().enumerate() {
        if p.name != expected.params[i].name {
            let want = expected.params[i].name;
            return format!(
                "the function's parameter is named {} but this position expects {}; rename the parameter to {}, or wrap the function in a lambda: fn({}: ...) ...: f({}: {})",
                p.name, want, want, want, p.name, want
            );
        }
    }
    String::new()
}

/// Names the fix when an Optional is used where a plain value is required.
pub fn optional_use_hint(actual: &Ty, expected: &Ty) -> String {
    if !actual.is_std("Optional") || actual.args.len() != 1 || expected.is_std("Optional") {
        return String::new();
    }
    format!(
        "{actual} may be absent; unwrap it first with 'if let', get(default), is_some() before get(), or match"
    )
}

/// Names the fix when a Result is used where its success type is required.
pub fn result_use_hint(actual: &Ty, expected: &Ty) -> String {
    if !actual.is_std("Result") || actual.args.is_empty() || !same(&actual.args[0], expected) {
        return String::new();
    }
    "unwrap it with 'try' inside a function that returns a compatible Result, with 'if let', or with '.get()'".to_string()
}

/// Names the explicit conversion between Int and Float.
pub fn number_conversion_hint(actual: &Ty, expected: &Ty) -> String {
    match (actual.id.as_str(), expected.id.as_str()) {
        ("Int", "Float") => "Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value".to_string(),
        ("Float", "Int") => "Float does not convert to Int implicitly; truncate_to_int() returns Optional[Int], so unwrap it, e.g. value.truncate_to_int().get(0)".to_string(),
        ("Int" | "Float" | "Bool", "String") => format!(
            "{actual} does not convert to String implicitly; interpolate it into text, e.g. \"{{value}}\""
        ),
        _ => String::new(),
    }
}

/// A plain value where a Result is required: wrap it in `ok(...)`.
pub fn ok_wrap_hint(actual: &Ty, expected: &Ty) -> String {
    if !expected.is_std("Result") || expected.args.is_empty() || !same(&expected.args[0], actual) {
        return String::new();
    }
    "wrap the value in ok(...), e.g. return ok(value)".to_string()
}

/// A no-argument operation named without parentheses.
pub fn uncalled_function_hint(actual: &Ty, expected: &Ty) -> String {
    let Some(result) = &actual.result else {
        return String::new();
    };
    if actual.kind != Kind::Function
        || expected.kind == Kind::Function
        || !actual.params.is_empty()
        || !same(result, expected)
    {
        return String::new();
    }
    format!("this is a function; call it with parentheses to get its {expected} result")
}

fn plural(count: usize, word: &str) -> String {
    if count == 1 {
        word.to_string()
    } else {
        format!("{word}s")
    }
}

/// A function passed where one with a different parameter count is required.
pub fn arity_mismatch_hint(actual: &Ty, expected: &Ty) -> String {
    if actual.kind != Kind::Function
        || expected.kind != Kind::Function
        || actual.params.len() == expected.params.len()
    {
        return String::new();
    }
    let (have, want) = (actual.params.len(), expected.params.len());
    format!(
        "the function takes {have} {} but this position expects {want}; pass a function with {want} {}, or wrap it in a lambda that supplies the rest",
        plural(have, "parameter"),
        plural(want, "parameter")
    )
}

/// Explains a missing type argument.
pub fn missing_type_argument_hint(
    name: &str,
    missing: Name,
    variables: &[Ty],
    arguments: &[Option<Ty>],
) -> String {
    let parts: Vec<String> = variables
        .iter()
        .enumerate()
        .map(|(i, v)| match arguments.get(i) {
            Some(Some(a)) if !invalid_ty(a) => a.to_string(),
            _ => v.name.to_string(),
        })
        .collect();
    format!(
        "cannot infer type argument {missing} for {name}; write {name}[{}](...) with an explicit type for {missing}; call arguments and the expected result must determine every type parameter",
        parts.join(", ")
    )
}

impl Checker {
    /// Bindings and function declarations visible at the current scope.
    pub(crate) fn value_names(&self) -> Vec<String> {
        let mut names: Vec<String> = Vec::new();
        let mut s = Some(self.scope.clone());
        while let Some(sc) = s {
            names.extend(sc.bindings.borrow().keys().map(|k| k.to_string()));
            s = sc.parent.clone();
        }
        for (name, symbol) in self.names.borrow().iter() {
            if symbol.kind == SymKind::Fn {
                names.push(name.to_string());
            }
        }
        names
    }

    /// Type names visible at the current scope.
    pub(crate) fn type_names(&self) -> Vec<String> {
        let mut names: Vec<String> = Vec::new();
        let mut s = Some(self.scope.clone());
        while let Some(sc) = s {
            names.extend(sc.types.borrow().keys().map(|k| k.to_string()));
            s = sc.parent.clone();
        }
        for (name, symbol) in self.names.borrow().iter() {
            if symbol.kind == SymKind::Type {
                names.push(name.to_string());
            }
        }
        names
    }

    /// Explains an arity error caused by a declaration that replaced the
    /// prelude type of the same name.
    pub(crate) fn prelude_shadow_hint(&self, name: Name) -> String {
        let prelude = stdlib::standard_symbol(name.as_str());
        if let (Some(prelude), Some(declared)) = (prelude, self.sym(name))
            && stdlib::is_prelude_symbol(&prelude)
            && !std::rc::Rc::ptr_eq(&declared, &prelude)
        {
            return format!(
                "; this module's own {name} shadows the prelude {name}, so rename the declaration to use the prelude type"
            );
        }
        String::new()
    }

    /// Explains an unresolved value.
    pub(crate) fn unknown_name(&mut self, name: Name) -> String {
        self.unknown_type = true; // later "<invalid>" diagnostics only restate this one
        let message = format!("unknown binding {name}");
        if name == "this" && self.scope.binding(n("self")).is_some() {
            return format!(
                "{message}; the receiver in an impl method is 'self'; write self instead of this"
            );
        }
        if name == "pass" {
            return format!(
                "{message}; 'pass' is not a keyword, so write 'unit' for an empty block or match arm"
            );
        }
        match name.as_str() {
            "nil" | "null" | "None" | "undefined" => {
                return format!(
                    "{message}; Manuscript has no null: absence is an Optional, written none, and a present value is some(value)"
                );
            }
            "print" | "println" | "printf" | "puts" | "echo" => {
                return format!(
                    "{message}; there is no built-in print: import stdout from \"@std/io.ms\" and call stdout().write(\"text\\n\")"
                );
            }
            _ => {}
        }
        let hint = did_you_mean(name.as_str(), &self.value_names());
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        let hint = import_hint(name.as_str());
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        format!(
            "{message}; declare it with 'let {name} = ...' before use, define 'fn {name}(...)', or import it from a module"
        )
    }

    /// Fields and operations available on a receiver type.
    pub(crate) fn member_names(&self, receiver: &Ty) -> Vec<String> {
        let mut seen: Vec<*const Type> = Vec::new();
        self.member_names_seen(receiver, &mut seen)
    }

    fn member_names_seen(&self, receiver: &Ty, seen: &mut Vec<*const Type>) -> Vec<String> {
        let ptr = std::rc::Rc::as_ptr(receiver);
        if seen.contains(&ptr) {
            return Vec::new();
        }
        seen.push(ptr);
        let mut names: Vec<String> = Vec::new();
        if receiver.kind == Kind::Record {
            names.extend(fields(receiver).iter().map(|f| f.name.to_string()));
        }
        if let Some(def) = &receiver.def {
            names.extend(def.operations.borrow().iter().map(|o| o.name.to_string()));
        }
        if let Some(intrinsic) = stdlib::intrinsic_operations(receiver.id)
            && let Some(def) = &intrinsic.def
        {
            names.extend(def.operations.borrow().iter().map(|o| o.name.to_string()));
        }
        if receiver.kind == Kind::Variable {
            for b in receiver.bounds() {
                names.extend(self.member_names_seen(&b, seen));
            }
        }
        for m in self.p.methods.iter() {
            let Some(name) = m.name() else {
                continue;
            };
            if !self.method_visible(m) {
                continue;
            }
            let mut sub = Subst::new();
            if unify(&m.receiver, receiver, &variable_set(&m.variables), &mut sub) {
                names.push(name.to_string());
            }
        }
        unique_sorted(&names)
    }

    /// Explains a member that several implementations provide.
    pub(crate) fn ambiguous_member(
        &self,
        receiver: &Ty,
        name: Name,
        methods: &[MethodRef],
    ) -> String {
        let contracts: Vec<String> = methods
            .iter()
            .filter_map(|m| m.contract.as_ref().map(|c| c.to_string()))
            .collect();
        let contracts = unique_sorted(&contracts);
        let message = format!("ambiguous member {name} on {receiver}");
        if contracts.len() < 2 {
            return format!("{message}; more than one implementation provides it");
        }
        format!(
            "{message}; it is provided by {}, so call it through an interface view, e.g. {}(value: ...).{name}()",
            contracts.join(", "),
            contracts[0]
        )
    }

    /// Explains an unknown member.
    pub(crate) fn unknown_member(&mut self, receiver: &Ty, name: Name) -> String {
        self.unknown_type = true;
        let message = format!("unknown or ambiguous member {name} on {receiver}");
        let available = self.member_names(receiver);
        if receiver.kind != Kind::Record {
            for f in fields(receiver) {
                if f.name == name {
                    return format!(
                        "member {name} of {receiver} is not readable or assignable; its state is reached only through its operations: {}",
                        available.join(", ")
                    );
                }
            }
        }
        if receiver.is_std("Map") && name == "set" {
            return format!(
                "{message}; 'm[key] = value' assigns only into a List; write m.add(key, value) to insert or replace a Map entry; available: {}",
                available.join(", ")
            );
        }
        if receiver.is_std("List") && name == "join" {
            return format!(
                "{message}; join is only available on List[String] and List[Int]; convert the elements first, e.g. xs.map(transform: fn(value: Float) String: \"{{value}}\").join(separator: \",\")"
            );
        }
        let hint = synonym_hint(name.as_str(), &available);
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        let hint = did_you_mean(name.as_str(), &available);
        if !hint.is_empty() {
            if available.len() <= 40 {
                return format!("{message}{hint}; available: {}", available.join(", "));
            }
            return format!("{message}{hint}");
        }
        if !available.is_empty() {
            if available.len() <= 40 {
                return format!("{message}; available: {}", available.join(", "));
            }
            let first = name.as_str().bytes().next();
            let same_start: Vec<&String> = available
                .iter()
                .filter(|c| first.is_some() && c.bytes().next() == first)
                .collect();
            if !same_start.is_empty() {
                let joined: Vec<&str> = same_start.iter().map(|s| s.as_str()).collect();
                return format!(
                    "{message}; available starting with '{}': {}; {} members in total",
                    &name.as_str()[..1],
                    joined.join(", "),
                    available.len()
                );
            }
            return format!("{message}; available: {}", list(&available, 40));
        }
        format!("{message}; this type has no fields or operations")
    }

    /// Explains an unknown type.
    pub(crate) fn unknown_type_message(&self, name: Name) -> String {
        let message = format!("unknown type {name}");
        let hint = import_hint(name.as_str());
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        let hint = did_you_mean(name.as_str(), &self.type_names());
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        format!(
            "{message}; declare it with 'type {name}:' / 'interface {name}:', declare it as a type parameter, or import it"
        )
    }

    /// Explains a failed import: the module lacks the name, or the name is
    /// private. It lists what the module does export.
    pub(crate) fn export_message(&self, item: &Import) -> String {
        let message = format!("module does not export {}", item.name);
        let mut exports: Vec<String> = Vec::new();
        let path = item.path.as_ref();
        if path.starts_with("@std/") {
            let pn = n(path);
            if !stdlib::is_native_module(pn) && stdlib::standard_source_module(pn).is_none() {
                let hint = did_you_mean(
                    path,
                    &stdlib::standard_module_names()
                        .iter()
                        .map(|s| s.to_string())
                        .collect::<Vec<_>>(),
                );
                return format!("{message}; unknown standard module {path}{hint}");
            }
            exports.extend(
                stdlib::standard_exports(pn.as_str())
                    .keys()
                    .map(|k| k.to_string()),
            );
        } else {
            let target = self.imports.get(self.current_file(), item.id);
            if let Some(names) = target.and_then(|t| self.p.symbols.get(&t)) {
                for (name, symbol) in names.borrow().iter() {
                    if Some(symbol.module) != target || symbol.decl.is_none() {
                        continue;
                    }
                    if symbol.export {
                        exports.push(name.to_string());
                    } else if *name == item.name {
                        return format!(
                            "{message}; it is declared in {path} but not exported, so write 'export' before its declaration"
                        );
                    }
                }
            }
        }
        let hint = did_you_mean(item.name.as_str(), &exports);
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        if exports.is_empty() {
            return format!(
                "{message}; {path} exports nothing; namespace imports are unsupported, so import individual exported declarations"
            );
        }
        format!(
            "{message}; {path} exports: {}; namespace imports are unsupported, so import individual exports with 'import {{ Name, OtherName }} from \"{path}\"'",
            list(&exports, 12)
        )
    }

    /// Adds a view hint only when the expected type itself is an interface.
    pub(crate) fn assignment_mismatch(&mut self, actual: &Ty, expected: &Ty) -> String {
        let message = format_mismatch(actual, expected);
        for hint in [
            label_mismatch_hint(actual, expected),
            optional_use_hint(actual, expected),
            number_conversion_hint(actual, expected),
            ok_wrap_hint(actual, expected),
            uncalled_function_hint(actual, expected),
        ] {
            if !hint.is_empty() {
                return format!("{message}; {hint}");
            }
        }
        if expected.kind != Kind::Contract || actual.id == "<invalid>" {
            return message;
        }
        if self.implements(actual, expected) {
            return format!(
                "{message}; {actual} implements {expected}; write {expected}(value: ...) to create an explicit interface view"
            );
        }
        if let Some(sym) = actual.symbol()
            && sym.native.as_str().is_empty()
            && matches!(actual.kind, Kind::Record | Kind::Alternative)
        {
            return format!(
                "{message}; no applicable 'impl {expected} for {actual}' is visible; declare an implementation before creating an interface view"
            );
        }
        format!(
            "{message}; use a concrete value implementing {expected} and create its explicit interface view with {expected}(value: ...)"
        )
    }

    pub(crate) fn interface_type_member(&mut self, typ: &Ty) -> String {
        self.unknown_type = true;
        format!(
            "{typ} is an interface, not an alternative; declare a concrete type and 'impl {typ} for <Type>:', then construct that concrete type"
        )
    }
}

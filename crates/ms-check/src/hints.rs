//! Diagnostic wording helpers.
//!
//! Diagnostics read "<cause>; <fix>". The cause comes first and keeps the
//! stable wording rule codes classify; the fix names concrete source to write.

use crate::checker::Checker;
use crate::fxmap::HashSet;
use crate::stdlib;
use crate::types::*;
use ms_syntax::ast::Import;
use std::rc::Rc;

/// Returns the candidate most similar to `name`, or "" when none is near
/// enough to be a plausible misspelling.
pub fn closest(name: &str, candidates: &[String]) -> String {
    let mut best = String::new();
    let mut best_key = (0usize, false);
    if name.len() < 3 {
        return best;
    }
    let limit = name.len().div_ceil(3).min(3);
    let lname = name.to_lowercase();
    for candidate in candidates {
        if candidate == name {
            continue;
        }
        let lcandidate = candidate.to_lowercase();
        let d = edit_distance(&lname, &lcandidate);
        // At equal distance a name that extends or truncates the typed one
        // ("testing" for "test") beats an unrelated one.
        let key = (
            d,
            !(lname.starts_with(&lcandidate) || lcandidate.starts_with(&lname)),
        );
        if d <= limit
            && (best.is_empty()
                || key < best_key
                || (key == best_key && candidate.as_str() < best.as_str()))
        {
            best = candidate.clone();
            best_key = key;
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
    let mut seen: HashSet<&str> = HashSet::default();
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
pub fn names_of(syms: ms_syntax::Names, params: &[Param]) -> Vec<String> {
    params
        .iter()
        .map(|p| syms.str(p.name).to_string())
        .collect()
}

/// The cases a match has not covered.
pub fn missing_cases(syms: ms_syntax::Names, cases: &[Case], seen: &HashSet<Name>) -> Vec<String> {
    cases
        .iter()
        .filter(|c| !seen.contains(&c.name))
        .map(|c| syms.str(c.name).to_string())
        .collect()
}

/// The arm heads a match still needs, e.g. `B(x):`, binding payload fields by name.
pub fn missing_arms(syms: ms_syntax::Names, cases: &[Case], seen: &HashSet<Name>) -> String {
    let arms: Vec<String> = cases
        .iter()
        .filter(|c| !seen.contains(&c.name))
        .map(|c| {
            if c.fields.is_empty() {
                format!("'{}:'", syms.str(c.name))
            } else {
                format!(
                    "'{}({}):'",
                    syms.str(c.name),
                    names_of(syms, &c.fields).join(", ")
                )
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
pub fn import_hint(session: &Rc<crate::stdlib::Session>, name: &str) -> String {
    import_hint_for(session, name, false)
}

/// Names a standard module exporting a type usable in an annotation.
pub fn type_import_hint(session: &Rc<crate::stdlib::Session>, name: &str) -> String {
    import_hint_for(session, name, true)
}

fn import_hint_for(session: &Rc<crate::stdlib::Session>, name: &str, types_only: bool) -> String {
    if let Some(symbol) = session.standard_symbol(name)
        && session.is_prelude_symbol(&symbol)
        && (!types_only || symbol.kind == SymKind::Type)
    {
        return format!(
            "; use the prelude {name} declaration directly; rename any shadowing binding or declaration"
        );
    }
    if session.checking_sources() {
        return String::new();
    }
    for module in session.standard_module_names() {
        if session
            .standard_exports(module)
            .get(&n(name))
            .is_some_and(|symbol| !types_only || symbol.kind == SymKind::Type)
        {
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
    ("includes", &["contains"]),
    ("has", &["contains"]),
    ("indexOf", &["index_of"]),
    ("find_index", &["index_of"]),
    ("reduce", &["fold"]),
    ("each", &["for_each"]),
    ("substring", &["slice", "slice_scalars"]),
    ("substr", &["slice", "slice_scalars"]),
    ("charAt", &["scalar_at"]),
    ("char_at", &["scalar_at"]),
    ("sort", &["sorted"]),
    ("trim_left", &["trim_start"]),
    ("trim_right", &["trim_end"]),
    ("to_upper", &["upper"]),
    ("to_lower", &["lower"]),
    ("to_uppercase", &["upper"]),
    ("to_lowercase", &["lower"]),
    ("toUpperCase", &["upper"]),
    ("toLowerCase", &["lower"]),
    ("trimStart", &["trim_start"]),
    ("trimEnd", &["trim_end"]),
    ("to_int", &["parse_int", "truncate_to_int"]),
    ("replace_all", &["replace"]),
    ("replace_n", &["replace", "replace_first"]),
];

/// `fooBar` -> `foo_bar`, or "" when `name` has no uppercase letter.
fn snake_case(name: &str) -> String {
    if !name.bytes().any(|b| b.is_ascii_uppercase()) {
        return String::new();
    }
    let mut out = String::new();
    for c in name.chars() {
        if c.is_ascii_uppercase() {
            out.push('_');
        }
        out.push(c.to_ascii_lowercase());
    }
    out
}

fn synonym_hint(name: &str, available: &[String]) -> String {
    let mut found: Vec<String> = Vec::new();
    let snake = snake_case(name);
    if !snake.is_empty() && available.contains(&snake) {
        found.push(format!("'{snake}'"));
    }
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
pub fn signature_text(syms: ms_syntax::Names, t: &Ty) -> String {
    if t.kind != Kind::Function {
        return String::new();
    }
    let parts: Vec<String> = t
        .params
        .iter()
        .map(|p| {
            format!(
                "{}{}: {}",
                if p.mutable { "var " } else { "" },
                syms.str(p.name),
                p.ty.display(syms)
            )
        })
        .collect();
    let result = t.result_ty();
    // `T!` is the declared spelling of `Result[T, Error]`.
    let result = match result.args.as_slice() {
        [ok, err] if result.is(Builtin::Result) && err.is(Builtin::Error) => {
            format!("{ok_t}!", ok_t = ok.display(syms))
        }
        _ => result.display(syms).to_string(),
    };
    format!("({}) {result}", parts.join(", "))
}

/// The builtin type other languages call by this name.
fn type_alias(name: &str) -> Option<&'static str> {
    Some(match name {
        "Integer" | "long" | "Long" | "i64" | "int64" | "number" | "Number" => "Int",
        "double" | "Double" | "f64" | "float64" => "Float",
        "str" | "Str" | "string" | "char" | "Char" | "Text" => "String",
        "boolean" | "Boolean" | "bool" => "Bool",
        "void" | "Void" | "None" | "NoneType" => "Unit",
        _ => return None,
    })
}

/// Names the fix when an Optional is used where a plain value is required.
pub fn optional_use_hint(syms: ms_syntax::Names, actual: &Ty, expected: &Ty) -> String {
    if !actual.is(Builtin::Optional) || actual.args.len() != 1 || expected.is(Builtin::Optional) {
        return String::new();
    }
    format!(
        "{actual_t} may be absent; unwrap it first with 'if value := x', get(default), is_some() before get(), or match",
        actual_t = actual.display(syms)
    )
}

/// A promise where its result is required: `wait()` gives it.
pub fn promise_use_hint(syms: ms_syntax::Names, actual: &Ty, expected: &Ty) -> String {
    if crate::suggestions::promise_wait_fits(syms, actual, expected) {
        return "a call that waits returns a Promise; call wait() on it to get the result"
            .to_string();
    }
    let is_promise = actual.is_source_type(syms, crate::suggestions::PROMISE_MODULE, "Promise")
        && actual.args.len() == 1;
    if !is_promise || expected.is_source_type(syms, crate::suggestions::PROMISE_MODULE, "Promise") {
        return String::new();
    }
    format!(
        "a call that waits returns a Promise; wait() gives its result, {}!, so call wait() and unwrap it with a trailing '?' or '.get()' before using it as {}",
        actual.args[0].display(syms),
        expected.display(syms)
    )
}

/// Names the explicit conversion between Int and Float.
pub fn number_conversion_hint(syms: ms_syntax::Names, actual: &Ty, expected: &Ty) -> String {
    match (syms.str(actual.id), syms.str(expected.id)) {
        ("Int", "Float") => "Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value".to_string(),
        ("Float", "Int") => "Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get(0)".to_string(),
        ("Int" | "Float" | "Bool", "String") => format!(
            "{actual_t} does not convert to String implicitly; interpolate it into text, e.g. \"{{value}}\""
        , actual_t = actual.display(syms)),
        _ => String::new(),
    }
}

/// A plain value where a Result is required: wrap it in `ok(...)`.
pub fn ok_wrap_hint(actual: &Ty, expected: &Ty) -> String {
    if !expected.is(Builtin::Result) || expected.args.is_empty() || !same(&expected.args[0], actual)
    {
        return String::new();
    }
    "wrap the value in ok(...), e.g. return ok(value)".to_string()
}

/// A no-argument operation named without parentheses.
pub fn uncalled_function_hint(syms: ms_syntax::Names, actual: &Ty, expected: &Ty) -> String {
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
    format!(
        "this is a function; call it with parentheses to get its {expected_t} result",
        expected_t = expected.display(syms)
    )
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
        "the function takes {have} {} but this position expects {want}; pass a function with {want} {}, or wrap it in a closure that supplies the rest",
        plural(have, "parameter"),
        plural(want, "parameter")
    )
}

/// Explains a missing type argument.
pub fn missing_type_argument_hint(
    syms: ms_syntax::Names,
    name: &str,
    missing: &[Name],
    variables: &[Ty],
    arguments: &[Option<Ty>],
) -> String {
    let parts: Vec<String> = variables
        .iter()
        .enumerate()
        .map(|(i, v)| match arguments.get(i) {
            Some(Some(a)) if !invalid_ty(a) => a.display(syms).to_string(),
            _ => syms.str(v.name).to_string(),
        })
        .collect();
    let list = missing
        .iter()
        .map(|m| syms.str(m))
        .collect::<Vec<_>>()
        .join(", ");
    let (noun, each) = if missing.len() == 1 {
        ("argument", "an explicit type for")
    } else {
        ("arguments", "explicit types for")
    };
    format!(
        "cannot infer type {noun} {list} for {name}; write {name}[{}](...) with {each} {list}; call arguments and the expected result must determine every type parameter",
        parts.join(", ")
    )
}

impl Checker {
    /// Bindings and function declarations visible at the current scope.
    pub(crate) fn value_names(&self) -> Vec<String> {
        let mut names: Vec<String> = Vec::new();
        let mut s = Some(self.scope.clone());
        while let Some(sc) = s {
            names.extend(
                sc.bindings
                    .borrow()
                    .keys()
                    .map(|k| self.syms.str(k).to_string()),
            );
            s = sc.parent.clone();
        }
        for (name, symbol) in self.names.borrow().iter() {
            if symbol.kind == SymKind::Fn {
                names.push(self.syms.str(name).to_string());
            }
        }
        names
    }

    /// Type names visible at the current scope that can be written as a type.
    /// `Optional` is the prelude type behind `T?` but has no `Optional[T]` spelling,
    /// so it is never a spelling to suggest.
    pub(crate) fn type_names(&self) -> Vec<String> {
        let mut names: Vec<String> = Vec::new();
        let mut s = Some(self.scope.clone());
        while let Some(sc) = s {
            names.extend(
                sc.types
                    .borrow()
                    .keys()
                    .map(|k| self.syms.str(k).to_string()),
            );
            s = sc.parent.clone();
        }
        for (name, symbol) in self.names.borrow().iter() {
            if symbol.kind == SymKind::Type {
                names.push(self.syms.str(name).to_string());
            }
        }
        names.retain(|name| name != "Optional");
        names
    }

    /// Explains an arity error caused by a declaration that replaced the
    /// prelude type of the same name.
    pub(crate) fn prelude_shadow_hint(&self, name: Name) -> String {
        let prelude = self.session.standard_symbol(self.syms.str(name));
        if let (Some(prelude), Some(declared)) = (prelude, self.sym(name))
            && self.session.is_prelude_symbol(&prelude)
            && !std::rc::Rc::ptr_eq(&declared, &prelude)
        {
            return format!(
                "; this module's own {name_t} shadows the prelude {name_t}, so rename the declaration to use the prelude type",
                name_t = self.syms.str(name)
            );
        }
        String::new()
    }

    /// Explains an unresolved value.
    pub(crate) fn unknown_name(&mut self, name: Name) -> String {
        self.unknown_type = true; // later "<invalid>" diagnostics only restate this one
        let message = format!("unknown binding {name_t}", name_t = self.syms.str(name));
        if self.syms.str(name) == "this" && self.scope.binding(n("self")).is_some() {
            return format!(
                "{message}; the receiver in an impl method is 'self'; write self instead of this"
            );
        }
        if self.syms.str(name) == "this" {
            return format!(
                "{message}; there is no 'this'; inside an impl method the receiver is 'self'"
            );
        }
        if self.syms.str(name) == "pass" {
            return format!(
                "{message}; 'pass' is not a keyword, so write 'unit' for an empty block or match arm"
            );
        }
        match self.syms.str(name) {
            "range" => {
                return format!(
                    "{message}; there is no range function: write start..end for the integers from start up to but excluding end, or range_by from \"@std/collections/collections.ms\" for a stepped list"
                );
            }
            "nil" | "null" | "None" | "undefined" => {
                return format!(
                    "{message}; Manuscript has no null: absence is an Optional, written none, and a present value is just the value, which converts where an Optional is expected"
                );
            }
            "Some" => {
                return format!(
                    "{message}; there is no Some: a plain value converts where an Optional is expected, so pass it directly"
                );
            }
            "Ok" => {
                return format!("{message}; write the lowercase ok(value) for a successful Result");
            }
            "Err" | "err" | "Error" => {
                return format!(
                    "{message}; write error(cause) for a failed Result, where cause has the Result's error type"
                );
            }
            "True" | "False" => {
                return format!("{message}; booleans are lowercase: write true and false");
            }
            "len" => {
                return format!(
                    "{message}; there is no {name_t}() function: call the length member, e.g. xs.length() (String also has byte_length and scalar_length)",
                    name_t = self.syms.str(name)
                );
            }
            "str" | "toString" | "repr" | "sprintf" => {
                return format!(
                    "{message}; to make text, interpolate: \"{{value}}\", or call value.to_string()"
                );
            }
            "int" | "parseInt" | "atoi" | "Number" | "parse_int" => {
                return format!(
                    "{message}; parse text with text.parse_int(), which returns Int?; Float has truncate_to_int()"
                );
            }
            "float" | "parseFloat" | "parse_float" => {
                return format!(
                    "{message}; parse text with parse_float (import parse_float from \"@std/math/math.ms\"), which returns a Result; an Int converts with value.to_float()"
                );
            }
            "Object" | "Array" | "dict" | "list" => {
                return format!(
                    "{message}; use the prelude List[T] and Map[K, V] types without imports; read a Map with m.keys(), m.values() or m.entries()"
                );
            }
            "Math" | "math" => {
                return format!(
                    "{message}; the math functions (floor, sqrt, pow, ...) are in \"@std/math/math.ms\": import floor from \"@std/math/math.ms\""
                );
            }
            "console" | "System" | "fmt" | "os" | "println" | "printf" | "puts" | "echo" => {
                return format!(
                    "{message}; there is no {name_t}: use print(value), which writes any value and a newline; for write errors or bytes import stdout from \"@std/io/io.ms\" and call stdout().write(\"text\\n\")",
                    name_t = self.syms.str(name)
                );
            }
            "spawn" | "Promise" | "Future" | "Thread" | "thread" | "setTimeout" | "setInterval" => {
                return format!(
                    "{message}; there is no free {name_t}: start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\" and call wait() on the returned Promise",
                    name_t = self.syms.str(name)
                );
            }
            "filesystem" | "network" | "commands" | "control" | "system" | "clock"
            | "wall_clock" | "entropy" | "terminal" | "files" => {
                return format!(
                    "{message}; host handle getters were removed: import the operation itself, e.g. read_file from \"@std/os/fs.ms\", connect from \"@std/net/net.ms\", run from \"@std/os/process.ms\", now from \"@std/time.ms\""
                );
            }
            _ => {}
        }
        let hint = did_you_mean(self.syms.str(name), &self.value_names());
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        let hint = import_hint(&self.session, self.syms.str(name));
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        format!(
            "{message}; declare it with '{name_t} := ...' before use, define 'fn {name_t}(...) T:', or import it from a module",
            name_t = self.syms.str(name)
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
        if receiver.kind == Kind::Type {
            names.extend(
                fields(receiver)
                    .iter()
                    .map(|f| self.syms.str(f.name).to_string()),
            );
        }
        if let Some(def) = &receiver.def {
            names.extend(
                def.operations
                    .borrow()
                    .iter()
                    .map(|o| self.syms.str(o.name).to_string()),
            );
        }
        for intrinsic in self.session.intrinsic_operations(receiver.id) {
            if let Some(def) = &intrinsic.def {
                names.extend(
                    def.operations
                        .borrow()
                        .iter()
                        .map(|o| self.syms.str(o.name).to_string()),
                );
            }
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
            let mut sub = Subst::default();
            if unify(&m.receiver, receiver, &variable_set(&m.variables), &mut sub) {
                names.push(self.syms.str(name).to_string());
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
            .filter_map(|m| {
                m.contract
                    .as_ref()
                    .map(|c| c.display(self.syms).to_string())
            })
            .collect();
        let contracts = unique_sorted(&contracts);
        let message = format!(
            "ambiguous member {name_t} on {receiver_t}",
            name_t = self.syms.str(name),
            receiver_t = receiver.display(self.syms)
        );
        if contracts.len() < 2 {
            return format!("{message}; more than one implementation provides it");
        }
        format!(
            "{message}; it is provided by {}, so bind it to the interface first, e.g. view: {} = value; view.{name_t}()",
            contracts.join(", "),
            contracts[0],
            name_t = self.syms.str(name)
        )
    }

    /// Explains a member that exists for the receiver's type constructor but
    /// whose implementation requires a bound the receiver's arguments lack.
    fn unmet_member_bound(&self, receiver: &Ty, name: Name) -> Option<String> {
        for m in self.p.methods.iter() {
            if m.name() != Some(name) || !self.method_visible(m) {
                continue;
            }
            let mut s = Subst::default();
            let (shared, _) = m.split_variables();
            if !unify(&m.receiver, receiver, &variable_set(shared), &mut s) {
                continue;
            }
            for v in shared {
                let Some(actual) = s.get(&v.id) else {
                    continue;
                };
                for b in v.bounds() {
                    let bound = sub(&b, &s);
                    if !self.satisfies(actual, &bound) {
                        let fix = if actual.kind == Kind::Variable {
                            format!(
                                "declare {actual_t}: {bound_t} on the enclosing function",
                                actual_t = actual.display(self.syms),
                                bound_t = bound.display(self.syms)
                            )
                        } else {
                            self.unsatisfied_message(
                                actual,
                                &bound,
                                "use a type that implements it",
                            )
                        };
                        return Some(format!(
                            "{name_t} requires {actual_t} to be {bound_t}; {fix}",
                            name_t = self.syms.str(name),
                            actual_t = actual.display(self.syms),
                            bound_t = bound.display(self.syms)
                        ));
                    }
                }
            }
        }
        None
    }

    /// Explains an unknown member.
    pub(crate) fn unknown_member(&mut self, receiver: &Ty, name: Name) -> String {
        self.unknown_type = true;
        let message = format!(
            "unknown or ambiguous member {name_t} on {receiver_t}",
            name_t = self.syms.str(name),
            receiver_t = receiver.display(self.syms)
        );
        if let Some(reason) = self.unmet_member_bound(receiver, name) {
            return format!("{message}; {reason}");
        }
        let available = self.member_names(receiver);
        if receiver.kind != Kind::Type {
            for f in fields(receiver) {
                if f.name == name {
                    return format!(
                        "member {name_t} of {receiver_t} is not readable or assignable; its state is reached only through its operations: {}",
                        available.join(", "),
                        name_t = self.syms.str(name),
                        receiver_t = receiver.display(self.syms)
                    );
                }
            }
        }
        if receiver.is(Builtin::Optional) {
            let fix = match self.syms.str(name) {
                "unwrap" | "expect" | "value" | "unwrap_or" | "unwrap_or_else" | "or_default"
                | "unwrap_or_default" => {
                    "read an Optional with x.get(default), x.get_or_else(create) for a lazy fallback, or `if value := x:` to test and unwrap; x.get() with no default faults on none"
                }
                "map_or" | "is_some_and" | "flatten" | "filter" => {
                    "use map, and_then, is_some, or `if value := x:`"
                }
                _ => "",
            };
            if !fix.is_empty() {
                return format!("{message}; {fix}");
            }
        }
        if receiver.is(Builtin::Result) {
            let fix = match self.syms.str(name) {
                "unwrap" | "expect" | "unwrap_or" | "unwrap_or_else" | "unwrap_or_default" => {
                    "read a Result with `x?` inside a fn that returns Result, x.get(default), x.get_or_else(create) for a lazy fallback, or `if value := x:`"
                }
                "unwrap_err" | "err" | "ok" => {
                    "inspect a Result with `if value := x:` or is_error()"
                }
                _ => "",
            };
            if !fix.is_empty() {
                return format!("{message}; {fix}");
            }
        }
        if (receiver.is(Builtin::Optional) || receiver.is(Builtin::Result))
            && !receiver.args.is_empty()
            && self
                .member_names(&receiver.args[0])
                .contains(&self.syms.str(name).to_string())
        {
            let (wrapper, unwrap) = if receiver.is(Builtin::Optional) {
                ("an Optional", "`if value := x:` or x.get(default)")
            } else {
                (
                    "a Result",
                    "`x?` inside a fn that returns Result, `if value := x:` or x.get(default)",
                )
            };
            return format!(
                "{message}; the value is {wrapper} of {payload_t}, which has {name_t}: unwrap it first with {unwrap}",
                payload_t = receiver.args[0].display(self.syms),
                name_t = self.syms.str(name)
            );
        }
        if (receiver.is(Builtin::List) || receiver.is(Builtin::Map) || receiver.is(Builtin::Set))
            && matches!(self.syms.str(name), "some" | "every")
        {
            let now = if self.syms.str(name) == "some" {
                "any"
            } else {
                "all"
            };
            return format!(
                "{message}; {name_t}(predicate) is now {now}(predicate)",
                name_t = self.syms.str(name)
            );
        }
        if receiver.is(Builtin::Map) && self.syms.str(name) == "set" {
            return format!(
                "{message}; write m[key] = value or m.add(key, value) to insert or replace a Map entry; available: {}",
                available.join(", ")
            );
        }
        let hint = synonym_hint(self.syms.str(name), &available);
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        let hint = did_you_mean(self.syms.str(name), &available);
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
            let first = self.syms.str(name).bytes().next();
            let same_start: Vec<&String> = available
                .iter()
                .filter(|c| first.is_some() && c.bytes().next() == first)
                .collect();
            if !same_start.is_empty() {
                let joined: Vec<&str> = same_start.iter().map(|s| s.as_str()).collect();
                return format!(
                    "{message}; available starting with '{}': {}; {} members in total",
                    &self.syms.str(name)[..1],
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
        let message = format!("unknown type {name_t}", name_t = self.syms.str(name));
        let hint = type_import_hint(&self.session, self.syms.str(name));
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        if matches!(self.syms.str(name), "Callable" | "Function" | "Func" | "Fn") {
            return format!(
                "{message}; function types are written fn(Int) Int: parameter types in parentheses, then the result type"
            );
        }
        if matches!(self.syms.str(name), "Option" | "Maybe") {
            return format!(
                "{message}; an optional type is written T?, e.g. Int? or (fn(Int) Int)?"
            );
        }
        if let Some(builtin) = type_alias(self.syms.str(name)) {
            return format!("{message}; did you mean '{builtin}'?");
        }
        let hint = did_you_mean(self.syms.str(name), &self.type_names());
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        format!(
            "{message}; declare it with 'type {name_t}:' / 'enum {name_t}:' / 'interface {name_t}:', declare it as a type parameter, or import it",
            name_t = self.syms.str(name)
        )
    }

    /// Explains a failed import: the module lacks the name, or the name is
    /// private. It lists what the module does export.
    pub(crate) fn export_message(&self, item: &Import) -> String {
        let message = format!("module does not export {}", self.syms.str(item.name));
        let mut exports: Vec<String> = Vec::new();
        let path = item.path.as_ref();
        if path.starts_with("@std/") {
            let pn = n(path);
            if !self.session.is_native_module(pn)
                && self.session.standard_source_module(pn).is_none()
            {
                let stem = |p: &str| stdlib::module_stem(p).to_string();
                let names = self.session.standard_module_names();
                let stems: Vec<String> = names.iter().map(|s| stem(s)).collect();
                let mut hint = did_you_mean(&stem(path), &stems);
                // The module name without its extension (`@std/os/env`) is the common slip.
                let with_ext = format!("{path}.ms");
                if names.iter().any(|name| *name == with_ext) {
                    return format!(
                        "unknown standard module {path}; did you mean '{with_ext}'? Import paths end in .ms"
                    );
                }
                // The right module under another folder (`@std/json/json.ms` for `@std/data/json.ms`)
                // has the same stem, which a spelling suggestion does not report.
                let base = |p: &str| p.rsplit('/').next().unwrap_or(p).to_string();
                if hint.is_empty()
                    && let Some(same) = names.iter().find(|name| base(name) == base(path))
                {
                    hint = format!("; did you mean '{same}'?");
                }
                let suggested = hint.split('\'').nth(1).map(str::to_string);
                if let Some(found) = suggested
                    && let Some(full) = names.iter().find(|name| stem(name) == found)
                {
                    hint = format!("; did you mean '{full}'?");
                }
                return format!("unknown standard module {path}{hint}");
            }
            exports.extend(
                self.session
                    .standard_exports(self.syms.str(pn))
                    .keys()
                    .map(|k| self.syms.str(k).to_string()),
            );
        } else {
            let target = self.imports.get(self.current_file(), item.id);
            if let Some(names) = target.and_then(|t| self.p.symbols.get(&t)) {
                for (name, symbol) in names.borrow().iter() {
                    if Some(symbol.module) != target || symbol.decl.is_none() {
                        continue;
                    }
                    if symbol.export {
                        exports.push(self.syms.str(name).to_string());
                    } else if *name == item.name {
                        return format!(
                            "{message}; it is declared in {path} but not exported, so write 'export' before its declaration"
                        );
                    }
                }
            }
        }
        let hint = did_you_mean(self.syms.str(item.name), &exports);
        if !hint.is_empty() {
            return format!("{message}{hint}");
        }
        let elsewhere = import_hint(&self.session, self.syms.str(item.name));
        if let Some(statement) = elsewhere.strip_prefix("; add: ") {
            return format!(
                "{message}; another standard module exports it, so replace this import with: {statement}"
            );
        }
        if exports.is_empty() {
            return format!(
                "{message}; {path} exports nothing; namespace imports are unsupported, so import individual exported declarations"
            );
        }
        format!(
            "{message}; {path} exports: {}; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from \"{path}\"'",
            list(&exports, 12)
        )
    }

    /// Adds a view hint only when the expected type itself is an interface.
    pub(crate) fn assignment_mismatch(&mut self, actual: &Ty, expected: &Ty) -> String {
        if actual.is(Builtin::Optional) && actual.args.len() == 1 && actual.args[0].is_invalid() {
            return format!(
                "expected {expected_t}, found none; none is absent, so it fits only an Optional position: declare the target {expected_t}? or give a value",
                expected_t = expected.display(self.syms)
            );
        }
        let message = format_mismatch(self.syms, actual, expected);
        for hint in [
            optional_use_hint(self.syms, actual, expected),
            number_conversion_hint(self.syms, actual, expected),
            ok_wrap_hint(actual, expected),
            promise_use_hint(self.syms, actual, expected),
            uncalled_function_hint(self.syms, actual, expected),
        ] {
            if !hint.is_empty() {
                return format!("{message}; {hint}");
            }
        }
        if expected.kind != Kind::Contract || actual.is_invalid() {
            return message;
        }
        if crate::contracts::has_generic_operation(expected) {
            return format!(
                "{message}; {expected_t} declares an operation with type parameters of its own, so it bounds a type parameter (`fn f[T: {expected_t}](x: T)`) but cannot type a value",
                expected_t = expected.display(self.syms)
            );
        }
        if self.implements(actual, expected) {
            return format!(
                "{message}; {actual_t} implements {expected_t}, but generic inference does not convert; bind it to an {expected_t}-typed binding first or give the arguments one type",
                actual_t = actual.display(self.syms),
                expected_t = expected.display(self.syms)
            );
        }
        if let Some(sym) = actual.symbol()
            && sym.native == Native::Source
            && matches!(actual.kind, Kind::Type | Kind::Alternative)
        {
            let gap = self.shape_gap(actual, expected).unwrap_or_default();
            return format!(
                "{message}; {actual_t} does not satisfy {expected_t} by its own methods ({gap}); declare each operation as a method of {actual_t} with the interface's exact signature",
                expected_t = expected.display(self.syms),
                actual_t = actual.display(self.syms)
            );
        }
        format!(
            "{message}; use a concrete value implementing {expected_t}",
            expected_t = expected.display(self.syms)
        )
    }

    pub(crate) fn interface_construction_message(&mut self, typ: &Ty) -> String {
        self.unknown_type = true;
        format!(
            "{typ_t} is an interface and cannot be constructed; a type whose methods match {typ_t} passes wherever {typ_t} is expected, so pass the value directly",
            typ_t = typ.display(self.syms)
        )
    }

    pub(crate) fn interface_type_member(&mut self, typ: &Ty) -> String {
        self.unknown_type = true;
        format!(
            "{typ_t} is an interface, not an alternative; declare a concrete type with the methods {typ_t} lists, then construct that concrete type",
            typ_t = typ.display(self.syms)
        )
    }
}

/// Names the conversion when an arithmetic or comparison mixes Int and Float.
pub fn int_float_mix_hint(syms: ms_syntax::Names, a: &Ty, b: &Ty) -> String {
    let (i, f) = (a.display(syms).to_string(), b.display(syms).to_string());
    let mixed = (i == "Int" && f == "Float") || (i == "Float" && f == "Int");
    if mixed {
        "convert the Int with value.to_float(), or the Float with value.truncate_to_int() (returns Int?)".to_string()
    } else {
        String::new()
    }
}

/// Names the real conversion for a built-in type called like a constructor.
pub fn builtin_constructor_hint(syms: ms_syntax::Names, typ: &Ty) -> String {
    match typ.display(syms).to_string().as_str() {
        "String" => "; make text with interpolation \"{value}\" or value.to_string()".to_string(),
        "Int" => "; parse text with text.parse_int() (Int?); Float has truncate_to_int()".to_string(),
        "Float" => "; convert an Int with value.to_float(); parse text with parse_float (import parse_float from \"@std/math/math.ms\")".to_string(),
        _ => String::new(),
    }
}

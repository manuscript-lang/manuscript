//! The review fact model: what the checker established about each callable
//! and type, never text. Collection from a checked program lives beside the
//! inspection it builds on.

use crate::tree::Node;
use std::collections::BTreeMap;

/// What a review compares for one callable or type. `key` is stable across
/// edits (file, kind, name).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Fact {
    pub key: String,
    pub file: String,
    pub kind: String,
    pub name: String,
    /// Display name when it differs from `name`: an impl method reads `Receiver.method`.
    pub label: String,
    pub ty: String,
    pub exported: bool,
    pub line: usize,
    pub effects: Vec<String>,
    pub error: String,
    pub tries: usize,
    /// Bindings whose scope closes a resource.
    pub scopes: usize,
    /// Keys of project entities called.
    pub calls: Vec<String>,
    pub external: Vec<String>,
    /// Record fields, case payloads, or parameters, in declaration order.
    pub slots: Vec<Slot>,
    /// The declared result of a callable.
    pub result: Option<Slot>,
    /// Ownership of the result established by the checker.
    pub result_ownership: ResultOwnership,
    /// The entity's head-side line range, for mapping a diff.
    pub first: usize,
    pub last: usize,
}

/// One typed position: a field, a case payload, a parameter, or a result.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Slot {
    pub name: String,
    pub ty: String,
    /// A `var` parameter: the callee may change the argument.
    pub var: bool,
    /// How a plain parameter is passed, from checked value class and moving-parameter facts.
    pub ownership: ParameterOwnership,
    /// Keys of the project types the written type names (resolved after collection).
    pub refs: Vec<String>,
}

/// Passing mode of a parameter without an explicit `var` annotation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ParameterOwnership {
    #[default]
    Borrow,
    Copy,
    Move,
}

impl Slot {
    /// The checked passing mode, with an explicit exclusive borrow taking priority.
    pub fn passing_mode(&self) -> &'static str {
        if self.var {
            "var"
        } else {
            match self.ownership {
                ParameterOwnership::Copy => "copy",
                ParameterOwnership::Move => "move",
                ParameterOwnership::Borrow => "borrow",
            }
        }
    }
}

/// The checker's result flags distinguish an owned view/wrapper from a borrowed result.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ResultOwnership {
    #[default]
    Owned,
    Borrow,
    View,
    BorrowedOk,
    BorrowedError,
    BorrowedBoth,
}

impl ResultOwnership {
    pub fn label(self) -> &'static str {
        match self {
            Self::Owned => "owned",
            Self::Borrow => "borrow",
            Self::View => "owned view",
            Self::BorrowedOk => "owned; borrowed ok",
            Self::BorrowedError => "owned; borrowed error",
            Self::BorrowedBoth => "owned; borrowed ok and error",
        }
    }
}

/// The fact model of one checked program.
#[derive(Clone, Debug, Default)]
pub struct Facts {
    pub entities: BTreeMap<String, Fact>,
    /// File to imported module paths.
    pub imports: BTreeMap<String, Vec<String>>,
    /// Each callable's ordered significant steps, for the flow and scope views.
    pub flows: BTreeMap<String, Vec<Node>>,
    /// Project file to its source text, for views that show code.
    pub sources: BTreeMap<String, String>,
}

pub fn fact_key(file: &str, kind: &str, name: &str) -> String {
    format!("{file}#{kind}#{name}")
}

pub fn append_unique(list: &mut Vec<String>, value: &str) {
    if !list.iter().any(|existing| existing == value) {
        list.push(value.to_string());
    }
}

/// Extracts E from a function type whose result is `Result[T, E]`.
pub fn error_type(signature: &str) -> String {
    let Some(params) = signature.strip_prefix("fn(") else {
        return String::new();
    };
    let bytes = params.as_bytes();
    let (mut end, mut depth) = (0usize, 1i32);
    while end < bytes.len() && depth > 0 {
        match bytes[end] {
            b'(' => depth += 1,
            b')' => depth -= 1,
            _ => {}
        }
        end += 1;
    }
    let result = params[end..].trim();
    if depth != 0 || !result.starts_with("Result[") {
        return String::new();
    }
    let inner = result.strip_prefix("Result[").unwrap_or(result);
    let inner = inner.strip_suffix(']').unwrap_or(inner);
    let mut depth = 0i32;
    for (i, byte) in inner.bytes().enumerate() {
        match byte {
            b'[' | b'(' => depth += 1,
            b']' | b')' => depth -= 1,
            b',' if depth == 0 => return inner[i + 1..].trim().to_string(),
            _ => {}
        }
    }
    String::new()
}

/// The declaration name from a key.
pub fn key_name(key: &str) -> &str {
    key.splitn(3, '#').last().unwrap_or(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_type_reads_result_error() {
        assert_eq!(error_type("fn(Int) Result[Int, Error]"), "Error");
        assert_eq!(
            error_type("fn(fn(Int) Int) Result[List[Int], Map[String, Int]]"),
            "Map[String, Int]"
        );
        assert_eq!(error_type("fn(Int) Int"), "");
        assert_eq!(error_type("Int"), "");
    }
}

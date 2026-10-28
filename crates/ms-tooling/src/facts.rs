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
    pub ty: String,
    pub exported: bool,
    pub line: usize,
    pub effects: Vec<String>,
    pub error: String,
    pub tries: usize,
    pub withs: usize,
    /// Keys of project entities called.
    pub calls: Vec<String>,
    pub external: Vec<String>,
    /// The entity's head-side line range, for mapping a diff.
    pub first: usize,
    pub last: usize,
}

/// The fact model of one checked program.
#[derive(Clone, Debug, Default)]
pub struct Facts {
    pub entities: BTreeMap<String, Fact>,
    /// File to imported module paths.
    pub imports: BTreeMap<String, Vec<String>>,
    /// Each callable's ordered significant steps, for the flow and scope views.
    pub flows: BTreeMap<String, Vec<Node>>,
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

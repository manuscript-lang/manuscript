//! Declaration-only source excerpts:
//! source names and order are kept, function bodies are omitted.

use crate::source::Source;
use ms_syntax::token::Tok;
use ms_syntax::{ExprKind, Param, TypeKind, TypeParam, TypeRef};

/// `[T: Bound = Default, ...]`, or empty when there are no parameters.
pub fn type_parameters(parameters: &[TypeParam]) -> String {
    if parameters.is_empty() {
        return String::new();
    }
    let values: Vec<String> = parameters
        .iter()
        .map(|p| {
            let mut value = p.name.as_str().to_string();
            if !p.bounds.is_empty() {
                let bounds: Vec<String> = p.bounds.iter().map(type_text).collect();
                value += &format!(": {}", bounds.join(" & "));
            }
            if let Some(default) = &p.default {
                value += &format!(" = {}", type_text(default));
            }
            value
        })
        .collect();
    format!("[{}]", values.join(", "))
}

/// The type's own parameters as the arguments of its `impl` receiver.
pub fn type_arguments(parameters: &[TypeParam]) -> String {
    if parameters.is_empty() {
        return String::new();
    }
    let names: Vec<&str> = parameters.iter().map(|p| p.name.as_str()).collect();
    format!("[{}]", names.join(", "))
}

/// `(name: Type = default, ...)`.
pub fn parameters(parameters: &[Param], source: Option<&Source>) -> String {
    let values: Vec<String> = parameters
        .iter()
        .map(|p| {
            let mut value = format!(
                "{}{}: {}",
                if p.mutable { "var " } else { "" },
                p.name,
                p.ty.as_ref().map_or(String::new(), type_text)
            );
            if p.default.is_some() {
                value += &format!(" = {}", default_text(p, source));
            }
            value
        })
        .collect();
    format!("({})", values.join(", "))
}

/// A written type.
pub fn type_text(t: &TypeRef) -> String {
    match &t.kind {
        TypeKind::Fn { params, result } => {
            format!("fn{} {}", parameters(params, None), type_text(result))
        }
        TypeKind::Named { name, args } => {
            let mut value = name.as_str().to_string();
            if !args.is_empty() {
                let args: Vec<String> = args.iter().map(type_text).collect();
                value += &format!("[{}]", args.join(", "));
            }
            value
        }
    }
}

/// Keeps default expressions in their original source spelling, including
/// calls, strings and suite closures. Only the containing parameter's
/// delimiters end it.
pub fn default_text(parameter: &Param, source: Option<&Source>) -> String {
    if let Some(default) = &parameter.default
        && let ExprKind::Name(text) = &default.kind
    {
        return text.as_str().to_string();
    }
    let Some(source) = source else {
        return "...".to_string();
    };
    let Some(tokens) = source.tokens() else {
        return "...".to_string();
    };
    let text = source.text();
    let from = parameter.pos.offset as usize;
    for (i, &(kind, offset)) in tokens.iter().enumerate() {
        if offset < from || kind != Tok::Assign {
            continue;
        }
        let Some(&(_, start)) = tokens.get(i + 1) else {
            break;
        };
        let mut depth = 0usize;
        for &(next, end) in &tokens[i + 1..] {
            match next {
                Tok::LParen | Tok::LBracket | Tok::LBrace => depth += 1,
                Tok::RParen | Tok::RBracket | Tok::RBrace => {
                    if depth == 0 {
                        return text[start..end].trim().to_string();
                    }
                    depth -= 1;
                }
                Tok::Comma | Tok::Newline if depth == 0 => {
                    return text[start..end].trim().to_string();
                }
                _ => {}
            }
        }
        break;
    }
    "...".to_string()
}

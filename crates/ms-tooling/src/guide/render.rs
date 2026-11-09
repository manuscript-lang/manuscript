//! Declaration-only source excerpts:
//! source names and order are kept, function bodies are omitted.

use crate::guide::source::Source;
use ms_syntax::token::Tok;
use ms_syntax::{ExprKind, Param, TypeKind, TypeParam, TypeRef};

/// `[T: Bound = Default, ...]`, or empty when there are no parameters.
pub fn type_parameters(syms: ms_syntax::Names, parameters: &[TypeParam]) -> String {
    if parameters.is_empty() {
        return String::new();
    }
    let values: Vec<String> = parameters
        .iter()
        .map(|p| {
            let mut value = syms.str(p.name).to_string();
            if !p.bounds.is_empty() {
                let bounds: Vec<String> = p.bounds.iter().map(|a| type_text(syms, a)).collect();
                value += &format!(": {}", bounds.join(" & "));
            }
            if let Some(default) = &p.default {
                value += &format!(" = {}", type_text(syms, default));
            }
            value
        })
        .collect();
    format!("[{}]", values.join(", "))
}

/// The type's own parameters as the arguments of its `impl` receiver.
pub fn type_arguments(syms: ms_syntax::Names, parameters: &[TypeParam]) -> String {
    if parameters.is_empty() {
        return String::new();
    }
    let names: Vec<&str> = parameters.iter().map(|p| syms.str(p.name)).collect();
    format!("[{}]", names.join(", "))
}

/// `(name: Type = default, ...)`.
pub fn parameters(syms: ms_syntax::Names, parameters: &[Param], source: Option<&Source>) -> String {
    let values: Vec<String> = parameters
        .iter()
        .map(|p| {
            let mut value = format!(
                "{}{}: {}",
                if p.mutable { "var " } else { "" },
                syms.str(p.name),
                p.ty.as_ref().map_or(String::new(), |a| type_text(syms, a))
            );
            if p.default.is_some() {
                value += &format!(" = {}", default_text(syms, p, source));
            }
            value
        })
        .collect();
    format!("({})", values.join(", "))
}

/// A written type.
pub fn type_text(syms: ms_syntax::Names, t: &TypeRef) -> String {
    match &t.kind {
        TypeKind::Named { name, args } if syms.str(name) == "Optional" && args.len() == 1 => {
            let payload = &args[0];
            let text = type_text(syms, payload);
            if matches!(payload.kind, TypeKind::Fn { .. }) {
                format!("({text})?")
            } else {
                format!("{text}?")
            }
        }
        TypeKind::Fn { params, result } => {
            let types: Vec<String> = params
                .iter()
                .map(|p| {
                    format!(
                        "{}{}",
                        if p.mutable { "var " } else { "" },
                        p.ty.as_ref().map_or(String::new(), |a| type_text(syms, a))
                    )
                })
                .collect();
            format!("fn({}) {}", types.join(", "), type_text(syms, result))
        }
        TypeKind::Named { name, args } => {
            let mut value = syms.str(name).to_string();
            if !args.is_empty() {
                let args: Vec<String> = args.iter().map(|a| type_text(syms, a)).collect();
                value += &format!("[{}]", args.join(", "));
            }
            value
        }
    }
}

/// Keeps default expressions in their original source spelling, including
/// calls, strings and suite closures. Only the containing parameter's
/// delimiters end it.
pub fn default_text(syms: ms_syntax::Names, parameter: &Param, source: Option<&Source>) -> String {
    if let Some(default) = &parameter.default
        && let ExprKind::Name(text) = &default.kind
    {
        return syms.str(text).to_string();
    }
    let Some(source) = source else {
        return "...".to_string();
    };
    let Some(tokens) = source.tokens() else {
        return "...".to_string();
    };
    let text = source.text();
    let from = parameter.pos.offset as usize;
    let first = tokens.partition_point(|&(_, offset)| offset < from);
    for (i, &(kind, _)) in tokens.iter().enumerate().skip(first) {
        if kind != Tok::Assign {
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

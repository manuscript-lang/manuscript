//! Compare two observations and render a short diff excerpt.

use crate::json::Json;

/// Flatten into `path: value` lines; multi-line strings become one line per line
/// so the excerpt points at the first differing output line.
fn flatten(value: &Json, path: &str, out: &mut Vec<String>) {
    match value {
        Json::Obj(fields) => {
            for (k, v) in fields {
                let next = if path.is_empty() {
                    k.clone()
                } else {
                    format!("{path}.{k}")
                };
                flatten(v, &next, out);
            }
        }
        Json::Arr(items) => {
            if items.is_empty() {
                out.push(format!("{path}: []"));
            }
            for (i, item) in items.iter().enumerate() {
                flatten(item, &format!("{path}[{i}]"), out);
            }
        }
        Json::Str(s) if s.contains('\n') => {
            for (i, line) in s.split('\n').enumerate() {
                out.push(format!("{path}:{}| {line}", i + 1));
            }
        }
        other => out.push(format!("{path}: {}", other.compact())),
    }
}

/// `None` when equal, otherwise a diff excerpt of at most `max_lines` lines per side.
pub fn diff(expected: &Json, actual: &Json, max_lines: usize) -> Option<String> {
    if expected == actual {
        return None;
    }
    let (mut a, mut b) = (Vec::new(), Vec::new());
    flatten(expected, "", &mut a);
    flatten(actual, "", &mut b);
    let prefix = a.iter().zip(&b).take_while(|(x, y)| x == y).count();
    let suffix = a[prefix..]
        .iter()
        .rev()
        .zip(b[prefix..].iter().rev())
        .take_while(|(x, y)| x == y)
        .count();
    let (ea, eb) = (&a[prefix..a.len() - suffix], &b[prefix..b.len() - suffix]);
    let mut text = String::new();
    let show = |label: char, lines: &[String], text: &mut String| {
        for line in lines.iter().take(max_lines) {
            let line: String = line.chars().take(200).collect();
            text.push_str(&format!("{label} {line}\n"));
        }
        if lines.len() > max_lines {
            text.push_str(&format!("{label} ... {} more\n", lines.len() - max_lines));
        }
    };
    show('-', ea, &mut text);
    show('+', eb, &mut text);
    Some(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::parse;

    #[test]
    fn equal_is_none() {
        let j = parse(r#"{"a":1}"#).unwrap();
        assert!(diff(&j, &j, 5).is_none());
    }

    #[test]
    fn points_at_first_differing_line() {
        let a = parse(r#"{"exit_code":0,"stdout":"a\nb\nc\n"}"#).unwrap();
        let b = parse(r#"{"exit_code":0,"stdout":"a\nX\nc\n"}"#).unwrap();
        let d = diff(&a, &b, 5).unwrap();
        assert_eq!(d, "- stdout:2| b\n+ stdout:2| X\n");
    }

    #[test]
    fn length_difference_is_shown() {
        let a = parse(r#"{"d":[1,2]}"#).unwrap();
        let b = parse(r#"{"d":[1]}"#).unwrap();
        assert!(diff(&a, &b, 5).unwrap().contains("- d[1]: 2"));
    }
}

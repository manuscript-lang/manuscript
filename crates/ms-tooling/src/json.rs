//! Output-only JSON with Go `json.MarshalIndent` formatting (two-space
//! indent, HTML-safe escaping), so `--json` documents are byte-identical.

use std::fmt::Write;

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn int(n: i64) -> Json {
        Json::Num(n.to_string())
    }

    pub fn str(s: &str) -> Json {
        Json::Str(s.to_string())
    }

    pub fn strings(list: &[String]) -> Json {
        Json::Arr(list.iter().map(|s| Json::str(s)).collect())
    }

    /// `null` for an empty list, as Go writes a nil slice.
    pub fn strings_or_null(list: &[String]) -> Json {
        if list.is_empty() {
            Json::Null
        } else {
            Json::strings(list)
        }
    }

    pub fn encode(&self) -> String {
        let mut out = String::new();
        self.write(&mut out, 0, false);
        out
    }

    /// Go `json.Marshal`: no whitespace.
    pub fn encode_compact(&self) -> String {
        let mut out = String::new();
        self.write(&mut out, 0, true);
        out
    }

    fn write(&self, out: &mut String, depth: usize, compact: bool) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Num(n) => out.push_str(n),
            Json::Str(s) => write_string(out, s),
            Json::Arr(items) if items.is_empty() => out.push_str("[]"),
            Json::Obj(fields) if fields.is_empty() => out.push_str("{}"),
            Json::Arr(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    newline(out, depth + 1, compact);
                    item.write(out, depth + 1, compact);
                }
                newline(out, depth, compact);
                out.push(']');
            }
            Json::Obj(fields) => {
                out.push('{');
                for (i, (key, value)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    newline(out, depth + 1, compact);
                    write_string(out, key);
                    out.push_str(if compact { ":" } else { ": " });
                    value.write(out, depth + 1, compact);
                }
                newline(out, depth, compact);
                out.push('}');
            }
        }
    }
}

fn newline(out: &mut String, depth: usize, compact: bool) {
    if compact {
        return;
    }
    out.push('\n');
    for _ in 0..depth {
        out.push_str("  ");
    }
}

fn write_string(out: &mut String, text: &str) {
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '<' | '>' | '&' | '\u{2028}' | '\u{2029}' => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

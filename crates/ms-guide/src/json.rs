//! A small JSON value with Go `encoding/json` compatible output
//! (`MarshalIndent` with two spaces and HTML-safe escaping) and a strict reader.

use std::fmt::Write as _;

/// A JSON value; objects keep insertion order like Go struct fields.
#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    /// `null`
    Null,
    /// A boolean.
    Bool(bool),
    /// An integer.
    Int(i64),
    /// A string.
    Str(String),
    /// An array.
    Arr(Vec<Json>),
    /// An object with ordered keys.
    Obj(Vec<(String, Json)>),
}

impl Json {
    /// A string value.
    pub fn str(text: &str) -> Json {
        Json::Str(text.to_string())
    }

    /// An array of strings.
    pub fn strings(items: &[String]) -> Json {
        Json::Arr(items.iter().map(|s| Json::Str(s.clone())).collect())
    }

    /// Go's `json.MarshalIndent(v, "", "  ")`.
    pub fn pretty(&self) -> String {
        let mut out = String::new();
        self.write(&mut out, 0);
        out
    }

    fn write(&self, out: &mut String, depth: usize) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Int(i) => {
                let _ = write!(out, "{i}");
            }
            Json::Str(s) => quote(out, s),
            Json::Arr(items) if items.is_empty() => out.push_str("[]"),
            Json::Arr(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    newline(out, depth + 1);
                    item.write(out, depth + 1);
                }
                newline(out, depth);
                out.push(']');
            }
            Json::Obj(fields) if fields.is_empty() => out.push_str("{}"),
            Json::Obj(fields) => {
                out.push('{');
                for (i, (key, value)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    newline(out, depth + 1);
                    quote(out, key);
                    out.push_str(": ");
                    value.write(out, depth + 1);
                }
                newline(out, depth);
                out.push('}');
            }
        }
    }
}

fn newline(out: &mut String, depth: usize) {
    out.push('\n');
    for _ in 0..depth {
        out.push_str("  ");
    }
}

fn quote(out: &mut String, text: &str) {
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

/// Parses one JSON document.
pub fn parse(text: &str) -> Result<Json, String> {
    let mut p = Parser {
        s: text.as_bytes(),
        i: 0,
    };
    let value = p.value()?;
    p.skip();
    if p.i != p.s.len() {
        return Err(format!("unexpected data at offset {}", p.i));
    }
    Ok(value)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn skip(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\n' | b'\r' | b'\t') {
            self.i += 1;
        }
    }

    fn eat(&mut self, b: u8) -> Result<(), String> {
        self.skip();
        if self.s.get(self.i) == Some(&b) {
            self.i += 1;
            Ok(())
        } else {
            Err(format!("expected {:?} at offset {}", b as char, self.i))
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        self.skip();
        match self.s.get(self.i) {
            Some(b'{') => {
                self.i += 1;
                let mut fields = Vec::new();
                self.skip();
                if self.s.get(self.i) == Some(&b'}') {
                    self.i += 1;
                    return Ok(Json::Obj(fields));
                }
                loop {
                    self.skip();
                    let Json::Str(key) = self.string()? else {
                        unreachable!()
                    };
                    self.eat(b':')?;
                    fields.push((key, self.value()?));
                    self.skip();
                    match self.s.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b'}') => {
                            self.i += 1;
                            return Ok(Json::Obj(fields));
                        }
                        _ => return Err(format!("expected ',' or '}}' at offset {}", self.i)),
                    }
                }
            }
            Some(b'[') => {
                self.i += 1;
                let mut items = Vec::new();
                self.skip();
                if self.s.get(self.i) == Some(&b']') {
                    self.i += 1;
                    return Ok(Json::Arr(items));
                }
                loop {
                    items.push(self.value()?);
                    self.skip();
                    match self.s.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b']') => {
                            self.i += 1;
                            return Ok(Json::Arr(items));
                        }
                        _ => return Err(format!("expected ',' or ']' at offset {}", self.i)),
                    }
                }
            }
            Some(b'"') => self.string(),
            Some(b't') => self.word("true", Json::Bool(true)),
            Some(b'f') => self.word("false", Json::Bool(false)),
            Some(b'n') => self.word("null", Json::Null),
            Some(b'-' | b'0'..=b'9') => {
                let start = self.i;
                self.i += 1;
                while self.i < self.s.len() && self.s[self.i].is_ascii_digit() {
                    self.i += 1;
                }
                std::str::from_utf8(&self.s[start..self.i])
                    .ok()
                    .and_then(|t| t.parse().ok())
                    .map(Json::Int)
                    .ok_or_else(|| format!("bad number at offset {start}"))
            }
            _ => Err(format!("unexpected input at offset {}", self.i)),
        }
    }

    fn word(&mut self, word: &str, value: Json) -> Result<Json, String> {
        if self.s[self.i..].starts_with(word.as_bytes()) {
            self.i += word.len();
            Ok(value)
        } else {
            Err(format!("unexpected input at offset {}", self.i))
        }
    }

    fn string(&mut self) -> Result<Json, String> {
        if self.s.get(self.i) != Some(&b'"') {
            return Err(format!("expected a string at offset {}", self.i));
        }
        self.i += 1;
        let mut out = Vec::new();
        while let Some(&b) = self.s.get(self.i) {
            self.i += 1;
            match b {
                b'"' => {
                    return String::from_utf8(out)
                        .map(Json::Str)
                        .map_err(|e| e.to_string());
                }
                b'\\' => {
                    let esc = *self.s.get(self.i).ok_or("unterminated escape")?;
                    self.i += 1;
                    match esc {
                        b'n' => out.push(b'\n'),
                        b'r' => out.push(b'\r'),
                        b't' => out.push(b'\t'),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'/' => out.push(b'/'),
                        b'"' | b'\\' => out.push(esc),
                        b'u' => {
                            let hex = self.s.get(self.i..self.i + 4).ok_or("short \\u escape")?;
                            let code = u32::from_str_radix(
                                std::str::from_utf8(hex).map_err(|e| e.to_string())?,
                                16,
                            )
                            .map_err(|e| e.to_string())?;
                            self.i += 4;
                            let c = char::from_u32(code).unwrap_or('\u{fffd}');
                            let mut buf = [0u8; 4];
                            out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
                        }
                        _ => return Err(format!("bad escape at offset {}", self.i)),
                    }
                }
                _ => out.push(b),
            }
        }
        Err("unterminated string".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_go_marshal_indent() {
        let value = Json::Obj(vec![
            ("a".into(), Json::Arr(vec![])),
            ("b".into(), Json::Arr(vec![Json::str("x<y&\"z\"\n")])),
            ("c".into(), Json::Obj(vec![])),
        ]);
        assert_eq!(
            value.pretty(),
            "{\n  \"a\": [],\n  \"b\": [\n    \"x\\u003cy\\u0026\\\"z\\\"\\n\"\n  ],\n  \"c\": {}\n}"
        );
    }

    #[test]
    fn reads_what_it_writes() {
        let value = parse("{\"format\": 1, \"backlog\": [\"a\", \"b\\u0041\"]}").unwrap();
        assert_eq!(
            value,
            Json::Obj(vec![
                ("format".into(), Json::Int(1)),
                (
                    "backlog".into(),
                    Json::Arr(vec![Json::str("a"), Json::str("bA")])
                ),
            ])
        );
    }
}

//! A small JSON value, parser and pretty printer with stable key order.
//!
//! The corpus must be reproducible byte for byte, so objects keep insertion
//! order and numbers keep their source text.

use std::fmt::Write as _;

/// A JSON value. Numbers keep their literal text so round trips are exact.
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn obj() -> Json {
        Json::Obj(Vec::new())
    }

    pub fn int(n: i64) -> Json {
        Json::Num(n.to_string())
    }

    pub fn str(s: impl Into<String>) -> Json {
        Json::Str(s.into())
    }

    /// Insert or replace a key on an object (no-op on other values).
    pub fn set(&mut self, key: &str, value: Json) {
        if let Json::Obj(fields) = self {
            if let Some(slot) = fields.iter_mut().find(|(k, _)| k == key) {
                slot.1 = value;
            } else {
                fields.push((key.to_string(), value));
            }
        }
    }

    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(fields) => fields.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn remove(&mut self, key: &str) -> Option<Json> {
        if let Json::Obj(fields) = self {
            let at = fields.iter().position(|(k, _)| k == key)?;
            return Some(fields.remove(at).1);
        }
        None
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Json::Num(n) => n.parse().ok(),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Json]> {
        match self {
            Json::Arr(items) => Some(items),
            _ => None,
        }
    }

    /// Apply `f` to every string in the value (keys are left alone).
    pub fn map_strings(&mut self, f: &dyn Fn(&str) -> String) {
        match self {
            Json::Str(s) => *s = f(s),
            Json::Arr(items) => items.iter_mut().for_each(|i| i.map_strings(f)),
            Json::Obj(fields) => fields.iter_mut().for_each(|(_, v)| v.map_strings(f)),
            _ => {}
        }
    }

    /// Pretty print with two-space indentation and a trailing newline.
    pub fn pretty(&self) -> String {
        let mut out = String::new();
        self.write(&mut out, 0);
        out.push('\n');
        out
    }

    /// Compact single-line form.
    pub fn compact(&self) -> String {
        let mut out = String::new();
        self.write_compact(&mut out);
        out
    }

    fn write_compact(&self, out: &mut String) {
        match self {
            Json::Arr(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    item.write_compact(out);
                }
                out.push(']');
            }
            Json::Obj(fields) => {
                out.push('{');
                for (i, (k, v)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_string(out, k);
                    out.push(':');
                    v.write_compact(out);
                }
                out.push('}');
            }
            other => other.write(out, 0),
        }
    }

    fn write(&self, out: &mut String, depth: usize) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Num(n) => out.push_str(n),
            Json::Str(s) => write_string(out, s),
            Json::Arr(items) if items.is_empty() => out.push_str("[]"),
            Json::Arr(items) => {
                out.push_str("[\n");
                for (i, item) in items.iter().enumerate() {
                    indent(out, depth + 1);
                    item.write(out, depth + 1);
                    if i + 1 < items.len() {
                        out.push(',');
                    }
                    out.push('\n');
                }
                indent(out, depth);
                out.push(']');
            }
            Json::Obj(fields) if fields.is_empty() => out.push_str("{}"),
            Json::Obj(fields) => {
                out.push_str("{\n");
                for (i, (k, v)) in fields.iter().enumerate() {
                    indent(out, depth + 1);
                    write_string(out, k);
                    out.push_str(": ");
                    v.write(out, depth + 1);
                    if i + 1 < fields.len() {
                        out.push(',');
                    }
                    out.push('\n');
                }
                indent(out, depth);
                out.push('}');
            }
        }
    }
}

fn indent(out: &mut String, depth: usize) {
    for _ in 0..depth {
        out.push_str("  ");
    }
}

fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || c == '\u{7f}' => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Parse a JSON document.
pub fn parse(text: &str) -> Result<Json, String> {
    let mut p = Parser {
        bytes: text.as_bytes(),
        at: 0,
    };
    p.skip_ws();
    let value = p.value()?;
    p.skip_ws();
    if p.at != p.bytes.len() {
        return Err(format!("trailing data at byte {}", p.at));
    }
    Ok(value)
}

struct Parser<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Parser<'_> {
    fn skip_ws(&mut self) {
        while self.at < self.bytes.len() && self.bytes[self.at].is_ascii_whitespace() {
            self.at += 1;
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.at).copied()
    }

    fn expect(&mut self, byte: u8) -> Result<(), String> {
        if self.peek() == Some(byte) {
            self.at += 1;
            Ok(())
        } else {
            Err(format!("expected '{}' at byte {}", byte as char, self.at))
        }
    }

    fn literal(&mut self, word: &str, value: Json) -> Result<Json, String> {
        if self.bytes[self.at..].starts_with(word.as_bytes()) {
            self.at += word.len();
            Ok(value)
        } else {
            Err(format!("invalid literal at byte {}", self.at))
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        match self.peek() {
            None => Err("unexpected end of input".into()),
            Some(b'n') => self.literal("null", Json::Null),
            Some(b't') => self.literal("true", Json::Bool(true)),
            Some(b'f') => self.literal("false", Json::Bool(false)),
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(b'[') => {
                self.at += 1;
                let mut items = Vec::new();
                self.skip_ws();
                if self.peek() == Some(b']') {
                    self.at += 1;
                    return Ok(Json::Arr(items));
                }
                loop {
                    self.skip_ws();
                    items.push(self.value()?);
                    self.skip_ws();
                    match self.peek() {
                        Some(b',') => self.at += 1,
                        Some(b']') => {
                            self.at += 1;
                            return Ok(Json::Arr(items));
                        }
                        _ => return Err(format!("expected ',' or ']' at byte {}", self.at)),
                    }
                }
            }
            Some(b'{') => {
                self.at += 1;
                let mut fields = Vec::new();
                self.skip_ws();
                if self.peek() == Some(b'}') {
                    self.at += 1;
                    return Ok(Json::Obj(fields));
                }
                loop {
                    self.skip_ws();
                    let key = self.string()?;
                    self.skip_ws();
                    self.expect(b':')?;
                    self.skip_ws();
                    fields.push((key, self.value()?));
                    self.skip_ws();
                    match self.peek() {
                        Some(b',') => self.at += 1,
                        Some(b'}') => {
                            self.at += 1;
                            return Ok(Json::Obj(fields));
                        }
                        _ => return Err(format!("expected ',' or '}}' at byte {}", self.at)),
                    }
                }
            }
            Some(b'-' | b'0'..=b'9') => {
                let start = self.at;
                while matches!(
                    self.peek(),
                    Some(b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9')
                ) {
                    self.at += 1;
                }
                Ok(Json::Num(
                    String::from_utf8_lossy(&self.bytes[start..self.at]).into_owned(),
                ))
            }
            Some(c) => Err(format!("unexpected '{}' at byte {}", c as char, self.at)),
        }
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let end = self.at + 4;
        let digits = self
            .bytes
            .get(self.at..end)
            .and_then(|b| std::str::from_utf8(b).ok())
            .ok_or("truncated \\u escape")?;
        let value = u32::from_str_radix(digits, 16).map_err(|_| "bad \\u escape".to_string())?;
        self.at = end;
        Ok(value)
    }

    fn string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut out: Vec<u8> = Vec::new();
        loop {
            let Some(b) = self.peek() else {
                return Err("unterminated string".into());
            };
            self.at += 1;
            match b {
                b'"' => break,
                b'\\' => {
                    let Some(e) = self.peek() else {
                        return Err("unterminated escape".into());
                    };
                    self.at += 1;
                    let ch = match e {
                        b'n' => '\n',
                        b't' => '\t',
                        b'r' => '\r',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'/' => '/',
                        b'\\' => '\\',
                        b'"' => '"',
                        b'u' => {
                            let mut code = self.hex4()?;
                            if (0xD800..0xDC00).contains(&code)
                                && self.bytes[self.at..].starts_with(b"\\u")
                            {
                                self.at += 2;
                                let low = self.hex4()?;
                                code =
                                    0x10000 + ((code - 0xD800) << 10) + (low.wrapping_sub(0xDC00));
                            }
                            char::from_u32(code).unwrap_or('\u{fffd}')
                        }
                        _ => return Err(format!("bad escape at byte {}", self.at)),
                    };
                    let mut buf = [0u8; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                b => out.push(b),
            }
        }
        String::from_utf8(out).map_err(|_| "invalid utf-8 in string".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_keeps_order_and_numbers() {
        let text = r#"{"b":1,"a":[true,null,"x\né"],"c":{"n":-12.5e3}}"#;
        let value = parse(text).unwrap();
        assert_eq!(
            value.compact(),
            r#"{"b":1,"a":[true,null,"x\né"],"c":{"n":-12.5e3}}"#
        );
        assert_eq!(parse(&value.pretty()).unwrap(), value);
    }

    #[test]
    fn rejects_trailing_data() {
        assert!(parse("{} x").is_err());
        assert!(parse("[1,").is_err());
    }

    #[test]
    fn surrogate_pairs_decode() {
        assert_eq!(parse(r#""😀""#).unwrap(), Json::Str("😀".into()));
    }

    #[test]
    fn set_get_remove() {
        let mut v = Json::obj();
        v.set("a", Json::int(1));
        v.set("a", Json::int(2));
        assert_eq!(v.get("a").and_then(Json::as_i64), Some(2));
        assert!(v.remove("a").is_some());
        assert!(v.get("a").is_none());
    }
}

//! A small JSON value with a parser and a compact writer.
//!
//! Objects keep insertion order; numbers keep their written spelling so a
//! request id is echoed exactly as the client sent it.

use std::fmt::Write;

/// A JSON value.
#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    /// `null`.
    Null,
    /// `true` or `false`.
    Bool(bool),
    /// A number, in its written spelling.
    Num(String),
    /// A string.
    Str(String),
    /// An array.
    Arr(Vec<Json>),
    /// An object, in insertion order.
    Obj(Vec<(String, Json)>),
}

/// Builds an object from key and value pairs.
pub fn obj<const N: usize>(fields: [(&str, Json); N]) -> Json {
    Json::Obj(
        fields
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect(),
    )
}

impl From<&str> for Json {
    fn from(s: &str) -> Json {
        Json::Str(s.to_string())
    }
}
impl From<String> for Json {
    fn from(s: String) -> Json {
        Json::Str(s)
    }
}
impl From<bool> for Json {
    fn from(b: bool) -> Json {
        Json::Bool(b)
    }
}
impl From<i64> for Json {
    fn from(n: i64) -> Json {
        Json::Num(n.to_string())
    }
}
impl From<usize> for Json {
    fn from(n: usize) -> Json {
        Json::Num(n.to_string())
    }
}
impl From<u32> for Json {
    fn from(n: u32) -> Json {
        Json::Num(n.to_string())
    }
}
impl<T: Into<Json>> From<Vec<T>> for Json {
    fn from(v: Vec<T>) -> Json {
        Json::Arr(v.into_iter().map(Into::into).collect())
    }
}
impl<T: Into<Json>> From<Option<T>> for Json {
    fn from(v: Option<T>) -> Json {
        v.map_or(Json::Null, Into::into)
    }
}

impl Json {
    /// The member named `key` of an object.
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(fields) => fields.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// Sets (or appends) a member of an object.
    pub fn set(&mut self, key: &str, value: Json) {
        if let Json::Obj(fields) = self {
            match fields.iter_mut().find(|(k, _)| k == key) {
                Some(slot) => slot.1 = value,
                None => fields.push((key.to_string(), value)),
            }
        }
    }

    /// The string, if this is one.
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    /// The number as an integer, if it is a whole number that fits.
    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Json::Num(n) => n.parse::<i64>().ok().or_else(|| {
                let f: f64 = n.parse().ok()?;
                (f.fract() == 0.0 && f.abs() < 9.0e15).then_some(f as i64)
            }),
            _ => None,
        }
    }

    /// The boolean, if this is one.
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }

    /// The elements, if this is an array.
    pub fn as_array(&self) -> Option<&[Json]> {
        match self {
            Json::Arr(items) => Some(items),
            _ => None,
        }
    }

    /// Whether this is `null`.
    pub fn is_null(&self) -> bool {
        matches!(self, Json::Null)
    }

    /// The compact encoding.
    pub fn encode(&self) -> String {
        let mut out = String::new();
        self.write(&mut out);
        out
    }

    fn write(&self, out: &mut String) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(true) => out.push_str("true"),
            Json::Bool(false) => out.push_str("false"),
            Json::Num(n) => out.push_str(n),
            Json::Str(s) => write_string(out, s),
            Json::Arr(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    item.write(out);
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
                    v.write(out);
                }
                out.push('}');
            }
        }
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
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

const MAX_DEPTH: usize = 512;

/// Parses one JSON document; trailing non-space input is an error.
pub fn parse(text: &[u8]) -> Result<Json, String> {
    let mut parser = Parser { s: text, at: 0 };
    let value = parser.value(0)?;
    parser.space();
    if parser.at != text.len() {
        return Err("trailing data after JSON value".to_string());
    }
    Ok(value)
}

struct Parser<'a> {
    s: &'a [u8],
    at: usize,
}

impl Parser<'_> {
    fn space(&mut self) {
        while matches!(self.s.get(self.at), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.at += 1;
        }
    }

    fn eat(&mut self, byte: u8) -> bool {
        if self.s.get(self.at) == Some(&byte) {
            self.at += 1;
            true
        } else {
            false
        }
    }

    fn word(&mut self, word: &str, value: Json) -> Result<Json, String> {
        if self.s[self.at..].starts_with(word.as_bytes()) {
            self.at += word.len();
            Ok(value)
        } else {
            Err("invalid literal".to_string())
        }
    }

    fn value(&mut self, depth: usize) -> Result<Json, String> {
        if depth > MAX_DEPTH {
            return Err("nesting too deep".to_string());
        }
        self.space();
        match self.s.get(self.at) {
            None => Err("unexpected end of JSON input".to_string()),
            Some(b'n') => self.word("null", Json::Null),
            Some(b't') => self.word("true", Json::Bool(true)),
            Some(b'f') => self.word("false", Json::Bool(false)),
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(b'[') => {
                self.at += 1;
                let mut items = Vec::new();
                self.space();
                if self.eat(b']') {
                    return Ok(Json::Arr(items));
                }
                loop {
                    items.push(self.value(depth + 1)?);
                    self.space();
                    if self.eat(b',') {
                        continue;
                    }
                    if self.eat(b']') {
                        return Ok(Json::Arr(items));
                    }
                    return Err("expected , or ] in array".to_string());
                }
            }
            Some(b'{') => {
                self.at += 1;
                let mut fields: Vec<(String, Json)> = Vec::new();
                self.space();
                if self.eat(b'}') {
                    return Ok(Json::Obj(fields));
                }
                loop {
                    self.space();
                    if self.s.get(self.at) != Some(&b'"') {
                        return Err("expected object key".to_string());
                    }
                    let key = self.string()?;
                    self.space();
                    if !self.eat(b':') {
                        return Err("expected : after object key".to_string());
                    }
                    let value = self.value(depth + 1)?;
                    // The last duplicate wins, like encoding/json.
                    match fields.iter_mut().find(|(k, _)| *k == key) {
                        Some(slot) => slot.1 = value,
                        None => fields.push((key, value)),
                    }
                    self.space();
                    if self.eat(b',') {
                        continue;
                    }
                    if self.eat(b'}') {
                        return Ok(Json::Obj(fields));
                    }
                    return Err("expected , or } in object".to_string());
                }
            }
            Some(b'-' | b'0'..=b'9') => self.number(),
            Some(_) => Err("invalid character in JSON input".to_string()),
        }
    }

    fn number(&mut self) -> Result<Json, String> {
        let start = self.at;
        self.eat(b'-');
        let digits = |p: &mut Parser| {
            let from = p.at;
            while matches!(p.s.get(p.at), Some(b'0'..=b'9')) {
                p.at += 1;
            }
            p.at > from
        };
        if self.s.get(self.at) == Some(&b'0') {
            self.at += 1;
        } else if !digits(self) {
            return Err("invalid number".to_string());
        }
        if self.eat(b'.') && !digits(self) {
            return Err("invalid number".to_string());
        }
        if matches!(self.s.get(self.at), Some(b'e' | b'E')) {
            self.at += 1;
            if matches!(self.s.get(self.at), Some(b'+' | b'-')) {
                self.at += 1;
            }
            if !digits(self) {
                return Err("invalid number".to_string());
            }
        }
        Ok(Json::Num(
            String::from_utf8_lossy(&self.s[start..self.at]).into_owned(),
        ))
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let digits = self
            .s
            .get(self.at..self.at + 4)
            .ok_or("invalid unicode escape")?;
        let text = std::str::from_utf8(digits).map_err(|_| "invalid unicode escape")?;
        let value = u32::from_str_radix(text, 16).map_err(|_| "invalid unicode escape")?;
        self.at += 4;
        Ok(value)
    }

    fn string(&mut self) -> Result<String, String> {
        self.at += 1;
        let mut out = String::new();
        loop {
            let start = self.at;
            while let Some(&b) = self.s.get(self.at) {
                if b == b'"' || b == b'\\' || b < 0x20 {
                    break;
                }
                self.at += 1;
            }
            // Invalid UTF-8 becomes U+FFFD, as encoding/json does.
            out.push_str(&String::from_utf8_lossy(&self.s[start..self.at]));
            match self.s.get(self.at) {
                None => return Err("unterminated string".to_string()),
                Some(b'"') => {
                    self.at += 1;
                    return Ok(out);
                }
                Some(b'\\') => {
                    self.at += 1;
                    let escape = *self.s.get(self.at).ok_or("unterminated string")?;
                    self.at += 1;
                    match escape {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let first = self.hex4()?;
                            let code = if (0xd800..0xdc00).contains(&first)
                                && self.s[self.at..].starts_with(b"\\u")
                            {
                                let save = self.at;
                                self.at += 2;
                                let second = self.hex4()?;
                                if (0xdc00..0xe000).contains(&second) {
                                    0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00)
                                } else {
                                    self.at = save;
                                    0xfffd
                                }
                            } else {
                                first
                            };
                            out.push(char::from_u32(code).unwrap_or('\u{fffd}'));
                        }
                        _ => return Err("invalid escape in string".to_string()),
                    }
                }
                Some(_) => return Err("control character in string".to_string()),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_values() {
        let text = r#"{"a":[1,2.5,-3e2,true,null],"b":"x\n\u00e9\ud83d\ude00","c":{}}"#;
        let value = parse(text.as_bytes()).unwrap();
        assert_eq!(value.get("b").unwrap().as_str(), Some("x\né😀"));
        assert_eq!(parse(value.encode().as_bytes()).unwrap(), value);
    }

    #[test]
    fn rejects_malformed_input() {
        for bad in ["", "{", "[1,]", "{\"a\" 1}", "01", "\"\\x\"", "1 2", "tru"] {
            assert!(parse(bad.as_bytes()).is_err(), "{bad}");
        }
    }

    #[test]
    fn keeps_number_spelling() {
        let value = parse(b"[1.0, 10]").unwrap();
        assert_eq!(value.encode(), "[1.0,10]");
    }
}

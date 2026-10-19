//! A small order-preserving JSON value with Go `encoding/json` compatible
//! output (two-space indent, HTML-safe escaping, trailing newline from
//! [`Json::encode`]) so `--json` documents are byte-identical to the Go ones.

use std::fmt::Write;

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    /// The number exactly as it is to be written.
    Num(String),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn int(n: i64) -> Json {
        Json::Num(n.to_string())
    }

    pub fn str(s: impl Into<String>) -> Json {
        Json::Str(s.into())
    }

    /// Start an object; chain [`Json::with`].
    pub fn object() -> Json {
        Json::Obj(Vec::new())
    }

    pub fn with(mut self, key: &str, value: Json) -> Json {
        if let Json::Obj(fields) = &mut self {
            fields.push((key.to_string(), value));
        }
        self
    }

    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(fields) => fields.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Json]> {
        match self {
            Json::Arr(items) => Some(items),
            _ => None,
        }
    }

    /// Indented encoding followed by a newline, like `json.Encoder` with `SetIndent("", "  ")`.
    pub fn encode(&self) -> String {
        let mut out = String::new();
        self.write(&mut out, 0);
        out.push('\n');
        out
    }

    fn write(&self, out: &mut String, depth: usize) {
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
                    newline(out, depth + 1);
                    item.write(out, depth + 1);
                }
                newline(out, depth);
                out.push(']');
            }
            Json::Obj(fields) => {
                out.push('{');
                for (i, (key, value)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    newline(out, depth + 1);
                    write_string(out, key);
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

/// Go's encoder escapes `<`, `>`, `&`, U+2028 and U+2029 in addition to the JSON basics.
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

/// Parse one JSON document; `None` when it is not valid JSON (`json.Valid`).
pub fn parse(text: &str) -> Option<Json> {
    let mut parser = Parser { bytes: text.as_bytes(), pos: 0 };
    parser.skip_space();
    let value = parser.value(0)?;
    parser.skip_space();
    (parser.pos == parser.bytes.len()).then_some(value)
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl Parser<'_> {
    fn skip_space(&mut self) {
        while matches!(self.bytes.get(self.pos), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.pos += 1;
        }
    }

    fn eat(&mut self, byte: u8) -> bool {
        if self.bytes.get(self.pos) == Some(&byte) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn literal(&mut self, word: &str) -> bool {
        if self.bytes[self.pos..].starts_with(word.as_bytes()) {
            self.pos += word.len();
            true
        } else {
            false
        }
    }

    fn value(&mut self, depth: usize) -> Option<Json> {
        if depth > 10_000 {
            return None;
        }
        match self.bytes.get(self.pos)? {
            b'{' => {
                self.pos += 1;
                let mut fields = Vec::new();
                self.skip_space();
                if self.eat(b'}') {
                    return Some(Json::Obj(fields));
                }
                loop {
                    self.skip_space();
                    let key = self.string()?;
                    self.skip_space();
                    if !self.eat(b':') {
                        return None;
                    }
                    self.skip_space();
                    let value = self.value(depth + 1)?;
                    fields.push((key, value));
                    self.skip_space();
                    if self.eat(b',') {
                        continue;
                    }
                    return self.eat(b'}').then_some(Json::Obj(fields));
                }
            }
            b'[' => {
                self.pos += 1;
                let mut items = Vec::new();
                self.skip_space();
                if self.eat(b']') {
                    return Some(Json::Arr(items));
                }
                loop {
                    self.skip_space();
                    items.push(self.value(depth + 1)?);
                    self.skip_space();
                    if self.eat(b',') {
                        continue;
                    }
                    return self.eat(b']').then_some(Json::Arr(items));
                }
            }
            b'"' => self.string().map(Json::Str),
            b't' => self.literal("true").then_some(Json::Bool(true)),
            b'f' => self.literal("false").then_some(Json::Bool(false)),
            b'n' => self.literal("null").then_some(Json::Null),
            _ => self.number(),
        }
    }

    fn number(&mut self) -> Option<Json> {
        let start = self.pos;
        self.eat(b'-');
        match self.bytes.get(self.pos)? {
            b'0' => self.pos += 1,
            b'1'..=b'9' => self.digits(),
            _ => return None,
        }
        if self.eat(b'.') {
            let before = self.pos;
            self.digits();
            if self.pos == before {
                return None;
            }
        }
        if self.eat(b'e') || self.eat(b'E') {
            if !self.eat(b'+') {
                self.eat(b'-');
            }
            let before = self.pos;
            self.digits();
            if self.pos == before {
                return None;
            }
        }
        Some(Json::Num(String::from_utf8_lossy(&self.bytes[start..self.pos]).into_owned()))
    }

    fn digits(&mut self) {
        while matches!(self.bytes.get(self.pos), Some(b'0'..=b'9')) {
            self.pos += 1;
        }
    }

    fn string(&mut self) -> Option<String> {
        if !self.eat(b'"') {
            return None;
        }
        let mut out: Vec<u8> = Vec::new();
        loop {
            let byte = *self.bytes.get(self.pos)?;
            self.pos += 1;
            match byte {
                b'"' => return Some(String::from_utf8_lossy(&out).into_owned()),
                b'\\' => {
                    let escape = *self.bytes.get(self.pos)?;
                    self.pos += 1;
                    match escape {
                        b'"' | b'\\' | b'/' => out.push(escape),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'n' => out.push(b'\n'),
                        b'r' => out.push(b'\r'),
                        b't' => out.push(b'\t'),
                        b'u' => {
                            let mut code = self.hex4()?;
                            if (0xd800..0xdc00).contains(&code) && self.bytes[self.pos..].starts_with(b"\\u") {
                                let save = self.pos;
                                self.pos += 2;
                                match self.hex4() {
                                    Some(low) if (0xdc00..0xe000).contains(&low) => {
                                        code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
                                    }
                                    _ => self.pos = save,
                                }
                            }
                            let c = char::from_u32(code).unwrap_or('\u{fffd}');
                            let mut buf = [0u8; 4];
                            out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
                        }
                        _ => return None,
                    }
                }
                0..=0x1f => return None,
                _ => out.push(byte),
            }
        }
    }

    fn hex4(&mut self) -> Option<u32> {
        let digits = self.bytes.get(self.pos..self.pos + 4)?;
        let mut value = 0;
        for &d in digits {
            value = value * 16 + (d as char).to_digit(16)?;
        }
        self.pos += 4;
        Some(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_escape() {
        let text = "{\"a\":[1,2.5e3,{\"b\":null}],\"c\":\"x<y>&\\n\",\"d\":[],\"e\":{}}";
        let value = parse(text).unwrap();
        assert_eq!(
            value.encode(),
            "{\n  \"a\": [\n    1,\n    2.5e3,\n    {\n      \"b\": null\n    }\n  ],\n  \"c\": \"x\\u003cy\\u003e\\u0026\\n\",\n  \"d\": [],\n  \"e\": {}\n}\n"
        );
    }

    #[test]
    fn rejects_invalid() {
        for bad in ["", "{", "[1,]", "{\"a\" 1}", "01", "\"\\q\"", "nul", "1 2"] {
            assert!(parse(bad).is_none(), "{bad}");
        }
    }
}

//! A minimal JSON reader for `bindings.json` (objects and strings only).

use std::collections::BTreeMap;

/// A parsed JSON value.
#[derive(Debug, Clone)]
pub enum Json {
    /// A string.
    Str(String),
    /// An object.
    Obj(BTreeMap<String, Json>),
}

impl Json {
    /// The object's entries, or empty.
    pub fn entries(&self) -> BTreeMap<String, Json> {
        match self {
            Json::Obj(o) => o.clone(),
            Json::Str(_) => BTreeMap::new(),
        }
    }

    /// The string value, or empty.
    pub fn text(&self) -> &str {
        match self {
            Json::Str(s) => s,
            Json::Obj(_) => "",
        }
    }
}

/// Parses an object/string-only JSON document.
pub fn parse(text: &str) -> Result<Json, String> {
    let mut p = Parser {
        s: text.as_bytes(),
        i: 0,
    };
    let v = p.value()?;
    p.ws();
    if p.i != p.s.len() {
        return Err("trailing characters".into());
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && self.s[self.i].is_ascii_whitespace() {
            self.i += 1;
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        self.ws();
        match self.s.get(self.i) {
            Some(b'{') => {
                self.i += 1;
                let mut map = BTreeMap::new();
                loop {
                    self.ws();
                    if self.s.get(self.i) == Some(&b'}') {
                        self.i += 1;
                        return Ok(Json::Obj(map));
                    }
                    let key = self.string()?;
                    self.ws();
                    if self.s.get(self.i) != Some(&b':') {
                        return Err("expected ':'".into());
                    }
                    self.i += 1;
                    let v = self.value()?;
                    map.insert(key, v);
                    self.ws();
                    if self.s.get(self.i) == Some(&b',') {
                        self.i += 1;
                    }
                }
            }
            Some(b'"') => Ok(Json::Str(self.string()?)),
            _ => Err("unsupported JSON value".into()),
        }
    }

    fn string(&mut self) -> Result<String, String> {
        if self.s.get(self.i) != Some(&b'"') {
            return Err("expected string".into());
        }
        self.i += 1;
        let mut out = Vec::new();
        while let Some(&c) = self.s.get(self.i) {
            self.i += 1;
            match c {
                b'"' => return String::from_utf8(out).map_err(|e| e.to_string()),
                b'\\' => {
                    let e = *self.s.get(self.i).ok_or("bad escape")?;
                    self.i += 1;
                    out.push(match e {
                        b'n' => b'\n',
                        b't' => b'\t',
                        other => other,
                    });
                }
                c => out.push(c),
            }
        }
        Err("unterminated string".into())
    }
}

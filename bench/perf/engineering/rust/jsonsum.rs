use std::collections::HashMap;
use std::io::Read;

// A generic JSON tree, as a library such as serde_json::Value would give.
enum Value {
    Null,
    Bool(bool),
    Num(i64),
    Str(String),
    Arr(Vec<Value>),
    Obj(Vec<(String, Value)>),
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn skip(&mut self) {
        while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\n' | b'\t' | b'\r') {
            self.i += 1;
        }
    }

    fn string(&mut self) -> String {
        self.i += 1;
        let mut out = Vec::new();
        while self.b[self.i] != b'"' {
            if self.b[self.i] == b'\\' {
                self.i += 1;
                out.push(match self.b[self.i] {
                    b'n' => b'\n',
                    b't' => b'\t',
                    c => c,
                });
            } else {
                out.push(self.b[self.i]);
            }
            self.i += 1;
        }
        self.i += 1;
        String::from_utf8(out).unwrap()
    }

    fn value(&mut self) -> Value {
        self.skip();
        match self.b[self.i] {
            b'{' => {
                self.i += 1;
                let mut members = Vec::new();
                self.skip();
                if self.b[self.i] == b'}' {
                    self.i += 1;
                    return Value::Obj(members);
                }
                loop {
                    self.skip();
                    let key = self.string();
                    self.skip();
                    self.i += 1;
                    members.push((key, self.value()));
                    self.skip();
                    let c = self.b[self.i];
                    self.i += 1;
                    if c != b',' {
                        return Value::Obj(members);
                    }
                }
            }
            b'[' => {
                self.i += 1;
                let mut items = Vec::new();
                self.skip();
                if self.b[self.i] == b']' {
                    self.i += 1;
                    return Value::Arr(items);
                }
                loop {
                    items.push(self.value());
                    self.skip();
                    let c = self.b[self.i];
                    self.i += 1;
                    if c != b',' {
                        return Value::Arr(items);
                    }
                }
            }
            b'"' => Value::Str(self.string()),
            b't' => {
                self.i += 4;
                Value::Bool(true)
            }
            b'f' => {
                self.i += 5;
                Value::Bool(false)
            }
            b'n' => {
                self.i += 4;
                Value::Null
            }
            _ => {
                let s = self.i;
                if self.b[self.i] == b'-' {
                    self.i += 1;
                }
                while self.i < self.b.len() && self.b[self.i].is_ascii_digit() {
                    self.i += 1;
                }
                Value::Num(std::str::from_utf8(&self.b[s..self.i]).unwrap().parse().unwrap())
            }
        }
    }
}

fn member<'a>(v: &'a Value, name: &str) -> &'a Value {
    match v {
        Value::Obj(m) => &m.iter().find(|(k, _)| k == name).unwrap().1,
        _ => &Value::Null,
    }
}

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let root = Parser { b: data.as_bytes(), i: 0 }.value();
    let mut scores: HashMap<&str, i64> = HashMap::new();
    let mut tags: HashMap<&str, u64> = HashMap::new();
    let (mut records, mut active, mut name_bytes) = (0, 0, 0);
    if let Value::Arr(items) = &root {
        for r in items {
            records += 1;
            if let (Value::Str(u), Value::Num(s)) = (member(r, "user"), member(r, "score")) {
                *scores.entry(u).or_insert(0) += s;
            }
            if let Value::Arr(ts) = member(r, "tags") {
                for t in ts {
                    if let Value::Str(t) = t {
                        *tags.entry(t).or_insert(0) += 1;
                    }
                }
            }
            if let Value::Bool(true) = member(r, "active") {
                active += 1;
            }
            if let Value::Str(n) = member(r, "name") {
                name_bytes += n.len();
            }
        }
    }
    println!("records: {records}");
    println!("active: {active}");
    println!("name bytes: {name_bytes}");
    let mut ranked: Vec<_> = scores.into_iter().collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    for (k, v) in ranked.iter().take(5) {
        println!("{k} {v}");
    }
    let mut ts: Vec<_> = tags.into_iter().collect();
    ts.sort();
    for (k, v) in ts {
        println!("{k} {v}");
    }
}

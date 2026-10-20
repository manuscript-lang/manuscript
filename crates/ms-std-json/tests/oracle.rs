//! Replays `tests/oracle/json.tsv`, a recorded corpus of parse, stringify and scalar cases.
use ms_std_core::Fail;
use ms_std_json::*;

fn bytes(tok: &str) -> Vec<u8> {
    let h = tok.strip_prefix('x').expect("hex token");
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect()
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|b| format!("{b:02x}")).collect()
}

fn limit(tok: &str) -> Option<i64> {
    (tok != "-").then(|| tok.parse().unwrap())
}

fn dump(doc: &Doc, id: NodeId, out: &mut String) {
    match &doc.nodes[id as usize] {
        Node::Null => out.push('N'),
        Node::Bool(b) => out.push(if *b { 'T' } else { 'F' }),
        Node::Number(t) => *out += &format!("#{t};"),
        Node::Str(s) => *out += &format!("s{};", hex(s.as_bytes())),
        Node::Array(items) => {
            out.push('[');
            items.iter().for_each(|&i| dump(doc, i, out));
            out.push(']');
        }
        Node::Object(entries) => {
            out.push('{');
            for (k, v) in entries {
                *out += &format!("{}:", hex(k.as_bytes()));
                dump(doc, *v, out);
            }
            out.push('}');
        }
    }
}

/// Parses the dump form back into a tree (number text is taken verbatim).
fn load(doc: &mut Doc, s: &[u8], pos: &mut usize) -> NodeId {
    let c = s[*pos];
    let until =
        |s: &[u8], from: usize, end: u8| from + s[from..].iter().position(|&b| b == end).unwrap();
    let node = match c {
        b'N' => {
            *pos += 1;
            Node::Null
        }
        b'T' | b'F' => {
            *pos += 1;
            Node::Bool(c == b'T')
        }
        b'#' => {
            let e = until(s, *pos, b';');
            let t = String::from_utf8(s[*pos + 1..e].to_vec()).unwrap();
            *pos = e + 1;
            Node::Number(t)
        }
        b's' => {
            let e = until(s, *pos, b';');
            let t = bytes(&format!(
                "x{}",
                std::str::from_utf8(&s[*pos + 1..e]).unwrap()
            ));
            *pos = e + 1;
            Node::Str(String::from_utf8(t).unwrap())
        }
        b'[' => {
            *pos += 1;
            let mut items = vec![];
            while s[*pos] != b']' {
                items.push(load(doc, s, pos));
            }
            *pos += 1;
            Node::Array(items)
        }
        b'{' => {
            *pos += 1;
            let mut entries = vec![];
            while s[*pos] != b'}' {
                let e = until(s, *pos, b':');
                let k = bytes(&format!("x{}", std::str::from_utf8(&s[*pos..e]).unwrap()));
                *pos = e + 1;
                let v = load(doc, s, pos);
                entries.push((String::from_utf8(k).unwrap(), v));
            }
            *pos += 1;
            Node::Object(entries)
        }
        _ => panic!("bad dump"),
    };
    doc.add(node)
}

fn result<T>(r: Result<T, Fail>, ok: impl FnOnce(T) -> String) -> String {
    match r {
        Ok(v) => format!("ok {}", ok(v)),
        Err(e) => format!("err {e:?}"),
    }
}

fn parse_dump(text: &str, limits: Limits) -> String {
    result(parse(text, limits), |(doc, root)| {
        let mut s = String::new();
        dump(&doc, root, &mut s);
        s
    })
}

#[test]
fn matches_recorded_cases() {
    let data = include_str!("oracle/json.tsv");
    let (mut n, mut skipped) = (0, 0);
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let got = match f[0] {
            "parse" => {
                let Ok(text) = String::from_utf8(bytes(f[1])) else {
                    skipped += 1;
                    continue;
                };
                let limits = Limits {
                    max_bytes: limit(f[2]),
                    max_depth: limit(f[3]),
                    max_values: limit(f[4]),
                };
                parse_dump(&text, limits)
            }
            "deep" => {
                let k: usize = f[1].parse().unwrap();
                let text = format!("{}{}", "[".repeat(k), "]".repeat(k));
                let r = parse(&text, Limits::default());
                result(r, |_| "deep".into())
            }
            "stringify" => {
                let mut doc = Doc::default();
                let root = load(&mut doc, f[1].as_bytes(), &mut 0);
                result(doc.stringify(root, limit(f[2]), limit(f[3])), |s| {
                    format!("x{}", hex(s.as_bytes()))
                })
            }
            "float" => {
                let v = f64::from_bits(u64::from_str_radix(f[1], 16).unwrap());
                match float_text(v) {
                    Some(t) => format!("#{t};"),
                    None => "N".into(),
                }
            }
            "scalar" => {
                let t = String::from_utf8(bytes(f[1])).unwrap();
                let i = parse_int(&t);
                let fl = parse_float(&t);
                format!(
                    "{} {} {} {:x}",
                    u8::from(i.is_some()),
                    i.unwrap_or(0),
                    u8::from(fl.is_some()),
                    fl.unwrap_or(0.0).to_bits()
                )
            }
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line:.200}");
        n += 1;
    }
    assert!(n > 5000, "{n} cases, {skipped} skipped");
}

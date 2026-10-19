//! Replays `tests/oracle/html.tsv`, recorded from the Go runtime by `go run ./scripts/rs-oracle`.
use ms_std_core::Fail;
use ms_std_html::*;

fn bytes(tok: &str) -> Vec<u8> {
    let h = tok.strip_prefix('x').expect("hex token");
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect()
}

fn text(tok: &str) -> String {
    String::from_utf8(bytes(tok)).unwrap()
}

fn hex(s: &str) -> String {
    s.bytes().map(|b| format!("{b:02x}")).collect()
}

fn limit(tok: &str) -> Option<i64> {
    (tok != "-").then(|| tok.parse().unwrap())
}

/// Renders a tree in the recorder's format, iteratively.
fn dump(tree: &Tree) -> String {
    enum Step {
        Visit(Id),
        Close,
    }
    let mut out = String::new();
    let mut stack = vec![Step::Visit(tree.root)];
    while let Some(step) = stack.pop() {
        let id = match step {
            Step::Close => {
                out.push(']');
                continue;
            }
            Step::Visit(id) => id,
        };
        let n = &tree.nodes[id];
        match n.ty {
            NodeType::Document => out.push_str("D["),
            NodeType::Element => {
                out.push_str(&format!("E{},{}{{", hex(&n.data), hex(&n.namespace)));
                for a in &n.attr {
                    out.push_str(&format!(
                        "{},{},{};",
                        hex(&a.key),
                        hex(&a.namespace),
                        hex(&a.val)
                    ));
                }
                out.push_str("}[");
            }
            NodeType::Text => {
                out.push_str(&format!("T{};", hex(&n.data)));
                continue;
            }
            NodeType::Comment => {
                out.push_str(&format!("C{};", hex(&n.data)));
                continue;
            }
            NodeType::Doctype => {
                let (mut public, mut system) = ("", "");
                for a in &n.attr {
                    if a.key == "public" {
                        public = &a.val;
                    } else if a.key == "system" {
                        system = &a.val;
                    }
                }
                out.push_str(&format!(
                    "Y{},{},{};",
                    hex(&n.data),
                    hex(public),
                    hex(system)
                ));
                continue;
            }
            NodeType::ScopeMarker => unreachable!(),
        }
        stack.push(Step::Close);
        let mut kids = vec![];
        let mut c = n.first;
        while let Some(k) = c {
            kids.push(k);
            c = tree.nodes[k].next;
        }
        stack.extend(kids.into_iter().rev().map(Step::Visit));
    }
    out
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data {
        crc ^= u32::from(b);
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn result<T>(r: Result<T, Fail>, ok: impl FnOnce(T) -> String) -> String {
    match r {
        Ok(v) => format!("ok {}", ok(v)),
        Err(e) => format!("err {e:?}"),
    }
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/html.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let got = match f[0] {
            "parse" => {
                let limits = Limits {
                    max_bytes: limit(f[2]),
                    max_depth: limit(f[3]),
                    max_nodes: limit(f[4]),
                };
                result(parse(&text(f[1]), limits), |t| dump(&t))
            }
            "parsehash" => result(parse(&text(f[1]), Limits::default()), |t| {
                let d = dump(&t);
                format!("{} {:x}", d.len(), crc32(d.as_bytes()))
            }),
            "unescape" => format!("x{}", hex(&unescape(&text(f[1])))),
            "escape" => format!("x{}", hex(&escape(&text(f[1])))),
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line:.300}");
        n += 1;
    }
    assert!(n > 5000, "{n} cases");
}

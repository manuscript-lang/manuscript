//! Replays `tests/oracle/url.tsv`, a recorded corpus.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_rt::ffi::Fail;
use ms_std_url::*;

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
    let mut out = String::from("x");
    for b in s.bytes() {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

fn limit(tok: &str) -> Option<i64> {
    (tok != "-").then(|| tok.parse().unwrap())
}

fn url_from(f: &[&str]) -> Components {
    Components {
        scheme: text(f[0]),
        host: text(f[1]),
        port: limit(f[2]),
        path: text(f[3]),
        query: text(f[4]),
        fragment: text(f[5]),
    }
}

fn url_text(u: &Components) -> String {
    format!(
        "{} {} {} {} {} {}",
        hex(&u.scheme),
        hex(&u.host),
        u.port.map_or("-".to_string(), |p| p.to_string()),
        hex(&u.path),
        hex(&u.query),
        hex(&u.fragment)
    )
}

fn query_text(items: &[(String, String)]) -> String {
    format!(
        "[{}]",
        items
            .iter()
            .map(|(k, v)| format!("{}:{}", hex(k), hex(v)))
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn query_from(tok: &str) -> Vec<(String, String)> {
    let inner = &tok[1..tok.len() - 1];
    if inner.is_empty() {
        return Vec::new();
    }
    inner
        .split(',')
        .map(|p| {
            let (k, v) = p.split_once(':').unwrap();
            (text(k), text(v))
        })
        .collect()
}

fn result<T>(r: Result<T, Fail>, ok: impl FnOnce(T) -> String) -> String {
    match r {
        Ok(v) => format!("ok {}", ok(v)),
        Err(e) => format!("err {e:?}"),
    }
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/url.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let got = match f[0] {
            "parse" => result(parse(&text(f[1])), |u| url_text(&u)),
            "format" => {
                let parts: Vec<&str> = f[1].split(' ').collect();
                result(format(&url_from(&parts)), |s| hex(&s))
            }
            "resolve" => {
                let parts: Vec<&str> = f[1].split(' ').collect();
                result(resolve(&url_from(&parts), &text(f[2])), |u| url_text(&u))
            }
            "encode" => hex(&encode_component(&text(f[1]))),
            "decode" => result(decode_component(&text(f[1])), |s| hex(&s)),
            "query" => result(parse_query(&text(f[1]), limit(f[2])), |q| query_text(&q)),
            "fquery" => hex(&format_query(&query_from(f[1]))),
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

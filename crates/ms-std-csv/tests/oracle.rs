//! Replays `tests/oracle/csv.tsv`, recorded from the Go runtime by `go run ./scripts/rs-oracle`.
use ms_std_core::Fail;
use ms_std_csv::*;

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

fn rows_text(rows: &[Vec<String>]) -> String {
    rows.iter()
        .map(|r| {
            format!(
                "[{}]",
                r.iter().map(|c| hex(c)).collect::<Vec<_>>().join(",")
            )
        })
        .collect()
}

/// Parses the `[x..,x..][..]` form back into rows.
fn rows_from(tok: &str) -> Vec<Vec<String>> {
    tok.split_inclusive(']')
        .filter(|r| !r.is_empty())
        .map(|r| {
            let inner = &r[1..r.len() - 1];
            if inner.is_empty() {
                Vec::new()
            } else {
                inner.split(',').map(text).collect()
            }
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
    let data = include_str!("oracle/csv.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let got = match f[0] {
            "parse" => {
                let o = options(&text(f[2]), &text(f[3]));
                result(
                    o.and_then(|o| parse(&text(f[1]), o, limit(f[4]), limit(f[5]))),
                    |rows| rows_text(&rows),
                )
            }
            "stringify" => {
                let o = options(&text(f[2]), &text(f[3]));
                let rows = rows_from(f[1]);
                result(o.and_then(|o| stringify(&rows, o, limit(f[4]))), |s| {
                    hex(&s)
                })
            }
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

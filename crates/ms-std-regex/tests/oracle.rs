//! Replays `tests/oracle/regex.tsv`, recorded from the Go runtime by `go run ./scripts/rs-oracle`.
use ms_std_core::Fail;
use ms_std_regex::{Regex, compile};
use std::collections::BTreeMap;

fn text(tok: &str) -> String {
    let h = tok.strip_prefix('x').expect("hex token");
    let bytes: Vec<u8> = (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect();
    String::from_utf8(bytes).unwrap()
}

fn hex(s: &str) -> String {
    let mut out = String::from("x");
    for x in s.bytes() {
        out.push_str(&format!("{x:02x}"));
    }
    out
}

fn limit(tok: &str) -> Option<i64> {
    (tok != "-").then(|| tok.parse().unwrap())
}

fn err(e: Fail) -> String {
    format!("err {e:?}")
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/regex.tsv");
    let mut compiled: BTreeMap<String, Option<Regex>> = BTreeMap::new();
    let mut bad: BTreeMap<String, String> = BTreeMap::new();
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let pattern = text(f[1]);
        let got = if f[0] == "compile" {
            let r = compile(&pattern);
            let got = match &r {
                Ok(_) => "ok".to_string(),
                Err(e) => err(*e),
            };
            compiled.insert(pattern.clone(), r.ok());
            got
        } else {
            let Some(re) = compiled.get(&pattern).and_then(|r| r.as_ref()) else {
                bad.entry(pattern.clone())
                    .or_insert_with(|| "compiled differently".into());
                continue;
            };
            let t = text(f[2]);
            match f[0] {
                "matches" => (if re.is_match(&t) { "1" } else { "0" }).to_string(),
                "findall" => match re.find_all(&t, limit(f[3])) {
                    Ok(v) => {
                        let mut s = String::from("ok");
                        for m in v {
                            s.push(' ');
                            s.push_str(&hex(&m));
                        }
                        s
                    }
                    Err(e) => err(e),
                },
                "replace" => match re.replace_all(&t, &text(f[3]), limit(f[4])) {
                    Ok(v) => format!("ok {}", hex(&v)),
                    Err(e) => err(e),
                },
                other => panic!("unknown case {other}"),
            }
        };
        if got != want {
            bad.entry(pattern)
                .or_insert_with(|| format!("{line}\n    got {got}"));
        }
        n += 1;
    }
    for (p, why) in &bad {
        eprintln!("MISMATCH {p:?}: {why}");
    }
    assert!(bad.is_empty(), "{} patterns differ", bad.len());
    assert!(n > 1000, "only {n} cases");
}

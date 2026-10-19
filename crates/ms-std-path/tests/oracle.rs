//! Replays `tests/oracle/path.tsv`, recorded from the Go runtime by `go run ./scripts/rs-oracle`.
use ms_std_path::*;

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

fn parts_from(tok: &str) -> Parts {
    let f: Vec<String> = tok.split(' ').map(text).collect();
    Parts {
        root: f[0].clone(),
        directory: f[1].clone(),
        base: f[2].clone(),
        extension: f[3].clone(),
        name: f[4].clone(),
    }
}

fn parts_text(p: &Parts) -> String {
    [&p.root, &p.directory, &p.base, &p.extension, &p.name]
        .map(|s| hex(s))
        .join(" ")
}

fn list_from(tok: &str) -> Vec<String> {
    let inner = &tok[1..tok.len() - 1];
    if inner.is_empty() {
        Vec::new()
    } else {
        inner.split(',').map(text).collect()
    }
}

fn result(r: Result<String, InvalidInput>) -> String {
    match r {
        Ok(s) => format!("ok {}", hex(&s)),
        Err(_) => "err InvalidInput".into(),
    }
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/path.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let r = Rules {
            windows: f[1] == "1",
        };
        let got = match f[0] {
            "basename" => hex(&r.basename(&text(f[2]))),
            "basename_without" => hex(&r.basename_without(&text(f[2]), &text(f[3]))),
            "dirname" => hex(&r.dirname(&text(f[2]))),
            "extension" => hex(&r.extension(&text(f[2]))),
            "is_absolute" => u8::from(r.is_absolute(&text(f[2]))).to_string(),
            "normalize" => hex(&r.normalize(&text(f[2]))),
            "namespaced" => hex(&r.to_namespaced_path(&text(f[2]))),
            "parse" => parts_text(&r.parse(&text(f[2]))),
            "format" => hex(&r.format(&parts_from(f[2]))),
            "join" => {
                let items = list_from(f[2]);
                hex(&r.join(&items.iter().map(String::as_str).collect::<Vec<_>>()))
            }
            "resolve" => {
                let items = if f[3] == "[]" {
                    Vec::new()
                } else {
                    list_from(f[3])
                };
                result(r.resolve(
                    &text(f[2]),
                    &items.iter().map(String::as_str).collect::<Vec<_>>(),
                ))
            }
            "relative" => result(r.relative(&text(f[2]), &text(f[3]))),
            "glob" => match r.matches_glob(&text(f[2]), &text(f[3])) {
                Ok(b) => format!("ok {}", u8::from(b)),
                Err(_) => "err InvalidInput".into(),
            },
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

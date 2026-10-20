//! Replays `tests/oracle/semver.tsv`, a recorded corpus.
use ms_std_semver::*;

fn text(tok: &str) -> String {
    let h = tok.strip_prefix('x').expect("hex token");
    let b: Vec<u8> = (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect();
    String::from_utf8(b).unwrap()
}

fn hex(s: &str) -> String {
    s.bytes()
        .fold(String::from("x"), |a, b| a + &format!("{b:02x}"))
}

fn ids_text(ids: &[String]) -> String {
    format!(
        "[{}]",
        ids.iter().map(|s| hex(s)).collect::<Vec<_>>().join(",")
    )
}

fn ids(tok: &str) -> Vec<String> {
    let inner = &tok[1..tok.len() - 1];
    if inner.is_empty() {
        return Vec::new();
    }
    inner.split(',').map(text).collect()
}

fn version_text(v: &Version) -> String {
    format!(
        "{} {} {} {} {}",
        v.major,
        v.minor,
        v.patch,
        ids_text(&v.prerelease),
        ids_text(&v.build)
    )
}

fn version(f: &[&str]) -> Version {
    Version {
        major: f[0].parse().unwrap(),
        minor: f[1].parse().unwrap(),
        patch: f[2].parse().unwrap(),
        prerelease: ids(f[3]),
        build: ids(f[4]),
    }
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/semver.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let arrow = f.iter().position(|t| *t == "=>").expect("arrow");
        let want = f[arrow + 1..].join(" ");
        let a = &f[1..arrow];
        let got = match f[0] {
            "parse" => match parse(&text(a[0])) {
                Ok(v) => format!("ok {}", version_text(&v)),
                Err(e) => format!("err {e:?}"),
            },
            "format" => hex(&format(&version(&a[0].split(' ').collect::<Vec<_>>()))),
            "compare" => {
                let l = version(&a[0].split(' ').collect::<Vec<_>>());
                let r = version(&a[1].split(' ').collect::<Vec<_>>());
                compare(&l, &r).to_string()
            }
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

//! Replays the `unescape` and `escape` lines of `tests/oracle/html.tsv`, a recorded corpus.
//! Its `parse` lines belong to the Manuscript parser and replay in `stdlib/data/html.ms` tests.
// Links the msrt_* runtime symbols the html crate releases through.
use ms_rt as _;
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

#[test]
fn matches_oracle() {
    let data = include_str!("oracle/html.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let got = match f[0] {
            "unescape" => format!("x{}", hex(&unescape(&text(f[1])))),
            "escape" => format!("x{}", hex(&escape(&text(f[1])))),
            _ => continue,
        };
        assert_eq!(got, want, "{line:.300}");
        n += 1;
    }
    assert!(n > 100, "{n} cases");
}

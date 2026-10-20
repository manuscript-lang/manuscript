//! Replays `tests/oracle/encoding.tsv`, a recorded corpus.
use ms_std_core::Fail;
use ms_std_encoding::*;

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

fn hex(b: &[u8]) -> String {
    format!("x{}", hex_encode(b))
}

fn limit(tok: &str) -> Option<i64> {
    (tok != "-").then(|| tok.parse().unwrap())
}

fn result<T>(r: Result<T, Fail>, ok: impl FnOnce(T) -> String) -> String {
    match r {
        Ok(v) => format!("ok {}", ok(v)),
        Err(e) => format!("err {e:?}"),
    }
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/encoding.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let (args, want) = (&f[1..f.len() - 2], f[f.len() - 1]);
        let got = match f[0] {
            "b64dec" => result(
                base64_decode(&text(args[0]), args[1] == "1", limit(args[2])),
                |b| hex(&b),
            ),
            "hexdec" => result(hex_decode(&text(args[0]), limit(args[1])), |b| hex(&b)),
            "b64enc" => hex(base64_encode(&bytes(args[0]), args[1] == "1").as_bytes()),
            "hexenc" => hex(hex_encode(&bytes(args[0])).as_bytes()),
            "u16enc" => hex(&utf16_encode(&text(args[0]), args[1] == "1")),
            "u16dec" => result(
                utf16_decode(&bytes(args[0]), args[1] == "1", limit(args[2])),
                |s| hex(s.as_bytes()),
            ),
            "l1enc" => result(latin1_encode(&text(args[0])), |b| hex(&b)),
            "l1dec" => hex(latin1_decode(&bytes(args[0])).as_bytes()),
            "asciienc" => result(ascii_encode(&text(args[0])), |b| hex(&b)),
            "asciidec" => result(ascii_decode(&bytes(args[0])), |s| hex(s.as_bytes())),
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

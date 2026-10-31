//! Replays `tests/oracle/compress.tsv`, a recorded corpus.
//! Streams produced by Go must decode identically (including every error), and compress must
//! accept and reject the same arguments; the encoded bytes themselves are implementation specific.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_rt::ffi::Fail;
use ms_std_compress::*;

fn bytes(tok: &str) -> Vec<u8> {
    let h = tok.strip_prefix('x').expect("hex token");
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect()
}

fn hex(b: &[u8]) -> String {
    let mut out = String::from("x");
    for x in b {
        out.push_str(&format!("{x:02x}"));
    }
    out
}

fn limit(tok: &str) -> Option<i64> {
    (tok != "-").then(|| tok.parse().unwrap())
}

fn result(r: Result<Vec<u8>, Fail>) -> String {
    match r {
        Ok(b) => format!("ok {}", hex(&b)),
        Err(e) => format!("err {e:?}"),
    }
}

#[test]
fn matches_oracle() {
    let data = include_str!("oracle/compress.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let want = f[f.len() - 1];
        let got = match f[0] {
            "compress" => match compress(b"sample", f[1], f[2].parse().unwrap(), limit(f[3])) {
                Ok(_) => "ok".to_string(),
                Err(e) => format!("err {e:?}"),
            },
            "decompress" => result(decompress_bytes(&bytes(f[2]), f[1], limit(f[3]))),
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 500, "only {n} cases");
}

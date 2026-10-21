//! Replays `tests/oracle/crypto.tsv`, a recorded corpus.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_core::Fail;
use ms_std_crypto::*;

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

/// Results over 1 KiB are recorded as their length and SHA-256.
fn compact(b: &[u8]) -> String {
    if b.len() > 1024 {
        let d = digest(Alg::Sha256, b);
        return format!("x#{}:{}", b.len(), &hex(&d)[1..]);
    }
    hex(b)
}

fn crypto(r: Result<Vec<u8>, CryptoFail>) -> String {
    match r {
        Ok(b) => format!("ok {}", compact(&b)),
        Err(e) => format!("err {e:?}"),
    }
}

fn fail(r: Result<Vec<u8>, Fail>) -> String {
    match r {
        Ok(b) => format!("ok {}", compact(&b)),
        Err(e) => format!("err {e:?}"),
    }
}

fn flag(b: bool) -> String {
    (if b { "1" } else { "0" }).to_string()
}

#[test]
fn matches_go() {
    let data = include_str!("oracle/crypto.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let arrow = f.iter().position(|t| *t == "=>").expect("arrow");
        let want = f[arrow + 1..].join("\t");
        let a = &f[1..arrow];
        let alg = || Alg::from_index(a[0].parse().unwrap()).unwrap();
        let got = match f[0] {
            "digest" => hex(&digest(alg(), &bytes(a[1]))),
            "hmac" => format!("ok {}", hex(&hmac(alg(), &bytes(a[1]), &bytes(a[2])))),
            "pbkdf2" => fail(derive_key(
                alg(),
                &bytes(a[1]),
                &bytes(a[2]),
                a[3].parse().unwrap(),
                a[4].parse().unwrap(),
            )),
            "hkdf" => fail(hkdf(
                alg(),
                &bytes(a[1]),
                &bytes(a[2]),
                &bytes(a[3]),
                a[4].parse().unwrap(),
            )),
            "hasher" => {
                let mut h = if a[1] == "-" {
                    Hasher::new(alg())
                } else {
                    Hasher::new_hmac(alg(), &bytes(a[1]))
                };
                h.update(&bytes(a[2]));
                h.update(&bytes(a[3]));
                let d1 = h.finish();
                let d2 = h.finish();
                format!("{}\t{}", hex(&d1), hex(&d2))
            }
            "cteq" => flag(constant_time_equal(&bytes(a[0]), &bytes(a[1]))),
            "seal" => crypto(seal(&bytes(a[0]), &bytes(a[1]), &bytes(a[2]), &bytes(a[3]))),
            "open" => crypto(open(&bytes(a[0]), &bytes(a[1]), &bytes(a[2]), &bytes(a[3]))),
            "ctr" => crypto(aes_ctr(&bytes(a[0]), &bytes(a[1]), &bytes(a[2]))),
            "cbcenc" => crypto(aes_cbc_encrypt(&bytes(a[0]), &bytes(a[1]), &bytes(a[2]))),
            "cbcdec" => crypto(aes_cbc_decrypt(&bytes(a[0]), &bytes(a[1]), &bytes(a[2]))),
            "pubkey" => crypto(ed25519_public_key(&bytes(a[0]))),
            "sign" => crypto(ed25519_sign(&bytes(a[0]), &bytes(a[1]))),
            "verify" => flag(ed25519_verify(&bytes(a[0]), &bytes(a[1]), &bytes(a[2]))),
            other => panic!("unknown case {other}"),
        };
        // Go reports CryptoError names; map ours (same spelling).
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 2000, "only {n} cases");
}

//! Replays `tests/oracle/crypto_asym.tsv`, recorded from the Go runtime by `go run ./scripts/rs-oracle`.
//! Randomized operations (ECDSA, PSS, OAEP) are checked for success/failure parity only; their
//! outputs are verified by the recorded Go signatures and ciphertexts instead.
use ms_std_crypto::asym::*;
use ms_std_crypto::{Alg, CryptoFail, digest};
use std::collections::HashMap;

fn bytes(tok: &str) -> Vec<u8> {
    let h = tok.strip_prefix('x').expect("hex token");
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect()
}

fn hex(b: &[u8]) -> String {
    b.iter()
        .fold(String::from("x"), |s, x| s + &format!("{x:02x}"))
}

/// Results over 1 KiB are recorded as their length and SHA-256.
fn compact(b: &[u8]) -> String {
    if b.len() > 1024 {
        return format!("x#{}:{}", b.len(), &hex(&digest(Alg::Sha256, b))[1..]);
    }
    hex(b)
}

fn res(r: Result<Vec<u8>, CryptoFail>) -> String {
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
    let data = include_str!("oracle/crypto_asym.tsv");
    let mut keys: HashMap<String, (Vec<u8>, Vec<u8>)> = HashMap::new();
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let (kind, rest) = (f[0], &f[1..]);
        match kind {
            "key" => {
                keys.insert(rest[0].into(), (bytes(rest[1]), bytes(rest[2])));
                continue;
            }
            "pt" => {
                keys.insert(rest[0].into(), (Vec::new(), bytes(rest[1])));
                continue;
            }
            _ => {}
        }
        let arrow = f.iter().position(|t| *t == "=>");
        let want = arrow.map(|i| f[i + 1..].join("\t")).unwrap_or_default();
        let a = &rest[..arrow.map_or(rest.len(), |i| i - 1)];
        let alg = || Alg::from_index(a[1].parse().unwrap()).unwrap();
        let k = || keys.get(a[0]).unwrap_or_else(|| panic!("key {line}"));
        let got = match kind {
            "pub" => res(public_key_der(&k().0)),
            "ecsign" => flag(ecdsa_sign(&k().0, alg(), &bytes(a[2])).is_ok()),
            "ecverify" => flag(ecdsa_verify(&k().1, alg(), &bytes(a[2]), &bytes(a[3]))),
            "ecdh" => res(ecdh_shared_secret(&k().0, &keys[a[1]].1)),
            "rsasign" => res(rsa_sign(&k().0, alg(), &bytes(a[2]))),
            "pssverify" => flag(rsa_verify_pss(&k().1, alg(), &bytes(a[2]), &bytes(a[3]))),
            "rsaverify" => flag(rsa_verify(&k().1, alg(), &bytes(a[2]), &bytes(a[3]))),
            "rsaenc" => flag(rsa_encrypt(&k().1, alg(), &vec![7; a[2].parse().unwrap()]).is_ok()),
            "rsadec" => res(rsa_decrypt(&k().0, alg(), &bytes(a[2]))),
            "rsagen" => res(rsa_generate(a[0].parse().unwrap())),
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

#[test]
fn generated_keys_roundtrip() {
    for i in 0..3 {
        let curve = Curve::from_index(i).unwrap();
        let (a, b) = (
            ecdsa_generate(curve).unwrap(),
            ecdsa_generate(curve).unwrap(),
        );
        let (pa, pb) = (public_key_der(&a).unwrap(), public_key_der(&b).unwrap());
        let sig = ecdsa_sign(&a, Alg::Sha256, b"m").unwrap();
        assert!(ecdsa_verify(&pa, Alg::Sha256, b"m", &sig));
        assert!(!ecdsa_verify(&pb, Alg::Sha256, b"m", &sig));
        assert_eq!(
            ecdh_shared_secret(&a, &pb).unwrap(),
            ecdh_shared_secret(&b, &pa).unwrap()
        );
    }
    let k = rsa_generate(2048).unwrap();
    let p = public_key_der(&k).unwrap();
    for alg in [Alg::Sha256, Alg::Sha512] {
        let s = rsa_sign_pss(&k, alg, b"m").unwrap();
        assert!(rsa_verify_pss(&p, alg, b"m", &s));
        let c = rsa_encrypt(&p, alg, b"secret").unwrap();
        assert_eq!(rsa_decrypt(&k, alg, &c).unwrap(), b"secret");
    }
}

/// Go reads the key from the scalar alone but still checks the algorithm identifiers: a key whose
/// algorithm or curve OID is altered is rejected, as it is by `x509.ParsePKCS8PrivateKey`.
#[test]
fn rejects_altered_algorithm_identifiers() {
    for i in 0..3 {
        let key = ecdsa_generate(Curve::from_index(i).unwrap()).unwrap();
        assert!(public_key_der(&key).is_ok());
        // id-ecPublicKey is 1.2.840.10045.2.1 (06 07 2a 86 48 ce 3d 02 01); the next OID is the curve.
        let alg = key
            .windows(9)
            .position(|w| w == [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01])
            .unwrap();
        for at in [alg + 4, alg + 10, alg + 11] {
            let mut bad = key.clone();
            bad[at] ^= 1;
            assert!(public_key_der(&bad).is_err(), "curve {i} byte {at}");
        }
    }
}

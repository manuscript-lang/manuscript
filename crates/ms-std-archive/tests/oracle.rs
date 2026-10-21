//! Replays `tests/oracle/archive.tsv`, a recorded corpus.
//! Tar output must match byte for byte; zip output only has to match in status because the
//! deflate payload differs from Go's encoder (the Rust-packed zip must round-trip instead).
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_archive::{Entry, Limits, pack, unpack};
use ms_std_core::Fail;
use std::collections::BTreeMap;

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

#[test]
fn matches_go() {
    let data = include_str!("oracle/archive.tsv");
    let rows: Vec<Vec<&str>> = data
        .lines()
        .filter(|l| !l.starts_with('#'))
        .map(|l| l.split('\t').collect())
        .collect();
    // Entry sets whose paths are not valid UTF-8 cannot be expressed as a Manuscript String.
    let mut sets: BTreeMap<usize, Vec<Option<Entry>>> = BTreeMap::new();
    for r in rows.iter().filter(|r| r[0] == "set") {
        let e = String::from_utf8(bytes(r[2])).ok().map(|path| Entry {
            path,
            data: bytes(r[3]),
            directory: r[4] == "1",
        });
        sets.entry(r[1].parse().unwrap()).or_default().push(e);
    }
    for r in rows.iter().filter(|r| r[0] == "setend") {
        sets.entry(r[1].parse().unwrap()).or_default();
    }
    let mut inputs: BTreeMap<usize, Vec<u8>> = BTreeMap::new();
    let (mut n, mut bad) = (0, Vec::new());
    for r in &rows {
        let want = r.last().unwrap().to_string();
        let got = match r[0] {
            "input" => {
                inputs.insert(r[1].parse().unwrap(), bytes(r[2]));
                continue;
            }
            "pack" => {
                let Some(set) = sets[&r[2].parse::<usize>().unwrap()]
                    .iter()
                    .map(|e| {
                        e.as_ref().map(|e| Entry {
                            path: e.path.clone(),
                            data: e.data.clone(),
                            directory: e.directory,
                        })
                    })
                    .collect::<Option<Vec<_>>>()
                else {
                    continue; // not representable as strings
                };
                match pack(&set, r[1], limit(r[3])) {
                    Ok(b) if r[1] == "tar" => format!("ok {}", hex(&b)),
                    Ok(b) => {
                        let back = unpack(&b, r[1], None).expect("own zip unpacks");
                        assert_eq!(back.len(), set.len(), "{}", r[..4].join(" "));
                        "ok".to_string()
                    }
                    Err(e) => format!("err {e:?}"),
                }
            }
            "unpack" => {
                let input = &inputs[&r[2].parse::<usize>().unwrap()];
                let limits = (r[3] != "-").then(|| {
                    let f: Vec<&str> = r[3].split(',').collect();
                    Limits {
                        max_entries: limit(f[0]),
                        max_entry_bytes: limit(f[1]),
                        max_total_bytes: limit(f[2]),
                    }
                });
                match unpack(input, r[1], limits) {
                    Ok(v) => {
                        let mut s = String::from("ok");
                        for e in v {
                            s.push_str(&format!(
                                " {}:{}:{}",
                                hex(e.path.as_bytes()),
                                u8::from(e.directory),
                                hex(&e.data)
                            ));
                        }
                        s
                    }
                    Err(e) => format!("err {e:?}"),
                }
            }
            _ => continue,
        };
        if got != want {
            bad.push(format!(
                "{}\n  want {}\n  got  {}",
                r[..r.len() - 1]
                    .join(" ")
                    .chars()
                    .take(160)
                    .collect::<String>(),
                want.chars().take(160).collect::<String>(),
                got.chars().take(160).collect::<String>()
            ));
        }
        n += 1;
    }
    for b in bad.iter().take(25) {
        eprintln!("MISMATCH {b}");
    }
    assert!(bad.is_empty(), "{} of {n} cases differ", bad.len());
    assert!(n > 1000, "only {n} cases");
    let _ = Fail::InvalidData;
}

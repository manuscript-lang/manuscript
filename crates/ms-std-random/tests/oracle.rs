//! Replays `tests/oracle/random.tsv`, a recorded corpus.
//! The entropy is a deterministic LCG stream (see `testEntropy` in `scripts/rs-oracle/random.go`).
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_random::*;

struct Entropy {
    state: u64,
    kind: String,
    served: usize,
    limit: usize,
}

impl Entropy {
    fn new(kind: &str) -> Entropy {
        let mut e = Entropy {
            state: 1,
            kind: kind.into(),
            served: 0,
            limit: 0,
        };
        if kind == "short" {
            e.state = 0;
        } else if let Some(s) = kind.strip_prefix('s') {
            e.state = s.parse().unwrap();
        } else if let Some(n) = kind.strip_prefix('f') {
            e.limit = n.parse().unwrap();
        }
        e
    }

    fn fetch(&mut self, count: usize) -> Result<Vec<u8>, RandomFail> {
        let mut n = count;
        if self.kind == "short" {
            n = count.saturating_sub(1);
        } else if self.kind.starts_with('f') && self.served + count > self.limit {
            return Err(RandomFail::Failed("boom".into()));
        }
        self.served += count;
        Ok((0..n)
            .map(|_| {
                self.state = self
                    .state
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                (self.state >> 56) as u8
            })
            .collect())
    }
}

fn hex(s: &str) -> String {
    s.bytes()
        .fold(String::from("x"), |a, b| a + &format!("{b:02x}"))
}

fn err(e: RandomFail) -> String {
    match e {
        RandomFail::InvalidInput => "err InvalidInput".into(),
        RandomFail::LimitExceeded => "err LimitExceeded".into(),
        RandomFail::Failed(m) => format!("err Failed {}", hex(&m)),
    }
}

type Fetch<'a> = &'a mut dyn FnMut(usize) -> Result<Vec<u8>, RandomFail>;

/// Runs `d` to completion over `fetch`, as the generated loop does; `swap` sees shuffle swaps.
fn drive(mut d: Draw, fetch: Fetch, mut swap: impl FnMut((i64, i64))) -> Result<Draw, RandomFail> {
    loop {
        let want = d.want();
        if want == 0 {
            break;
        }
        let data = fetch(want as usize)?;
        if d.push(&data) {
            swap(d.swap());
        }
    }
    match d.status() {
        ms_rt_abi::STATUS_OK => Ok(d),
        ms_rt_abi::STATUS_INVALID_INPUT => Err(RandomFail::InvalidInput),
        _ => Err(RandomFail::Failed(
            "entropy source returned incorrect length".into(),
        )),
    }
}

fn secure_int(fetch: Fetch, min: i64, max: Option<i64>) -> Result<i64, RandomFail> {
    drive(Draw::new(Kind::Int, min, max), fetch, drop).map(|d| d.int())
}

fn uuid_v4(fetch: Fetch) -> Result<String, RandomFail> {
    drive(Draw::new(Kind::Uuid, 0, None), fetch, drop).map(|d| d.text().to_string())
}

fn float(fetch: Fetch) -> Result<f64, RandomFail> {
    drive(Draw::new(Kind::Float, 0, None), fetch, drop).map(|d| d.float())
}

fn shuffle(fetch: Fetch, values: &mut [i64]) -> Result<(), RandomFail> {
    let d = Draw::new(Kind::Shuffle, values.len() as i64, None);
    drive(d, fetch, |(i, j)| values.swap(i as usize, j as usize)).map(drop)
}

fn choice_index(fetch: Fetch, len: usize) -> Result<Option<usize>, RandomFail> {
    drive(Draw::new(Kind::Choice, len as i64, None), fetch, drop)
        .map(|d| usize::try_from(d.int()).ok())
}

/// Runs `step` up to `n` times, joining `ok ..` results and stopping at the first error.
fn repeat(n: usize, mut step: impl FnMut() -> Result<String, RandomFail>) -> String {
    let mut vals = Vec::new();
    for _ in 0..n {
        match step() {
            Ok(v) => vals.push(format!("ok {v}")),
            Err(e) => {
                vals.push(err(e));
                break;
            }
        }
    }
    vals.join(",")
}

#[test]
fn matches_oracle() {
    let data = include_str!("oracle/random.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let arrow = f.iter().position(|t| *t == "=>").expect("arrow");
        let want = f[arrow + 1..].join("\t");
        let a = &f[1..arrow];
        let mut e = Entropy::new(a[0]);
        let mut fetch = |c| e.fetch(c);
        let got = match f[0] {
            "int" => {
                let max = (a[2] != "-").then(|| a[2].parse().unwrap());
                let min = a[1].parse().unwrap();
                repeat(6, || {
                    secure_int(&mut fetch, min, max).map(|v| v.to_string())
                })
            }
            "uuid" => repeat(4, || uuid_v4(&mut fetch)),
            "float" => repeat(4, || {
                float(&mut fetch).map(|v| format!("{:x}", v.to_bits()))
            }),
            "shuffle" => {
                let mut v: Vec<i64> = (0..a[1].parse().unwrap()).collect();
                match shuffle(&mut fetch, &mut v) {
                    Ok(()) => format!(
                        "ok {}",
                        v.iter().map(i64::to_string).collect::<Vec<_>>().join(",")
                    ),
                    Err(e) => err(e),
                }
            }
            "choice" => match choice_index(&mut fetch, a[1].parse().unwrap()) {
                Ok(Some(i)) => format!("ok {i}"),
                Ok(None) => "ok none".into(),
                Err(e) => err(e),
            },
            other => panic!("unknown case {other}"),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

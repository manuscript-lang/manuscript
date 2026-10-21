//! Replays `tests/oracle/log.tsv`, a recorded corpus of log records.
//! The wall clock is fixed at 0 here.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_log::*;

fn text(tok: &str) -> String {
    let h = tok.strip_prefix('x').expect("hex token");
    let b: Vec<u8> = (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect();
    String::from_utf8(b).unwrap()
}

fn hex(b: &[u8]) -> String {
    b.iter()
        .fold(String::from("x"), |a, x| a + &format!("{x:02x}"))
}

fn err(e: LogFail) -> String {
    format!("err {e:?}")
}

fn run(a: &[&str]) -> Result<Option<Vec<u8>>, LogFail> {
    let level = (a[0] != "-").then(|| a[0].parse::<usize>().unwrap());
    let ts = (a[1] != "-").then(|| a[1] == "1");
    let max = (a[2] != "-").then(|| a[2].parse::<i64>().unwrap());
    let mut logger = Logger::new(level, ts, max)?;
    let n: usize = a[3].parse().unwrap();
    for b in &a[4..4 + n] {
        logger = logger.child(&text(b))?;
    }
    let rest = &a[4 + n..];
    let (level, msg) = (rest[0].parse::<i64>().unwrap(), text(rest[1]));
    if rest[2] == "-" {
        logger.log(level, &msg, 0)
    } else {
        logger.log_json(level, &msg, &text(rest[2]), 0)
    }
}

#[test]
fn matches_recorded_cases() {
    let data = include_str!("oracle/log.tsv");
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        let arrow = f.iter().position(|t| *t == "=>").expect("arrow");
        let want = f[arrow + 1..].join("\t");
        let got = match run(&f[1..arrow]) {
            Ok(Some(b)) => format!("ok {}", hex(&b)),
            Ok(None) => "ok none".into(),
            Err(e) => err(e),
        };
        assert_eq!(got, want, "{line}");
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

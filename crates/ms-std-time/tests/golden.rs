//! Compares the timestamp logic with Go's `time` package (`tests/golden/gen.go` writes the vectors).
//! `MS_TIME_GOLDEN=<file>` runs a larger set instead of the committed one.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_std_time::core_time::{Ts, calendar, from_calendar, to_string};

#[test]
fn matches_oracle() {
    let text = match std::env::var("MS_TIME_GOLDEN") {
        Ok(path) => std::fs::read_to_string(path).unwrap(),
        Err(_) => include_str!("golden/golden.txt").to_string(),
    };
    let mut failures = Vec::new();
    let mut total = 0;
    for line in text.lines() {
        let (lhs, want) = line.split_once(" => ").unwrap();
        let f: Vec<&str> = lhs.split(' ').collect();
        let got = match f[0] {
            "cal" => {
                let ts = Ts {
                    seconds: f[1].parse().unwrap(),
                    nanos: f[2].parse().unwrap(),
                };
                let zone = f.get(3).copied().unwrap_or("");
                let c = calendar(ts, zone).unwrap();
                let v = c.civil;
                format!(
                    "{} {} {} {} {} {} {} {} {} {} {}",
                    v.year,
                    v.month,
                    v.day,
                    v.hour,
                    v.minute,
                    v.second,
                    v.nanosecond,
                    v.weekday,
                    v.day_of_year,
                    c.offset_seconds,
                    c.zone.replace(' ', "_")
                )
            }
            "str" => to_string(Ts {
                seconds: f[1].parse().unwrap(),
                nanos: f[2].parse().unwrap(),
            }),
            "from" => {
                let n: Vec<i64> = f[1..8].iter().map(|v| v.parse().unwrap()).collect();
                let zone = f.get(8).copied().unwrap_or("");
                match from_calendar(n[0], n[1], n[2], n[3], n[4], n[5], n[6], zone) {
                    Ok(t) => t.seconds.to_string(),
                    Err(_) => "ERR".to_string(),
                }
            }
            other => panic!("unknown record {other}"),
        };
        total += 1;
        if got != want {
            failures.push(format!("{line}\n   got {got}"));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {total} differ; first: {:#?}",
        failures.len(),
        &failures[..failures.len().min(8)]
    );
}

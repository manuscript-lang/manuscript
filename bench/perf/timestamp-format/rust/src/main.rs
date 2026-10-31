use ms_std_time::{
    civil::civil_of,
    core_time::{self, Ts},
};
use std::{fmt::Write, hint::black_box, time::Instant};

fn rust_format(ts: Ts) -> String {
    let c = civil_of(ts.seconds, ts.nanos);
    let mut out = String::with_capacity(30);
    write!(
        out,
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        c.year, c.month, c.day, c.hour, c.minute, c.second
    )
    .unwrap();
    if ts.nanos != 0 {
        write!(out, ".{:09}", ts.nanos).unwrap();
        while out.ends_with('0') {
            out.pop();
        }
    }
    out.push('Z');
    out
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = &args[0];
    let count: usize = args[1].parse().unwrap();
    let moments = [
        Ts {
            seconds: args[2].parse().unwrap(),
            nanos: args[3].parse().unwrap(),
        },
        Ts {
            seconds: args[4].parse().unwrap(),
            nanos: args[5].parse().unwrap(),
        },
    ];
    let expected = [&args[6], &args[7]];
    let mut checksum = 0;
    let mut last = String::new();
    let started = Instant::now();
    for i in 0..count {
        let ts = black_box(moments[i % 2]);
        last = if mode == "rust" {
            rust_format(ts)
        } else {
            core_time::to_string(ts)
        };
        assert_eq!(last, *expected[i % 2]);
        checksum += black_box(last.len());
    }
    let ns = started.elapsed().as_nanos();
    assert_eq!(
        checksum,
        count / 2 * (expected[0].len() + expected[1].len())
    );
    println!("{count}\t{ns}\t{checksum}\t{last}");
}

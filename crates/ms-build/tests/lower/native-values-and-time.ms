# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "closure.new"
# expect-mir: "msstd_time_parse_timestamp"

import stdout from "@std/io.ms"
import {sqrt, max} from "@std/math.ms"
import {Duration, parse_timestamp} from "@std/time.ms"

fn via(f: fn(Float) Float, x: Float) Float: f(x)

export fn main() Int:
    let to_text: fn() String = 7.to_string
    let d: Duration = 2.seconds
    let _t = parse_timestamp("2020-01-02T03:04:05Z")
    let _r = stdout().write(
        "{to_text()} {via(sqrt, 4.0)} {max(left: 1, right: 2)} {d.to_milliseconds()}\n"
    )
    return 0

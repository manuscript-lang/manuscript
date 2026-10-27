# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "closure.new"
# expect-mir: "msstd_time_parse_timestamp"

from "@std/io.ms" import stdout
from "@std/math.ms" import sqrt, max
from "@std/time.ms" import Duration, parse_timestamp

def via(f: Callable[[Float], Float], x: Float) -> Float: f(x)

export def main() -> Int:
    let to_text: Callable[[], String] = 7.to_string
    let d: Duration = 2.seconds
    let t = parse_timestamp("2020-01-02T03:04:05Z")
    let r = stdout().write(f"{to_text()} {via(sqrt, 4.0)} {max(left: 1, right: 2)} {d.to_milliseconds()}\n")
    return 0

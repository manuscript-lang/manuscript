# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msstd_time_instant_shift"
# expect-mir: "msstd_time_instant_difference"
# expect-mir: "msstd_time_instant_unshift"

from "@std/time.ms" import clock

export def main() -> Int:
    let a = clock().now()
    let b = a + 5.seconds
    let d = b - a
    let c = b - 1.seconds
    return d.to_nanoseconds() + c.difference(a).to_nanoseconds()

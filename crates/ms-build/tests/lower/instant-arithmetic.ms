# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msstd_time_instant_shift"
# expect-mir: "msstd_time_instant_difference"
# expect-mir: "msstd_time_instant_unshift"

import monotonic from "@std/os/time.ms"

export fn main() Int:
    let a = monotonic()
    let b = a + 5.seconds
    let d = b - a
    let c = b - 1.seconds
    return d.to_nanoseconds() + c.difference(a).to_nanoseconds()

// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "msrt_string_concat"
// expect-mir: "iadd.chk"

import stdout from "@std/io/io.ms"

fn main() Unit:
    var total = 0
    for x in [1, 2, 3]:
        total += x

    let _r = stdout().write("total {total}\n")

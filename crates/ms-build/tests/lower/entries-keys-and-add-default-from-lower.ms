# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_map_contains"

import stdout from "@std/io/io.ms"

export fn main() Int:
    var m: Map[String, Int] = Map()
    m.add_default_from("a", fn(key: String): 5)

    let items = [4, 5]
    let _r = stdout().write("{items.keys()} {items.entries().length()}\n")
    return 0

// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "map_probe"

import stdout from "@std/io/io.ms"

fn main() Unit:
    var m: Map[String, Int] = Map()
    m.add_default_from("a", fn(key: String): 5)

    items := [4, 5]
    _r := stdout().write("{items.keys()} {items.entries().length()}\n")

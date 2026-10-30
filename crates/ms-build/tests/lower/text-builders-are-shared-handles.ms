# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "shared.new"
# expect-mir: "shared.addr"
# expect-mir: "builder is sealed"

import StringBuilder from "@std/string.ms"

export fn main() Int:
    var b = StringBuilder()
    b.append("a")
    b.append("b")
    return b.build().length()

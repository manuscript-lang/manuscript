# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_strbuilder_append"
# expect-mir: "msrt_strbuilder_freeze"

import StringBuilder from "@std/string.ms"

export fn main() Int:
    var b = StringBuilder()
    b.append("a")
    b.append("b")
    return b.build().length()

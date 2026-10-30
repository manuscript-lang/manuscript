# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "cell.new"
# expect-mir: "cell.addr"
# expect-mir: "builder is sealed"

import ListBuilder from "@std/collections.ms"

export fn main() Int:
    var b = ListBuilder[Int]()
    b.append(1)
    b.append(2)
    return b.build().length()

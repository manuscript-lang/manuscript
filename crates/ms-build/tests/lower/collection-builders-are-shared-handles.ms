# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "shared.new"
# expect-mir: "shared.addr"
# expect-mir: "builder is sealed"

from "@std/collections.ms" import ListBuilder

export def main() -> Int:
    var b = ListBuilder[Int]()
    b.append(1)
    b.append(2)
    return b.build().length()

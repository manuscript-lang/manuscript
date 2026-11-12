// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir-count: 2 "msrt_map_slot_lent"


export fn main() Int:
    var counts: Map[String, Int] = Map()
    parts := "long-dynamic-map-key-padding-1 b".split(" ")
    counts.update(parts[0].clone(), 0, fn n: n + 1)
    counts.update(parts[0].clone(), 0, fn n: n + 1)
    return counts[parts[0]] - 2

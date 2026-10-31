# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_map_add"
# expect-mir: "msrt_list_to_set"
# expect-mir: "put "

export fn main() Int:
    var m = {"a": 1}
    m.add("b", 2)

    let s = Set[Int]([1, 2])
    var total = 0
    for e in m:
        total += e.value
    return total + s.length() + m.get_or("z", 0)

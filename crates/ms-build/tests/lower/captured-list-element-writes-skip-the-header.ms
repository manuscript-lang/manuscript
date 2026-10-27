# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "list.addr.u"
# expect-mir: "store "
# expect-mir-count: 1 "load list<int>"
def fill(f: Callable[[Int], Unit]) -> Unit:
    f(0)
    f(1)

export def main() -> Int:
    var out: List[Int] = [0, 0]
    fill(lambda r: out[r] = r + 5)
    return out[1]

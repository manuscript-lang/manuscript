# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "slot "
# expect-mir: "take "

type Counter:
    total: Int

impl Counter:
    var def bump(by: Int) -> Int:
        self.total += by
        return self.total

def add(var xs: List[Int], v: Int) -> Unit:
    xs.append(v)

export def main() -> Int:
    var c = Counter(total: 1)
    let a = c.bump(4)
    var l = [1]
    add(var l, a)
    return l.length()

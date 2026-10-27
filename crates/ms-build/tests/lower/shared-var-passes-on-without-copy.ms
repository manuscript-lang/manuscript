# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# A closure that passes a captured `var` on hands over the shared slot: no copy in, no write back.
# expect-mir-order: "fn @<anonymous>" "closure.cap 0" "call @resize (%2, %1)"
def resize(var out: List[Int], n: Int) -> Unit:
    out.append(n)

def each(f: Callable[[Int], Unit]) -> Unit:
    f(1)
    f(2)

def run() -> Int:
    var out: List[Int] = []
    each(lambda i: resize(var out, i))
    return out.length()

export def main() -> Int:
    return run()

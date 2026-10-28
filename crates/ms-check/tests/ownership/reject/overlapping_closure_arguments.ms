def apply(f: Callable[[], Unit], g: Callable[[], Unit]) -> Unit:
    f()
    g()

def main() -> Int:
    var n = 0
    apply(lambda: n += 1, lambda: n += 2)  # error: the closure at 7:11 of `apply` is changed in place but overlaps the closure at 7:27
    return n

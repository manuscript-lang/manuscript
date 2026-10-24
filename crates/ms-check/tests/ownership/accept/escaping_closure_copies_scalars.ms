def adder(n: Int) -> Callable[[Int], Int]:
    return lambda (x: Int) -> Int: x + n

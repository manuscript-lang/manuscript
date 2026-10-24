def make() -> Callable[[], Int]:
    let xs = [1, 2]
    let f = lambda () -> Int: xs.length()  # error: takes `xs` with it
    let n = xs.length()
    return f

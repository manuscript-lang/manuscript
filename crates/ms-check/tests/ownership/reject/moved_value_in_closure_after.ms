def f() -> Int:
    let xs = [1]
    let g = lambda () -> List[Int]: xs  # error: would move `xs` out
    return g().length()

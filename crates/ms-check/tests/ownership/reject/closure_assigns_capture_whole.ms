def f() -> Int:
    var xs = ["a"]
    let reset = lambda: xs = ["c"]
    let n = xs.length()  # error: while closure `reset` (made at 3:17) changes it
    reset()
    return n

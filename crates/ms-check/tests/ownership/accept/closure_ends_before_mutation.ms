def f() -> Int:
    var xs = [1]
    let show = lambda () -> Int: xs.length()
    let n = show()
    xs.append(2)
    return n + xs.length()

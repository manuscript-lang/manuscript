fn f(c: Bool) Int:
    a := [1]
    var n = 0

    if c:
        b := a
        n = b.length()

    return n + a.length()

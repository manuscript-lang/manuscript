fn f() Int:
    var a = [1, 2]
    var c = a
    n := a.length()  // error: cannot use `a`
    c.append(n)
    return c.length()

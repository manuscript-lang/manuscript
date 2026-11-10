fn make() fn() Int:
    var n = 1
    n = 2
    f := fn: n
    return f

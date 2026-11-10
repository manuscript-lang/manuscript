fn f() Int:
    var xs = ["a"]
    reset := fn: xs = ["c"]
    n := xs.length()  // error: while closure `reset` (made at 3:14) changes it
    reset()
    return n

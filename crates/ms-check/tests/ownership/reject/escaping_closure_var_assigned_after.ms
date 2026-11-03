fn make() fn() Int:
    var n = 1
    let f = fn: n  // error: captures the `var` `n`
    n = 2
    return f

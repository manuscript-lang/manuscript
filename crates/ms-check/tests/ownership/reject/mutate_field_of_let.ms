type P:
    x: Int

fn f() Int:
    p := P(x: 1)
    p.x = 2  // error: is an immutable binding
    return p.x

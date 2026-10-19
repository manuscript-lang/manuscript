type P:
    x: Int

fn f() Int:
    let p = P(x: 1)
    p.x = 2  # error: declared with let
    return p.x

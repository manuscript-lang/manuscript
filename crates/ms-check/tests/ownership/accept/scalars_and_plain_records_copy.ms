type P:
    x: Int
    y: Int

fn f() Int:
    p := P(x: 1, y: 2)
    q := p
    return p.x + q.y

type P:
    x: Int
    y: Int

def f() -> Int:
    let p = P(x: 1, y: 2)
    let q = p
    return p.x + q.y

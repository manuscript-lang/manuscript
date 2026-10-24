type P:
    x: Int
    items: List[Int]

def f() -> Int:
    var p = P(x: 1, items: [])
    p.x = p.x + 1
    p.items.append(p.x)
    return p.items.length()

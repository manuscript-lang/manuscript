type P:
    xs: List[Int]
    ys: List[Int]

def f() -> Int:
    var p = P(xs: [], ys: [])
    var a = p.xs
    var b = p.ys
    a.append(1)
    b.append(2)
    return a.length() + b.length()

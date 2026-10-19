fn step(xs: List[Int]) List[Int]:
    var out = xs
    out.append(1)
    return out

fn f() Int:
    var xs = [0]
    var i = 0
    while i < 3:
        xs = step(xs)
        i += 1
    return xs.length()

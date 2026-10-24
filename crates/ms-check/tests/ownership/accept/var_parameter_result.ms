def pushed(var xs: List[Int], v: Int) -> Int:
    xs.append(v)
    return xs.length()

def f() -> Int:
    var xs = [0]
    return pushed(var xs, 1) + pushed(var xs, 2)

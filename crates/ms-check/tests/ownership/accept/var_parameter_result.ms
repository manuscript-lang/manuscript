fn pushed(var xs: List[Int], v: Int) Int:
    xs.append(v)
    return xs.length()

fn f() Int:
    var xs = [0]
    return pushed(xs, 1) + pushed(xs, 2)

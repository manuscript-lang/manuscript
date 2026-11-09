fn make() List[Int]:
    return [1]

fn go() Int:
    var xs = make()
    xs[0] = 2
    make().append(3)
    return xs[0]

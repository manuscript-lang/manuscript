fn make() List[Int]:
    return [1, 2]

fn total(xs: List[Int]) Int:
    return xs.length()

fn f() Int:
    return total(make()) + make().length()

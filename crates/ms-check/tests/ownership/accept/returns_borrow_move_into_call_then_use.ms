fn keep(xs: List[Int]) List[Int]:
    return xs

fn f() Int:
    a := [1, 2]
    b := keep(a)
    return a.length() + b.length()

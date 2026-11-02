fn keep(xs: List[Int]) List[Int]:
    return xs

fn f() Int:
    let a = [1, 2]
    let b = keep(a)
    return a.length() + b.length()

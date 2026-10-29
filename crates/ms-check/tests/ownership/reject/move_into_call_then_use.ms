fn keep(xs: List[Int]) List[Int]:
    return xs

fn f() Int:
    let a = [1, 2]
    let b = keep(a)  # error: moved here but used again
    return a.length() + b.length()

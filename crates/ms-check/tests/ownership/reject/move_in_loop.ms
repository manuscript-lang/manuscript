fn keep(xs: List[Int]) List[Int]:
    return xs

fn f() Int:
    let a = [1]
    var i = 0

    while i < 3:
        let b = keep(a)  # error: moved here but used again
        i += 1

    return 0

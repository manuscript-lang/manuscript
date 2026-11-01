type Big:
    name: String
    items: List[Int]

fn keep(xs: List[Int]) List[Int]:
    return xs

fn looped(b: Big) Int:
    var i = 0

    while i < 3:
        let a = keep(b.items)
        i += a.length()

    return i

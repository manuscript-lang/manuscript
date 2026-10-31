type Big:
    name: String
    items: List[Int]

fn keep(xs: List[Int]) List[Int]:
    return xs

fn captured(b: Big) Int:
    let f = fn: b.items.length()
    let a = keep(b.items)  # error: while `f` borrows it
    return a.length() + f()

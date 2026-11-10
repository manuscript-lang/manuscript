type Big:
    name: String
    items: List[Int]

fn keep(xs: List[Int]) List[Int]:
    return xs

fn captured(b: Big) Int:
    f := fn: b.items.length()
    a := keep(b.items)
    return a.length() + f()

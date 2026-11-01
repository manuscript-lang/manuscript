type Big:
    name: String
    items: List[Int]

fn keep(xs: List[Int]) List[Int]:
    return xs

fn twice(b: Big) Int:
    let a = keep(b.items)
    return a.length() + b.items.length()

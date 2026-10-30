type Big:
    name: String
    items: List[Int]

fn keep(xs: List[Int]) List[Int]:
    return xs

fn twice(b: Big) Int:
    let a = keep(b.items)  # error: moved here but used again
    return a.length() + b.items.length()

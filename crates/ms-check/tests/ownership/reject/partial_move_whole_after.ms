type Big:
    name: String
    items: List[Int]

fn keep(xs: List[Int]) List[Int]:
    return xs

fn show(b: Big) Int:
    return b.name.length()

fn whole(b: Big) Int:
    let a = keep(b.items)  # error: moved here but used again
    return a.length() + show(b)

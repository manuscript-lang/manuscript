fn total(xs: List[Int]) Int:
    return xs.length()

fn f(xs: List[Int]) Int:
    return total(xs) + total(xs)

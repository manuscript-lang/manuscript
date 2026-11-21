fn first(xs: List[Int]) Int?:
    return xs.get(0)

fn second(xs: List[Int]) Int?:
    a := first(xs)?
    return a

fn lost(xs: List[Int]) Int:
    return 1

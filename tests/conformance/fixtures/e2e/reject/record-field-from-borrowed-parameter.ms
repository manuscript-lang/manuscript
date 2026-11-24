// conform: tags=ownership,tier-core
// conform: phase=check
// A borrowed parameter handed to a record constructor is copied unless the source says `.clone()` or the parameter is `move`.
type Box:
    items List[Int]

fn wrap(xs List[Int]) Box:
    return Box(xs)

fn main() Void:
    print(wrap([1, 2]).items.length())

fn find(xs: List[Int], v: Int) Int:
    var i = 0

    while i < xs.length():
        if xs.get(i) == v:
            return i

        i += 1

    return -1

fn total(xs: List[Int]) Int:
    var s = 0
    for x in xs:
        s += x
    return s

export fn main() Int:
    let xs = [1, 2, 3]
    return find(xs, 2) + total(xs)

fn total(xs: List[Int]) Int:
    let sum = xs.sum()
    return sum

fn kept(xs: List[Int]) Int:
    let sum = xs.sum()
    print("{sum}")
    return sum

export fn main() Int:
    return total([1, 2]) + kept([3])

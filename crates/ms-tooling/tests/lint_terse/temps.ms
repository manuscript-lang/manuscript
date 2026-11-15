fn total(xs: List[Int]) Int:
    sum := xs.sum()
    return sum

fn kept(xs: List[Int]) Int:
    sum := xs.sum()
    print(f"{sum}")
    return sum

export fn main() Int:
    return total([1, 2]) + kept([3])

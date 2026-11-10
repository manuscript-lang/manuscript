fn first(xs: List[Int], name: String) Int:
    if xs.is_empty() or not name.is_empty(): return 0

    empty := xs.is_empty()
    if empty: return 1

    return xs[0] + xs[1 + 1]

export fn main() Int:
    return first([1, 2, 3], "n")

fn first(xs: List[Int], name: String) Int:
    if xs.length() == 0 or name.length() > 0:
        return 0

    empty := xs.length() == 0
    if empty:
        return 1

    return xs.get(0) + xs.get(1 + 1)

export fn main() Int:
    return first([1, 2, 3], "n")

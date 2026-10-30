fn n(x: Int??) Int:
    return 1

export fn main() Int:
    let keep = some(5)
    return n(some(none)) + n(some(some(1))) + keep.get(0)

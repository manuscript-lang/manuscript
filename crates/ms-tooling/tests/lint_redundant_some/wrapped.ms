fn f(x: Int? = some(3)) Int?:
    return some(x.get(0) + 1)

export fn main() Int:
    let o: Int? = some(4)
    return f(some(2)).get(0) + o.get(0)

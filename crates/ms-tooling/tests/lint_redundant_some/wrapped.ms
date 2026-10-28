fn f(x: Optional[Int] = some(3)) Optional[Int]:
    return some(x.get(0) + 1)

export fn main() Int:
    let o: Optional[Int] = some(4)
    return f(some(2)).get(0) + o.get(0)

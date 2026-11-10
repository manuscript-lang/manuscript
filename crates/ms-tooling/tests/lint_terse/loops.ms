fn work(xs: List[Int], m: Map[String, Int], flag: Bool, n: Int) Int:
    var label = 0
    if flag:
        label = 5
    var i = 0
    var total = 0
    while i < n:
        total += xs[i]
        i += 1
    for j in 0..xs.length():
        total += xs[j]
    var out = List[Int]()
    for x in xs:
        out.append(x)
    var copy: List[Int] = []
    for x in xs:
        copy.append(x * 2)
    var sum = 0
    for x in xs:
        sum += x
    return total + label + m.get("a").get(0) + out.length() + copy.length() + sum

export fn main() Int:
    return work([1, 2], Map[String, Int](), true, 2)

export fn main() Int:
    var m = Map[String, List[Int]]()
    m.add("a", [1])

    if var e = m["a"]?:
        m.add("b", [])
        e.append(2)

    return 0

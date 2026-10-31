type Counter:
    count: Int
    tags: List[String]

fn bump(var m: Map[String, Counter]) Int:
    if var c = m["a"]?:
        c.count = c.count + 1
        c.tags.append("x")

    return m.length()

type Counter:
    count: Int
    tags: List[String]

def bump(var m: Map[String, Counter]) -> Int:
    if var c = m.get("a"):
        c.count = c.count + 1
        c.tags.append("x")

    return m.length()

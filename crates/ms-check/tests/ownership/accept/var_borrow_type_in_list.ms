type Counter:
    count: Int
    tags: List[String]

fn bump(var cs: List[Counter]) Int:
    var c = cs[0]
    c.count = c.count + 1
    c.tags.append("x")
    return cs[0].count

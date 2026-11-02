type Counter:
    count: Int
    tags: List[String]

fn f() Int:
    var xs = [1, 2, 3]
    var y = xs[0]
    y += 10
    var cs = [Counter(count: 1, tags: [])]
    var n = cs[0].count
    n += 1
    var c = cs[0]
    c.count += n
    return xs[0] + y + cs[0].count

def f() -> Int:
    var rows = [[1], [2]]
    let head = rows[0]
    let n = head.length()
    rows.append([3])
    return n + rows.length()

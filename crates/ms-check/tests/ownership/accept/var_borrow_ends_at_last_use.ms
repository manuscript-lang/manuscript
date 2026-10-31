fn f() Int:
    var rows = [[1], [2]]
    var head = rows[0]
    head.append(5)
    rows.append([3])
    return rows.length()

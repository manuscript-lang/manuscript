fn f() Int:
    var rows = [[1], [2]]
    head := rows[0]
    n := head.length()
    rows.append([3])
    return n + rows.length()

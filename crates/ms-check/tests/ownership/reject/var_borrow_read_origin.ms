fn f() Int:
    var rows = [[1], [2]]
    var head = rows[0]
    let n = rows.length()  # error: cannot use `rows`
    head.append(n)
    return head.length()

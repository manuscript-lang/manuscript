fn f() Int:
    var rows = [[1], [2]]
    var head = rows[0]
    rows.append([3])  # error: cannot change `rows`
    head.append(1)
    return head.length()

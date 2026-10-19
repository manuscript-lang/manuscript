fn f() Int:
    var rows = [[1], [2]]
    var head = rows[0]  # error: cannot take part of another value
    head.append(5)
    return head.length()

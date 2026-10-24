def f() -> Int:
    var rows = [[1], [2]]
    var head = rows[0]
    head = [9]  # error: cannot reassign
    return head.length()

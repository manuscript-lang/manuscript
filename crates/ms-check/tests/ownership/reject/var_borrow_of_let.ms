def f() -> Int:
    let rows = [[1], [2]]
    var head = rows[0]  # error: declared with let
    head.append(1)
    return head.length()

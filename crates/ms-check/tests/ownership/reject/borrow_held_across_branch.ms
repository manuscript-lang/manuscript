def f(c: Bool) -> Int:
    var rows = [[1]]
    let head = rows[0]
    if c:
        rows.append([2])  # error: while `head` borrows it
    return head.length()

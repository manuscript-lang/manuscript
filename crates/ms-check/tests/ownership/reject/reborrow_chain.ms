def f() -> Int:
    var rows = [[1]]
    let a = rows[0]
    let b = a
    rows.append([2])  # error: while `b` borrows it
    return b.length()

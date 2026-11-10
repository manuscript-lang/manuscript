fn f() Int:
    var rows = [[1]]
    a := rows[0]
    b := a
    rows.append([2])  // error: while `b` borrows it
    return b.length()

fn f() Int:
    var rows = [[1], [2]]
    head := rows[0]
    rows.append([3])  // error: while `head` borrows it
    return head.length()

fn f() Int:
    var rows = [[1]]
    let head = rows[0]
    var i = 0
    while i < 2:
        rows.append([2])  # error: while `head` borrows it
        i += 1
    return head.length()

fn f() List[Int]:
    var rows = [[1], [2]]
    var head = rows[0]
    head.append(1)
    return head  # error: cannot move

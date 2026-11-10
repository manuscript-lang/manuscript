fn f() Int:
    rows := [[1], [2]]
    var head = rows[0]  // error: is an immutable binding
    head.append(1)
    return head.length()

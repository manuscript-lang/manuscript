fn f() Int:
    var rows = [[1], [2]]
    var a = rows[0]
    var b = rows[1]
    a.append(1)
    b.append(2)
    return a.length() + b.length()

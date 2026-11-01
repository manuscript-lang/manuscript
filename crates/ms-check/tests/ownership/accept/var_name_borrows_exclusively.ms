fn f() Int:
    var a = [1, 2]
    var c = a
    c.append(4)
    var p = [[1]]
    var q = p
    q.append([2])
    return a.length() + p.length()

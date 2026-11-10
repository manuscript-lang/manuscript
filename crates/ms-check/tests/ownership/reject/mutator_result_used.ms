fn f() Int:
    var xs = [1]
    ys := xs.append(2)
    return ys.length()  // error: member length on Unit

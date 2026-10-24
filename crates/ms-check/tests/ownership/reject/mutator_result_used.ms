def f() -> Int:
    var xs = [1]
    let ys = xs.append(2)
    return ys.length()  # error: member length on Unit

fn f() Int:
    var xs = [1]
    let ys = xs.append(2)  # error: result cannot be used
    return ys.length()

fn f() Int:
    var xs = [1]
    let show = fn() Int: xs.length()
    let n = show()
    xs.append(2)
    return n + xs.length()

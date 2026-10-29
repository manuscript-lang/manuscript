fn f() Int:
    var xs = [1]
    let add = fn(v: Int) Unit:
        xs.append(v)
    let n = xs.length()  # error: while closure `add`
    add(2)
    return n

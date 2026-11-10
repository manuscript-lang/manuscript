fn f() Int:
    var xs = [1]
    add := fn(v: Int) Unit:
        xs.append(v)
    n := xs.length()  // error: while closure `add`
    add(2)
    return n

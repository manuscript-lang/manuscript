fn f() Int:
    var xs = [1]
    add := fn(v: Int) Void:
        xs.append(v)
    n := xs.length()  // error: while closure `add`
    add(2)
    return n

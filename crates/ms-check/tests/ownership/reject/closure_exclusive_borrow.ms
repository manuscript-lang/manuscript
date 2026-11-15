fn f() Int:
    var xs = [1]
    add := fn(v: Int) Void:
        xs.append(v)
    xs.append(2)  // error: while `add` borrows it
    add(3)
    return xs.length()

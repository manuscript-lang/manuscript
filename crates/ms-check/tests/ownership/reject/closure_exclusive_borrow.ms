fn f() Int:
    var xs = [1]
    let add = fn(v: Int) Unit:
        xs.append(v)
    xs.append(2)  # error: while `add` borrows it
    add(3)
    return xs.length()

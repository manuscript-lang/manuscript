fn f() Int:
    var a = [1, 2]
    let b = a
    a.append(3)  # error: cannot change `a` while `b` borrows it
    return b.length()

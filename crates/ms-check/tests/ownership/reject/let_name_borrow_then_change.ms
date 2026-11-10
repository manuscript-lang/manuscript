fn f() Int:
    var a = [1, 2]
    b := a
    a.append(3)  // error: cannot change `a` while `b` borrows it
    return b.length()

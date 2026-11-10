fn f() Int:
    var xs = [1]
    show := fn() Int: xs.length()
    xs.append(2)  // error: while `show` borrows it
    return show()

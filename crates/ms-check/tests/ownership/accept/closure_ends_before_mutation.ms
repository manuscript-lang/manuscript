fn f() Int:
    var xs = [1]
    show := fn() Int: xs.length()
    n := show()
    xs.append(2)
    return n + xs.length()

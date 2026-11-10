fn f() Int:
    xs := [1]
    g := fn() List[Int]: xs  // error: would move `xs` out
    return g().length()

fn f() Int:
    let xs = [1]
    let g = fn() List[Int]: xs  # error: would move `xs` out
    return g().length()

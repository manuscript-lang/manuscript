type Box:
    items: List[Int]

fn f() Int:
    a := [1]
    b := Box(items: a)  // error: moved here but used again
    return a.length() + b.items.length()

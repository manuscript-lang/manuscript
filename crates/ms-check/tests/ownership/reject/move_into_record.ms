type Box:
    items: List[Int]

fn f() Int:
    let a = [1]
    let b = Box(items: a)  # error: moved here but used again
    return a.length() + b.items.length()

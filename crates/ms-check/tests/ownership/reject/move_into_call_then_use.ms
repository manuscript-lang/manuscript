def keep(xs: List[Int]) -> List[Int]:
    return xs

def f() -> Int:
    let a = [1, 2]
    let b = keep(a)  # error: moved here but used again
    return a.length() + b.length()

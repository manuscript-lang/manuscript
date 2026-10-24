def f(xs: List[Int]) -> Int:
    let ys = xs  # error: moved here but used again
    return xs.length() + ys.length()

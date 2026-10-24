def f(c: Bool) -> Int:
    let a = [1]
    var n = 0

    if c:
        let b = a  # error: moved here but used again
        n = b.length()

    return n + a.length()

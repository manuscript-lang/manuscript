export def main() -> Int:
    var xs = [1, 2, 3]
    let add = xs.append
    let n = xs.length()  # error: cannot use `xs`
    add(4)
    return n

export def main() -> Int:
    var xs = [1, 2, 3]
    let add = xs.append
    add(4)
    add(5)

    let n = xs.length()
    return n

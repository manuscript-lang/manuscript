export fn main() Int:
    var xs = [1, 2, 3]
    add := xs.append
    add(4)
    add(5)

    n := xs.length()
    return n

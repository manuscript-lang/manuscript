export fn main() Int:
    var xs = [1, 2, 3]
    add := xs.append
    n := xs.length()  // error: cannot use `xs`
    add(4)
    return n

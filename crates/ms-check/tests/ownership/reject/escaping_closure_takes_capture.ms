fn make() fn() Int:
    let xs = [1, 2]
    let f = fn() Int: xs.length()  # error: takes `xs` with it
    let n = xs.length()
    return f

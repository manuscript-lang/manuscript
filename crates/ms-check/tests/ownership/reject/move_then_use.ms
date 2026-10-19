fn f() Int:
    let a = [1, 2, 3]
    let b = a  # error: moved here but used again
    return a.length() + b.length()

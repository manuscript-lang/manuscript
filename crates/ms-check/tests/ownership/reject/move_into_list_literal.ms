fn f() Int:
    let a = [1]
    let rows = [a, a]  # error: moved here but used again
    return rows.length()

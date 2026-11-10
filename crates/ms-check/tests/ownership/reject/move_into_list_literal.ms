fn f() Int:
    a := [1]
    rows := [a, a]  // error: moved here but used again
    return rows.length()

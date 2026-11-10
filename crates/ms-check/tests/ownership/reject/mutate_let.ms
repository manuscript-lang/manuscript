fn f() Int:
    xs := [1]
    xs.append(2)  // error: is an immutable binding
    return xs.length()

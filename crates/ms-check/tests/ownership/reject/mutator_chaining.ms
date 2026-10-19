fn f() Int:
    var xs = [1]
    xs.append(2).append(3)  # error: result cannot be used
    return xs.length()

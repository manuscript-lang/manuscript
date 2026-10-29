fn f() Int:
    let xs = [1]
    xs.append(2)  # error: declared with let
    return xs.length()

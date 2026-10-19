fn f() Int:
    var xs = [1]
    xs.append(2).append(3)  # error: member append on Unit
    return xs.length()

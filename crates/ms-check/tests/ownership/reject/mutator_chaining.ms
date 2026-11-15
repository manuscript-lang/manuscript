fn f() Int:
    var xs = [1]
    xs.append(2).append(3)  // error: member append on Void
    return xs.length()

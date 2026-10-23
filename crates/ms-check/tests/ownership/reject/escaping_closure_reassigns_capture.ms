fn counter() fn() Int:
    var n = 0
    return fn() Int:  # error: cannot be returned
        n += 1
        return n

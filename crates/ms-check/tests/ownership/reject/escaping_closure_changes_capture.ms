fn make() fn() Unit:
    var xs = [0]
    return fn() Unit:  # error: cannot be returned
        xs.append(1)

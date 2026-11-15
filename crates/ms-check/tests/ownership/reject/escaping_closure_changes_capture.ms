fn make() fn() Void:
    var xs = [0]
    return fn() Void:  // error: cannot be returned
        xs.append(1)

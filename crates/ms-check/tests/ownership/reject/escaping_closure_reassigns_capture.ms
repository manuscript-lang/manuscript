def counter() -> Callable[[], Int]:
    var n = 0

    return lambda () -> Int:  # error: cannot be returned
        n += 1
        return n

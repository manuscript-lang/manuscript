def make() -> Callable[[], Unit]:
    var xs = [0]
    return lambda () -> Unit:  # error: cannot be returned
        xs.append(1)

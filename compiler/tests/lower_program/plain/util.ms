fn bump(x: Int) Int:
    return x + 1

export fn twice(x: Int) Int:
    return bump(x) + bump(x)

export fn scale(x: Float, by: Float) Float:
    return x * by

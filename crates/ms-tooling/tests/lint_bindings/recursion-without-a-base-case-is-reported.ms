fn forever(n: Int) Int:
    return forever(n - 1)

fn both(n: Int) Int:
    if n > 0:
        return both(n - 1)
    else:
        return both(n + 1)

export fn main() Int:
    return 0

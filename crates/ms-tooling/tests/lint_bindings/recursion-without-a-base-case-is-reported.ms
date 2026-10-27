def forever(n: Int) -> Int:
    return forever(n - 1)

def both(n: Int) -> Int:
    if n > 0:
        return both(n - 1)
    else:
        return both(n + 1)

export def main() -> Int:
    return 0

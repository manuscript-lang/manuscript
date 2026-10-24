def add_one(x: Int) -> Int:
    return x + 1

def bump(x: Int) -> Int:
    return add_one(x)

export def main() -> Int:
    return bump(9223372036854775807)

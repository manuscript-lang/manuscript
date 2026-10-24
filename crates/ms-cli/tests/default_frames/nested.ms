def divide(value: Int = 1 / 0) -> Int:
    return value

def outer(value: Int = divide()) -> Int:
    return value

export def main() -> Int:
    return outer()

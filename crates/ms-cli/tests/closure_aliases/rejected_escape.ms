def escape() -> Callable[[], Unit]:
    var rows = [[1]]
    var first = rows[0]
    return lambda: first.append(9)

export def main() -> Int:
    return 0

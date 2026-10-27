export def main() -> Int:
    var items = [1, 2, 3]
    items.set(value: 8, 0)
    items.insert(value: 5, 1)
    if items[0] != 8 or items[1] != 5 or items.length() != 4:
        return 1
    return 0

type Plain:
    value: Int

export def main() -> Int:
    var items = [Plain(2), Plain(1)]
    items.sort()
    return items.length()

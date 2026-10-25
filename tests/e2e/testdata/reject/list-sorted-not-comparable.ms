type Plain:
    value: Int

export def main() -> Int:
    return [Plain(2), Plain(1)].sorted().length()

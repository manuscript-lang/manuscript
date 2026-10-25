type Plain:
    value: Int

export def main() -> Int:
    return [Plain(2)].max().get().value

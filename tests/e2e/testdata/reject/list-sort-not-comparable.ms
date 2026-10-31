type Plain:
    value: Int

export fn main() Int:
    var items = [Plain(2), Plain(1)]
    items.sort()
    return items.length()

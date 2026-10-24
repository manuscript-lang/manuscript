type Counter:
    count: Int

impl Counter:
    var def around(action: Callable[[], Unit]) -> Unit:
        action()

export def main() -> Int:
    var counts = [Counter(count: 1)]
    var first = counts[0]
    let around = first.around
    around(lambda: first.count += 10)
    return 0

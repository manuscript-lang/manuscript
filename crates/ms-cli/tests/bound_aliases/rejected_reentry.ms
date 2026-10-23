type Counter:
    count: Int

impl Counter:
    var fn around(action: fn() Unit) Unit:
        action()

export fn main() Int:
    var counts = [Counter(count: 1)]
    var first = counts[0]
    let around = first.around
    around(fn(): first.count += 10)
    return 0

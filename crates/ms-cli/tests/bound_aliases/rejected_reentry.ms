type Counter:
    count: Int

fn var Counter.around(action: fn() Unit) Unit:
    action()

export fn main() Int:
    var counts = [Counter(count: 1)]
    var first = counts[0]
    around := first.around
    around(fn: first.count += 10)
    return 0

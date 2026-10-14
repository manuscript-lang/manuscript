fn add(left: Int, right: Int) -> Int: left + right
fn offset(value: Int, delta: Int = 1) -> Int: value + delta
fn reordered(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = add(right: index, left: total)
        index = index + 1
    return total
fn defaults(limit: Int) -> Int:
    var value = 1000
    var index = 0
    while index < limit:
        value = offset(value)
        index = index + 1
    return value - 1000

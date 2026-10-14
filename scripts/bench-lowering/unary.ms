fn negate(input: Int, limit: Int) -> Int:
    var value = input
    var index = 0
    while index < limit:
        value = -value
        index = index + 1
    return value

fn negate_float(input: Float, limit: Int) -> Float:
    var value = input
    var index = 0
    while index < limit:
        value = -value
        index = index + 1
    return value

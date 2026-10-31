fn helper(left: Int, right: Int) Int:
    return left + right

export fn defaults(
    first: Int = -3,
    second: Int = helper(left: first, right: 2),
    text: String = "literal, )",
    callback: fn(Int) Int = (
        fn(value: Int) Int:
            return value + 1
    )
) Int:
    return callback(second)

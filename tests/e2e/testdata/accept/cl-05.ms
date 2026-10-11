fn increase(value: Int) -> Int:
    return value + 1

fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int:
    return transform(value: value)

test "function label compatibility":
    let transform: fn(value: Int) -> Int = increase
    assert apply(value: 4, transform: transform) == 5

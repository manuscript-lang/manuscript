fn add(left: Int, right: Int) -> Int: left + right
fn identity(value: Int) -> Int: value
fn forward(value: Int) -> Int: identity(value)
fn computed_forward(value: Int) -> Int: add(value, 1)

fn calls(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = add(total, index)
        index = index + 1
    return total

fn mixed(limit: Int) -> Int:
    let dynamic: fn(left: Int, right: Int) -> Int = add
    var total = 0
    var index = 0
    while index < limit:
        total = dynamic(total, index)
        index = index + 1
    return total

// expect-mir: "clone"
fn identity(value: String) String:
    return value

export fn main() Int:
    let f = identity
    let value = f("value-{17}")
    return if value == "value-17": 0 else: 1

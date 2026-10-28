fn add_one(x: Int) Int:
    return x + 1

fn bump(x: Int) Int:
    return add_one(x)

export fn main() Int:
    return bump(9223372036854775807)

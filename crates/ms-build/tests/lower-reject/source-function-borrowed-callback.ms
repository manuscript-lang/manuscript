fn identity(value: fn(Int) Int) fn(Int) Int:
    return value

fn add_one(value: Int) Int:
    return value + 1

export fn main() Int:
    f := identity
    out := f(add_one)
    return out(1) - 2

fn divide(value: Int = 1 / 0) Int:
    return value

fn outer(value: Int = divide()) Int:
    return value

export fn main() Int:
    return outer()

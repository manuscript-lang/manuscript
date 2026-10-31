fn divide(value: Int = 1 / "".byte_length()) Int:
    return value

fn outer(value: Int = divide()) Int:
    return value

export fn main() Int:
    return outer()

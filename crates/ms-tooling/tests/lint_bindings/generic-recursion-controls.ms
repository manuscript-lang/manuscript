fn terminating[T](value: T, count: Int) Int:
    if count <= 0:
        return 1

    return terminating[T](value, count - 1)

fn conditional[T](value: T, stop: Bool) Bool:
    return stop or conditional[T](value, true)

fn other[T](_value: T) Int:
    return 2

fn caller[T](value: T) Int:
    return other[T](value)

export fn main() Int:
    if not conditional[Int](1, false):
        return 1

    return terminating[Int](1, 2) + caller[Int](1)

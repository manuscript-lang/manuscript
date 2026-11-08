fn loop[T](value: T) Int:
    return loop[T](value)

export fn main() Int:
    return loop[Int](1)

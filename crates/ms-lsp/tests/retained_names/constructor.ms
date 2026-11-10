type Item[T]:
    value: T

fn caller() Int:
    return Item[Int](1).value

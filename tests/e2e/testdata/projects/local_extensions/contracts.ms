export interface Read[T]:
    fn get() -> T

export fn invoke[T: Read[Int]](value: T) -> Int:
    return value.get()

export fn relay[T: Read[Int]](value: T) -> Int:
    return invoke(value)

export fn as_view[T: Read[Int]](value: T) -> Read[Int]:
    return Read[Int](value)

export fn read_view(value: Read[Int]) -> Int:
    return value.get()

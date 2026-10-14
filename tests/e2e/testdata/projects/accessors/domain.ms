export type Item:
    count: Int

export interface Read[T]:
    get value -> T

export fn generic[T: Read[Int]](value: T) -> Int:
    return value.value

export fn as_view[T: Read[Int]](value: T) -> Read[Int]:
    return Read[Int](value)

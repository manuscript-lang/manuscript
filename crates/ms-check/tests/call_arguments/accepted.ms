def choose[T](first: T, second: T, third: T = first) -> T:
    return second

type Row[T]:
    first: T
    second: T
    third: T = first

def apply[T, U](callback: Callable[[T], U], value: T) -> U:
    return callback(value)

def exercise() -> Int:
    let _mixed = choose(second: 2, 1)
    let _explicit = choose[Int](third: 3, second: 2, 1)
    let _row = Row(second: 2, 1)
    let _sized = choose[Int8](second: 2, 1)
    let _optional = some(1)
    let _callback = apply(value: 1, lambda x: x + 1)
    let callable: Callable[[Int, Int, Int], Int] = choose[Int]
    return callable(1, 2, 3)

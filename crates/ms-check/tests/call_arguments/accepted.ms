fn choose[T](first: T, second: T, third: T = first) T:
    return second

type Row[T]:
    first: T
    second: T
    third: T = first

fn apply[T, U](callback: fn(T) U, value: T) U:
    return callback(value)

fn exercise() Int:
    let _mixed = choose(second: 2, 1)
    let _explicit = choose[Int](third: 3, second: 2, 1)
    let _row = Row(second: 2, 1)
    let _sized = choose[Int8](second: 2, 1)
    let _optional = some(1)
    let _callback = apply(value: 1, fn x: x + 1)
    let callable: fn(Int, Int, Int) Int = choose[Int]
    return callable(1, 2, 3)

import List from "@std/collections.ms"

fn build(count: Int) -> List[Int]:
    let values: List[Int] = []
    var i = 0

    while i < count:
        values.append(i * 7919 % 100003)
        i = i + 1

    return values

fn index(values: List[Int], count: Int) -> Int:
    var total = 0
    var i = 0

    while i < count:
        total = total + values.at(i % values.length()).unwrap()
        i = i + 1

    return total

fn iterate(values: List[Int]) -> Int:
    var total = 0

    for value in values:
        total = total + value

    return total

type Total:
    value: Int

fn callbacks(values: List[Int]) -> Int:
    let total = Total(0)
    values.for_each(
        fn(value):
            total.value = total.value + value
    )
    return total.value

fn sorted(values: List[Int]) -> List[Int]:
    return values.sorted(compare)

fn compare(left: Int, right: Int) -> Int:
    if left < right: return -1
    if left > right: return 1

    return 0

export fn main() -> Int: return 0

fn callback_write(values: List[Int]) -> Int:
    let total = Total(0)
    values.for_each(
        fn(value):
            total.value = total.value + value

            if value == 0:
                values.with_value(index: 0, value: 7)
    )
    return total.value

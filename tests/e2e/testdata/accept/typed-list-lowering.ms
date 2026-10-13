import panic from "@std/faults.ms"

type Holder:
    values: List[Int]

fn compare(left: Int, right: Int) -> Int: left - right

fn generic_read[T](values: List[T], index: Int) -> Optional[T]: values.at(index)

fn matched(values: List[Int], index: Int) -> Int:
    return match values.at(index):
        some(value): value + 1
        none: 0

fn sum(values: List[Int]) -> Int:
    var total = 0

    for value in values:
        total = total + value

        if value == 2: values.append(90)

    return total

test "typed access match range and comparator preserve generic aliases":
    let values = [10000, 20000, 30000]
    if values.at(-1).unwrap() != 30000 or matched(values, -2) != 20001:
        return panic("relative access")
    if matched(values, 9) != 0: return panic("absent match")

    let escaped = values.at(1)
    if escaped.unwrap() != 20000 or generic_read(values, -1).unwrap() != 30000:
        return panic("Optional and generic boundaries")

    let at = values.at
    if at(0).unwrap() != 10000: return panic("bound at")

    let sorted = [30000, 10000, 20000].sorted(compare)
    if sorted.at(0).unwrap() != 10000 or sorted.at(-1).unwrap() != 30000:
        return panic("typed named comparator")

    let bias = 1000
    let callback = fn(left: Int, right: Int) -> Int: (left + bias) - (right + bias)
    let captured = [30000, 10000, 20000].sorted(callback)
    if captured.at(0).unwrap() != 10000: return panic("typed captured comparator")

    let floats = [3.5, -1.0, 2.5].sorted(
        fn(left: Float, right: Float) -> Int:
            if left < right: return -1
            if left > right: return 1

            return 0
    )
    if floats.at(0).unwrap() != -1.0: return panic("typed Float comparator")
    if [true, false].at(-1).unwrap() or ["first", "last"].at(-1).unwrap() != "last":
        return panic("Bool/String typed access")

    let range_values = [1, 2, 3]
    if sum(range_values) != 6 or range_values.length() != 4:
        return panic("captured initial range length")

    var receiver = [7]
    let original = (
        receiver
        .at(
            match some(0):
                some(index):
                    receiver = [9]
                    index
                none: 0
        )
        .unwrap()
    )
    if original != 7 or receiver.at(0).unwrap() != 9:
        return panic("receiver capture order")

    let holder = Holder([4])

    let independent = match holder.values.slice(0, 1):
        ok(value): value
        error(failure): panic(failure.toString())

    holder.values.append(5)
    if independent.length() != 1: return panic(
        "strict Result slicing and separate backing"
    )

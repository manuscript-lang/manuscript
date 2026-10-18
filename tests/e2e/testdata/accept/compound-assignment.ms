import panic from "@std/faults.ms"

type Counter:
    count: Int
    label: String

type Outer:
    inner: Counter

fn tally(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

test "compound assignment on bindings":
    var number = 20
    number += 5
    number -= 3
    number *= 2
    number /= 4
    number %= 7
    var ratio = 1.5
    ratio *= 2.0
    var text = "a"
    text += "b"
    if number != 4 or ratio != 3.0 or text != "ab":
        return panic("compound assignment on bindings")

test "right side groups as one operand":
    var number = 10
    number -= 4 - 1
    number *= 1 + 1
    if number != 14:
        return panic("compound right side")

test "compound assignment on fields":
    let counter = Counter(1, "x")
    counter.count += 4
    counter.count *= counter.count
    counter.label += "y"
    let outer = Outer(counter)
    outer.inner.count -= 5
    if counter.count != 20 or counter.label != "xy" or tally([1, 2, 3]) != 6:
        return panic("compound assignment on fields")

test "compound assignment in loops":
    var index = 0
    var total = 0

    while index < 5:
        total += index
        index += 1

    if total != 10 or index != 5:
        return panic("compound assignment loop")

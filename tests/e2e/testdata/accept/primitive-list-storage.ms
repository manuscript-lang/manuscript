import {expect_equal, expect_false, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

fn append_value[T](values: List[T], value: T) List[T]:
    values.append(value)
    return values

fn forwarded[T](values: List[T]) List[T]:
    return values

type Lists:
    values: List[Int]

test "primitive storage retains generic record Optional and saved aliases":
    var values = [9223372036854775807, -9223372036854775808]
    let record = Lists(values)
    let wrapped: Optional[List[Int]] = some(values)
    let append = forwarded(values).append
    for i in range(0, 4096):
        append_value(record.values, i)
    append(17)
    wrapped.get().set(0, 41)
    try expect_false(
        not (
            values.length() == 4099
            and record.values[0] == 41
            and values[-1] == 17
        )
    )
    var copy = values.clone()
    values.set(0, 42)
    try expect_equal(copy[0], 41)
    let nested: List[Optional[Int]] = [some(7), none]
    try expect_false(not (nested[0].get() == 7 and nested[1].is_none()))

test "Float Bool and String preserve mutation traversal and width":
    var floats = [1e-300, 1e300, 0.25]
    let clone = floats.clone()
    var seen: List[Float] = []
    var index = 0

    for value in floats:
        seen.append(value)
        if index == 0:
            floats.set(1, 0.5)
        index += 1

    try expect_false(not (seen == [1e-300, 0.5, 0.25] and clone[1] == 1e300))
    var booleans = [true, false, true]
    booleans.remove(0)
    booleans.prepend(false)
    var strings = ["a", "b", "c"]
    strings.reverse_in_place()
    try expect_false(
        not (booleans == [false, false, true] and strings == ["c", "b", "a"])
    )

test "stable sort and strict Result slice preserve separate storage":
    let values = [7, 1, 4, 8, 2, 5]
    var sorted = values.sorted(fn(left, right): return left % 3 - right % 3)
    sorted.set(0, 99)
    try expect_equal(values[0], 7)

    if let copy = values.slice(-2, 6):
        copy.set(0, 12)
        try expect_false(not (copy == [12, 5] and values[4] == 2))
    else:
        return fail("valid strict slice failed")

    try expect_false(values.slice(-7, 6).is_ok())

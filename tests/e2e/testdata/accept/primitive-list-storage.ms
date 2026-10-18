import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

fn append_value[T](values: List[T], value: T) -> List[T]:
    return values.append(value)

fn forwarded[T](values: List[T]) -> List[T]:
    return values

type Lists:
    values: List[Int]

test "primitive storage retains generic record Optional and saved aliases":
    let values = [9223372036854775807, -9223372036854775808]
    let record = Lists(values)
    let wrapped: Optional[List[Int]] = some(values)
    let append = forwarded(values).append
    for i in range(0, 4096):
        append_value(record.values, i)
    append(17)
    wrapped.unwrap().set(0, 41)
    (
        not (
            values.length() == 4099
            and record.values[0].unwrap() == 41
            and values[-1].unwrap() == 17
        )
    ) | try expect_false
    let copy = values.clone()
    values.set(0, 42)
    copy[0].unwrap() | try expect_equal(expected: 41)
    let nested: List[Optional[Int]] = [some(7), none]
    ((nested[0].unwrap().unwrap() == 7 and nested[1].unwrap().is_none())) | try expect_true

test "Float Bool and String preserve mutation traversal and width":
    let floats = [1e-300, 1e300, 0.25]
    let clone = floats.clone()
    let seen: List[Float] = []
    var index = 0

    for value in floats:
        seen.append(value)
        if index == 0:
            floats.set(1, 0.5)
        index = index + 1

    (seen == [1e-300, 0.5, 0.25] and clone[1].unwrap() == 1e300) | try expect_true
    let booleans = [true, false, true]
    booleans.remove(0)
    booleans.prepend(false)
    let strings = ["a", "b", "c"]
    strings.reverse_in_place()
    (booleans == [false, false, true] and strings == ["c", "b", "a"]) | try expect_true

test "stable sort and strict Result slice preserve separate storage":
    let values = [7, 1, 4, 8, 2, 5]
    let sorted = values.sorted(fn(left, right): return left % 3 - right % 3)
    sorted.set(0, 99)
    values[0].unwrap() | try expect_equal(expected: 7)

    match values.slice(-2, 6):
        ok(copy):
            copy.set(0, 12)
            ((copy == [12, 5] and values[4].unwrap() == 2) | try expect_true)
        error(_):
            return fail("valid strict slice failed")

    match values.slice(-7, 6):
        ok(_):
            return fail("invalid slice succeeded")
        error(_):
            return

# conform: tags=closures,control-flow,faults,formatter,generics,lists,modules,mutation,numbers,optional,parser,records,stdlib-collections,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/primitive-list-storage.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

fn append_value[T](var values: List[T], value: T) List[T]:
    values.append(value)
    return values.clone()

fn forwarded[T](values: List[T]) List[T]:
    return values.clone()

type Lists:
    values: List[Int]

test "primitive storage retains generic record Optional and independent copies":
    var values = [9223372036854775807, -9223372036854775808]
    var record = Lists(values.clone())
    let wrapped: List[Int]? = values.clone()
    for i in 0..4096:
        append_value(var record.values, i)
    values.append(17)
    try expect_equal(values.length(), 3)
    try expect_equal(record.values.length(), 4098)
    try expect_equal(values[-1], 17)
    try expect_equal(values[0], 9223372036854775807)
    try expect_equal(wrapped.get() [0], 9223372036854775807)

    var copy = values.clone()
    values.set(0, 42)
    try expect_equal(copy[0], 9223372036854775807)

    let nested: List[Int?] = [7, none]
    try expect_false(not (nested[0].get() == 7 and nested[1].is_none()))

test "Float Bool and String preserve mutation traversal and width":
    var floats = [1e-300, 1e300, 0.25]
    let clone = floats.clone()
    var seen: List[Float] = []
    var index = 0

    for value in floats.clone():
        seen.append(value)
        if index == 0:
            floats.set(1, 0.5)
        index += 1

    try expect_false(
        not (
            seen == [1e-300, 1e300, 0.25]
            and clone[1] == 1e300
            and floats[1] == 0.5
        )
    )

    var booleans = [true, false, true]
    booleans.remove(0)
    booleans.prepend(false)

    var strings = ["a", "b", "c"]
    strings.reverse()
    try expect_false(
        not (booleans == [false, false, true] and strings == ["c", "b", "a"])
    )

test "stable sort and strict Result slice preserve separate storage":
    let values = [7, 1, 4, 8, 2, 5]
    var sorted = values.sorted(fn left, right: return left % 3 - right % 3)
    sorted.set(0, 99)
    try expect_equal(values[0], 7)

    if let slice = values.slice(-2, 6):
        var copy = slice.clone()
        copy.set(0, 12)
        try expect_false(not (copy == [12, 5] and values[4] == 2))
    else:
        return fail("valid strict slice failed")

    try expect_false(values.slice(-7, 6).is_ok())

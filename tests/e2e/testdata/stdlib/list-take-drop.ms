import TextError from "@std/core.ms"
import expect_equal, expect_false from "@std/test.ms"

test "List take and drop copy prefix and remainder":
    let values = [1, 2, 3]
    try expect_false(values.take(2) != [1, 2] or values.drop(2) != [3])

test "List take and drop clamp positive counts and preserve empty boundaries":
    let values = [1, 2, 3]
    try expect_false(not (values.take(0).is_empty()) or values.drop(0) != values)
    try expect_false(values.take(3) != values or not (values.drop(3).is_empty()))
    try expect_false(
        (
            values.take(9999999) != values
            or not (values.drop(9999999).is_empty())
        )
    )

    let empty: List[Int] = []
    try expect_false(not (empty.take(0).is_empty()) or not (empty.drop(7).is_empty()))

test "List take and drop allocate independent outer storage":
    let values = [1, 2, 3]
    var prefix = values.take(3)
    var remainder = values.drop(0)
    prefix.set(0, 9)
    prefix.append(4)
    remainder.remove(0)
    try expect_false(
        (values != [1, 2, 3] or prefix != [9, 2, 3, 4] or remainder != [2, 3])
    )

    var empty_take = values.take(0)
    var empty_drop = values.drop(3)
    empty_take.append(5)
    empty_drop.append(6)
    try expect_false(not (values.take(0).is_empty()) or not (values.drop(3).is_empty()))

type Box:
    value: Int

test "List take and drop copy payloads before changing them":
    let boxes = [Box(1), Box(2)]
    var prefix = boxes.take(1)
    let remainder = boxes.drop(0)
    var changed = prefix.get(0).clone()
    changed.value = 7
    prefix.set(0, changed)
    try expect_false(
        boxes.get(0).value != 1 or remainder.get(0).value != 1 or prefix.get(
            0
        ).value != 7
    )

    let nested = [1]
    let lists = [nested.clone()]
    var copied = lists.take(1).drop(0)
    var inner = copied.get(0).clone()
    inner.append(2)
    copied.set(0, inner)
    try expect_false(nested != [1] or lists.get(0) != nested or copied.get(0) != [1, 2])

fn copy_window[T: Clonable](values: List[T], first: Int, skip: Int) List[T]:
    return values.take(first).drop(skip)

test "List take and drop support generic and nested values":
    try expect_equal(copy_window[String](["a", "b", "c"], 2, 1), ["b"])

    let values: List[Result[Int?, TextError]] = [ok(some(1)), error(TextError("cause"))]
    try expect_equal(copy_window(values, 2, 1).get(0).err().message(), "cause")

    let callbacks = [fn(value: Int) Int: value + 1]
    try expect_equal(callbacks.take(1).drop(0).get(0)(1), 2)

test "List take and drop bound methods read the retained receiver":
    var values = [1, 2, 3, 4]
    let take = values.take
    let drop: fn(Int) List[Int] = values.drop
    try expect_false(take(7) != [1, 2, 3, 4] or drop(2) != [3, 4])

    var first = take(2)
    first.set(0, 8)
    try expect_false(take(2) != [1, 2] or first != [8, 2])

import panic from "@std/faults.ms"

test "List take and drop copy prefix and remainder":
    let values = [1, 2, 3]
    if values.take(2) != [1, 2] or values.drop(2) != [3]: return panic(
        "List prefix/remainder"
    )

test "List take and drop clamp positive counts and preserve empty boundaries":
    let values = [1, 2, 3]
    if not (values.take(0).is_empty()) or values.drop(0) != values: return panic(
        "zero copy count"
    )
    if values.take(3) != values or not (values.drop(3).is_empty()): return panic(
        "exact copy count"
    )
    if values.take(9999999) != values or not (values.drop(9999999).is_empty()): return panic(
        "oversized copy count"
    )

    let empty: List[Int] = []
    if not (empty.take(0).is_empty()) or not (empty.drop(7).is_empty()): return panic(
        "empty list copies"
    )

test "List take and drop allocate independent outer storage":
    let values = [1, 2, 3]
    let prefix = values.take(3)
    let remainder = values.drop(0)
    prefix.set(0, 9).append(4)
    remainder.remove(0)
    if (
        values != [1, 2, 3]
        or prefix != [9, 2, 3, 4]
        or remainder != [2, 3]
    ): return panic("list copy storage alias")

    let empty_take = values.take(0)
    let empty_drop = values.drop(3)
    empty_take.append(5)
    empty_drop.append(6)
    if not (values.take(0).is_empty()) or not (values.drop(3).is_empty()): return panic(
        "empty copy storage alias"
    )

type Box:
    value: Int

test "List take and drop retain shallow payload references":
    let shared = Box(1)
    let nested = [1]
    let boxes = [shared, Box(2)]
    let prefix = boxes.take(1)
    let remainder = boxes.drop(0)
    prefix.at(0).unwrap().value = 7
    if shared.value != 7 or remainder.at(0).unwrap().value != 7: return panic(
        "record payload cloned"
    )

    let lists = [nested]
    let copied = lists.take(1).drop(0)
    copied.at(0).unwrap().append(2)
    if nested != [1, 2] or lists.at(0).unwrap() != nested: return panic(
        "nested list payload cloned"
    )

fn copy_window[T](values: List[T], first: Int, skip: Int) -> List[T]:
    return values.take(first).drop(skip)

test "List take and drop support generic and nested values":
    if copy_window[String](
        ["a", "b", "c"],
        2,
        1
    ) != ["b"]: return panic("generic copying")

    let values: List[Result[Optional[Int], List[String]]] = [
        ok(some(1)),
        error(["cause"])
    ]
    if copy_window(values, 2, 1).at(0).unwrap().unwrap_error() != ["cause"]: return panic(
        "nested result copying"
    )

    let callbacks = [fn(value: Int) -> Int: value + 1]
    if callbacks.take(1).drop(0).at(0).unwrap()(value: 1) != 2: return panic(
        "unconstrained function payload"
    )

test "List take and drop bound methods read the retained receiver at call time":
    var values = [1, 2, 3]
    let take = values.take
    let drop: fn(count: Int) -> List[Int] = values.drop
    values.append(4)
    values = [9]
    if take(count: 7) != [1, 2, 3, 4] or drop(2) != [3, 4]: return panic(
        "bound receiver membership"
    )

    let first = take(2)
    first.set(0, 8)
    if take(2) != [1, 2] or values != [9]: return panic("bound copy reused storage")

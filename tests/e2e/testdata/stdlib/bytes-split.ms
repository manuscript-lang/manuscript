import {expect_equal, expect_false} from "@std/testing.ms"
import Bytes from "@std/bytes.ms"

test "Bytes split is binary safe":
    let data = Bytes([255, 0, 1, 0, 254])
    try expect_equal(data.split(Bytes([0])), [Bytes([255]), Bytes([1]), Bytes([254])])

test "Bytes split handles exact and nonoverlapping separators":
    let empty = Bytes([])
    try expect_equal(
        Bytes([0, 7, 0]).split(Bytes([0])), [empty.clone(), Bytes([7]), empty.clone()]
    )
    try expect_equal(
        Bytes([0, 0]).split(Bytes([0])), [empty.clone(), empty.clone(), empty.clone()]
    )
    try expect_equal(
        Bytes([255, 0, 9, 255, 0]).split(Bytes([255, 0])),
        [empty.clone(), Bytes([9]), empty.clone()]
    )
    try expect_equal(Bytes([1, 1, 1]).split(Bytes([1, 1])), [empty.clone(), Bytes([1])])
    try expect_equal(Bytes([1]).split(Bytes([1, 2])), [Bytes([1])])
    try expect_equal(empty.split(Bytes([0])), [empty])

test "Bytes empty separator splits bytes without decoding":
    let empty = Bytes([])
    try expect_false(not (empty.split(empty).is_empty()))
    try expect_equal(
        Bytes([0, 255, 128]).split(empty), [Bytes([0]), Bytes([255]), Bytes([128])]
    )

    let scalars = "é".to_bytes().split(empty)
    try expect_equal(scalars, [Bytes([195]), Bytes([169])])
    try expect_false(scalars.get(0).decode_utf8().is_some())
    try expect_equal("é".to_bytes().split(Bytes([169])), [Bytes([195]), empty])

test "Bytes split optional limits truncate parts":
    let data = Bytes([1, 0, 2, 0, 3, 0])
    let separator = Bytes([0])
    let expected = [Bytes([1]), Bytes([2]), Bytes([3]), Bytes([])]
    try expect_false(
        (
            data.split(separator) != expected
            or data.split(separator, none) != expected
        )
    )
    try expect_equal(data.split(separator, some(2)), [Bytes([1]), Bytes([2])])
    try expect_equal(data.split(separator, 1), [Bytes([1])])
    try expect_false(
        (
            not (data.split(separator, 0).is_empty())
            or not (Bytes([]).split(separator, 0).is_empty())
        )
    )
    try expect_equal(data.split(separator, 9999999), expected)
    try expect_equal(data.split(Bytes([]), 2), [Bytes([1]), Bytes([0])])

fn split_then[T](data: Bytes, separator: Bytes, transform: fn(value: List[Bytes]) T) T:
    return data.split(separator) | transform

fn call_split(
    operation: fn(separator: Bytes, max_parts: Optional[Int]) List[Bytes]
) List[Bytes]:
    return operation(Bytes([0]), some(2))

test "Bytes split bound methods and generic forwarding retain contracts":
    var data = Bytes([1, 0, 2])
    let split = data.split
    let typed: fn(separator: Bytes, max_parts: Optional[Int]) List[Bytes] = data.split
    data = Bytes([9])
    try expect_equal(split(Bytes([0])), [Bytes([1]), Bytes([2])])
    try expect_equal(split(max_parts: 1, Bytes([0])), [Bytes([1])])
    try expect_equal(call_split(typed), [Bytes([1]), Bytes([2])])
    try expect_false(
        (
            split_then[Bool](
                Bytes([1, 0, 2]), Bytes([0]), fn(value): value.length() == 2
            ) != true
        )
    )

test "Bytes split returns independent List storage and immutable views":
    let data = Bytes([1, 0, 2])
    var first = data.split(Bytes([0]))
    let second = data.split(Bytes([0]))
    let payload = first.get(0).clone()
    let edited = payload.with_value(0, 99)
    var extracted = payload.values()
    extracted.set(0, 88)
    first.set(0, Bytes([77]))
    first.append(Bytes([66]))
    try expect_false(
        (
            edited != Bytes([99])
            or payload != Bytes([1])
            or data != Bytes([1, 0, 2])
        )
    )
    try expect_equal(second, [Bytes([1]), Bytes([2])])

    let empty = Bytes([])
    var zero_parts = data.split(Bytes([0]), 0)
    zero_parts.append(empty.clone())
    try expect_false(not (data.split(Bytes([0]), 0).is_empty()))

    var no_parts = empty.split(empty)
    no_parts.append(Bytes([1]))
    try expect_false(not (empty.split(empty).is_empty()))

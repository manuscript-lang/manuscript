import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import Bytes from "@std/bytes.ms"

test "Bytes split is binary safe":
    let data = Bytes([255, 0, 1, 0, 254])
    data.split(Bytes([0])) | try expect_equal(
        expected: [Bytes([255]), Bytes([1]), Bytes([254])]
    )

test "Bytes split handles exact and nonoverlapping separators":
    let empty = Bytes([])
    Bytes([0, 7, 0]).split(Bytes([0])) | try expect_equal(
        expected: [empty, Bytes([7]), empty]
    )
    Bytes([0, 0]).split(Bytes([0])) | try expect_equal(expected: [empty, empty, empty])
    Bytes([255, 0, 9, 255, 0]).split(Bytes([255, 0])) | try expect_equal(
        expected: [empty, Bytes([9]), empty]
    )
    Bytes([1, 1, 1]).split(Bytes([1, 1])) | try expect_equal(
        expected: [empty, Bytes([1])]
    )
    Bytes([1]).split(Bytes([1, 2])) | try expect_equal(expected: [Bytes([1])])
    empty.split(Bytes([0])) | try expect_equal(expected: [empty])

test "Bytes empty separator splits bytes without decoding":
    let empty = Bytes([])
    (empty.split(empty).is_empty()) | try expect_true
    Bytes([0, 255, 128]).split(empty) | try expect_equal(
        expected: [Bytes([0]), Bytes([255]), Bytes([128])]
    )
    let scalars = "é".to_bytes().split(empty)
    scalars | try expect_equal(expected: [Bytes([195]), Bytes([169])])
    scalars.at(0).unwrap().to_string().is_some() | try expect_false
    "é".to_bytes().split(Bytes([169])) | try expect_equal(
        expected: [Bytes([195]), empty]
    )

test "Bytes split optional limits truncate parts":
    let data = Bytes([1, 0, 2, 0, 3, 0])
    let separator = Bytes([0])
    let expected = [Bytes([1]), Bytes([2]), Bytes([3]), Bytes([])]
    (data.split(separator) != expected or data.split(separator, none) != expected) | try expect_false
    data.split(separator: separator, max_parts: some(2)) | try expect_equal(
        expected: [Bytes([1]), Bytes([2])]
    )
    data.split(separator, max_parts: 1) | try expect_equal(expected: [Bytes([1])])
    (
        (
            not (data.split(separator, 0).is_empty())
            or not (Bytes([]).split(separator, 0).is_empty())
        )
    ) | try expect_false
    data.split(separator, 9999999) | try expect_equal(expected: expected)
    data.split(Bytes([]), 2) | try expect_equal(expected: [Bytes([1]), Bytes([0])])

fn split_then[T](
    data: Bytes,
    separator: Bytes,
    transform: fn(value: List[Bytes]) -> T
) -> T:
    return transform(data.split(separator))

fn call_split(
    operation: fn(separator: Bytes, max_parts: Optional[Int]) -> List[Bytes]
) -> List[Bytes]:
    return operation(Bytes([0]), some(2))

test "Bytes split bound methods and generic forwarding retain contracts":
    var data = Bytes([1, 0, 2])
    let split = data.split
    let typed: fn(separator: Bytes, max_parts: Optional[Int]) -> List[Bytes] = data.split
    data = Bytes([9])
    split(Bytes([0])) | try expect_equal(expected: [Bytes([1]), Bytes([2])])
    split(max_parts: 1, separator: Bytes([0])) | try expect_equal(
        expected: [Bytes([1])]
    )
    call_split(typed) | try expect_equal(expected: [Bytes([1]), Bytes([2])])
    try expect_false(
        (
            split_then[Bool](
                Bytes([1, 0, 2]),
                Bytes([0]),
                fn(value): value.length() == 2
            ) != true
        )
    )

test "Bytes split returns independent List storage and immutable views":
    let data = Bytes([1, 0, 2])
    let first = data.split(Bytes([0]))
    let second = data.split(Bytes([0]))
    let payload = first.at(0).unwrap()
    let edited = payload.with_value(0, 99)
    let extracted = payload.values()
    extracted.set(0, 88)
    first.set(0, Bytes([77])).append(Bytes([66]))
    (edited != Bytes([99]) or payload != Bytes([1]) or data != Bytes([1, 0, 2])) | try expect_false
    second | try expect_equal(expected: [Bytes([1]), Bytes([2])])
    let empty = Bytes([])
    let zero_parts = data.split(Bytes([0]), 0)
    zero_parts.append(empty)
    (data.split(Bytes([0]), 0).is_empty()) | try expect_true
    let no_parts = empty.split(empty)
    no_parts.append(Bytes([1]))
    (empty.split(empty).is_empty()) | try expect_true

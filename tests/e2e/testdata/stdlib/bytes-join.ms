from "@std/test.ms" import expect_equal
from "@std/bytes.ms" import Bytes, join

test "join concatenates parts in order":
    try expect_equal(
        join([Bytes([1, 2]), Bytes([]), Bytes([255]), Bytes([0, 7])]),
        Bytes([1, 2, 255, 0, 7])
    )

test "join of nothing is empty":
    let none_at_all: List[Bytes] = []
    try expect_equal(join(none_at_all), Bytes([]))
    try expect_equal(join([Bytes([]), Bytes([])]), Bytes([]))

test "join leaves its parts unchanged":
    let parts = [Bytes([3]), Bytes([4, 5])]
    let whole = join(parts)
    try expect_equal(whole, Bytes([3, 4, 5]))
    try expect_equal(parts, [Bytes([3]), Bytes([4, 5])])

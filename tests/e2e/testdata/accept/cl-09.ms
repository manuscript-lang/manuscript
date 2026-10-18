import {expect_equal, expect_true} from "@std/testing.ms"

type Box[T]:
    value: T

fn unwrap[T](box: Box[T]) -> T:
    return box.value

fn same[T: Equal](left: T, right: T) -> Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](6)
    unwrap(box: box) | try expect_equal(expected: 6)
    unwrap[Int](box: box) | try expect_equal(expected: 6)
    (same(left: 6, right: 6)) | try expect_true

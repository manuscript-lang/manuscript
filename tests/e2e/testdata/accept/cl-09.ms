import {expect_equal, expect_false} from "@std/testing.ms"

type Box[T]:
    value: T

fn unwrap[T](box: Box[T]) T:
    return box.value

fn same[T: Equal](left: T, right: T) Bool:
    return left == right

test "generic argument inference":
    let box = Box[Int](6)
    try expect_equal(unwrap(box), 6)
    try expect_equal(unwrap[Int](box), 6)
    try expect_false(not (same(6, 6)))

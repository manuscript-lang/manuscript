import {expect_equal, expect_not_equal} from "@std/testing.ms"
import Decimal from "@std/decimal.ms"

type Callback:
    handler: fn(value: Int) -> Int

fn increment(value: Int) -> Int:
    return value + 1

fn preserve_key[K: Hashable](value: K) -> K:
    return value

test "derived value equality":
    let present: Optional[Int] = some(1)
    let same: Optional[Int] = some(1)
    let missing: Optional[Int] = none
    present | try expect_equal(expected: same)
    present | try expect_not_equal(expected: missing)
    1.00d | try expect_equal(expected: 1d)
    [1, 2] | try expect_equal(expected: [1, 2])
    [1, 2] | try expect_not_equal(expected: [2, 1])
    preserve_key(value: "key") | try expect_equal(expected: "key")
    let callback = Callback(increment)

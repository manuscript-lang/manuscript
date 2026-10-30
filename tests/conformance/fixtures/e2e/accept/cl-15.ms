# conform: tags=closures,decimal,modules,optional,records,stdlib-decimal,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-15.ms
import expect_equal, expect_not_equal from "@std/test.ms"
import Decimal from "@std/decimal.ms"

type Callback:
    handler: fn(Int) Int

fn increment(value: Int) Int:
    return value + 1

fn preserve_key[K: Hashable](value: K) K:
    return value

test "derived value equality":
    let present: Int? = some(1)
    let same: Int? = some(1)
    let missing: Int? = none
    try expect_equal(present, same)
    try expect_not_equal(present, missing)
    try expect_equal(1.00d, 1d)
    try expect_equal([1, 2], [1, 2])
    try expect_not_equal([1, 2], [2, 1])
    try expect_equal(preserve_key("key"), "key")

    let _callback = Callback(increment)

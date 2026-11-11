// conform: tags=closures,decimal,modules,optional,records,stdlib-decimal,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/cl-15.ms
import (
	Decimal from "@std/math/decimal.ms",
	expect_equal, expect_not_equal from "@std/test/test.ms",
)

type Callback:
	handler: fn(Int) Int

fn increment(value: Int) Int:
	return value + 1

fn preserve_key[K: Hashable](value: K) K:
	return value

test "derived value equality":
	present: Int? := 1
	same: Int? := 1
	missing: Int? := none
	expect_equal(present, same)?
	expect_not_equal(present, missing)?
	expect_equal(1.00d, 1d)?
	expect_equal([1, 2], [1, 2])?
	expect_not_equal([1, 2], [2, 1])?
	expect_equal(preserve_key("key"), "key")?

	_callback := Callback(increment)

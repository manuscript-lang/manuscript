// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

test "integer families share one set of operations":
	a Int8 := (-5).to_int8() or panic("called Optional.get() on null")
	expect_equal(a.abs(), (5).to_int8() or panic("called Optional.get() on null"))?
	expect_equal(a.sign(), -1)?
	expect_equal(a.compare((3).to_int8() or panic("called Optional.get() on null")), -1)?
	expect_equal(a.to_float(), -5.0)?
	expect_equal(a.to_binary(), "-101")?

	u UInt16 := (255).to_uint16() or panic("called Optional.get() on null")
	expect_equal(u.to_hex(), "ff")?
	expect_equal(u.compare(u), 0)?
	expect_equal((7).abs(), 7)?
	expect_equal((-7).sign(), -1)?
	expect_equal((3).compare(4), -1)?

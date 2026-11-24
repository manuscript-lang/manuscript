// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_none from "@std/test/test.ms",
)

type Reading:
	value Int8?

enum Sample:
	Value(value Float32?)

fn tiny() Int8?: 100 + 27

fn rounded() Float32?: + (1.0000000596046448 + 0.0)

fn large() UInt64?: 9223372036854775807 + 1

fn take(value Int8?) Int8?: value

test "optional sized arithmetic keeps payload values":
	expect_equal((tiny() or panic("called Optional.get() on null")).to_int(), 127)?
	expect_equal(
		(rounded() or panic("called Optional.get() on null")).to_float64(),
		1.0000001192092896,
	)?
	expect_equal(
		(large() or panic("called Optional.get() on null")).to_string(),
		"9223372036854775808",
	)?
	expect_equal((take(1 + 2) or panic("called Optional.get() on null")).to_int(), 3)?

	callable fn(Int8?) Int8? := take
	expect_equal(
		(callable(2 * 3) or panic("called Optional.get() on null")).to_int(),
		6,
	)?

	var reading = Reading(100 + 27)
	expect_equal(
		(reading.value or panic("called Optional.get() on null")).to_int(),
		127,
	)?
	reading.value = -(60 + 67)
	expect_equal(
		(reading.value or panic("called Optional.get() on null")).to_int(),
		-127,
	)?

	values List[Int8?] := [1 + 2, null]
	expect_equal((values[0] or panic("called Optional.get() on null")).to_int(), 3)?
	expect_none(values[1])?

	sample := Sample.Value(0.25 + 0.5)

	match sample:
		Sample.Value(value): expect_equal(
			(value or panic("called Optional.get() on null")).to_float64(),
			0.75,
		)?

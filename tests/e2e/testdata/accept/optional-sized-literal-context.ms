import expect_equal, expect_none from "@std/test/test.ms"

type Reading:
	value: Int8?

enum Sample:
	Value(value: Float32?)

fn tiny() Int8?: 100 + 27

fn rounded() Float32?: + (1.0000000596046448 + 0.0)

fn large() UInt64?: 9223372036854775807 + 1

fn take(value: Int8?) Int8?: value

test "optional sized arithmetic keeps payload values":
	try expect_equal(tiny().get().to_int(), 127)
	try expect_equal(rounded().get().to_float64(), 1.0000001192092896)
	try expect_equal(large().get().to_string(), "9223372036854775808")
	try expect_equal(take(1 + 2).get().to_int(), 3)

	callable: fn(Int8?) Int8? = take
	try expect_equal(callable(2 * 3).get().to_int(), 6)

	var reading = Reading(100 + 27)
	try expect_equal(reading.value.get().to_int(), 127)
	reading.value = -(60 + 67)
	try expect_equal(reading.value.get().to_int(), -127)

	values: List[Int8?] = [1 + 2, none]
	try expect_equal(values[0].get().to_int(), 3)
	try expect_none(values[1])

	sample := Sample.Value(0.25 + 0.5)

	match sample:
		Sample.Value(value): try expect_equal(value.get().to_float64(), 0.75)

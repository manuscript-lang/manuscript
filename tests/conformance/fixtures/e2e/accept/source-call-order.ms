// conform: tags=faults,generics,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/source-call-order.ms
import expect_equal from "@std/test/test.ms"

fn pair(a: Int, b: Int) Int: a * 10 + b

test "arguments":
	var value = 1
	option: Int? := 2
	result := pair(
		a: value,
		b: match option:
			i:
				value = 9
				i
			none: 0
	)
	expect_equal(result, 12)?

fn optional(value: Int?) Int: value.get()

fn defaulted(value: Int = 3) Int: value

fn identity[T](value: T) T: value

test "source call dispatch contracts":
	expect_equal(optional(4), 4)?
	expect_equal(defaulted(5), 5)?
	expect_equal(defaulted(), 3)?
	expect_equal(pair(b: 2, a: 1), 12)?

	callback := pair
	expect_equal(callback(a: 3, b: 4), 34)?
	expect_equal(identity(6), 6)?

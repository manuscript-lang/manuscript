// conform: tags=faults,formatter,generics,match,modules,mutation,optional,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/source-call-order.ms
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

fn pair(a Int, b Int) Int => a * 10 + b

test "arguments" {
	var value = 1
	option Int? := 2
	result := pair(
		a: value,
		b: match option {
			i => {
				value = 9
				i
			} null => 0
		}
	)
	expect_equal(result, 12)?
}

fn optional(value Int?) Int => value or panic("called Optional.get() on null")

fn defaulted(value Int = 3) Int => value

fn identity[T](value T) T => value

test "source call dispatch contracts" {
	expect_equal(optional(4), 4)?
	expect_equal(defaulted(5), 5)?
	expect_equal(defaulted(), 3)?
	expect_equal(pair(b: 2, a: 1), 12)?

	callback := pair
	expect_equal(callback(a: 3, b: 4), 34)?
	expect_equal(identity(6), 6)?
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tpanic from "@std/core.ms",
// expect-formatted: \texpect_equal from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: fn pair(a, b Int) Int => a * 10 + b
// expect-formatted:
// expect-formatted: test "arguments" {
// expect-formatted: \tvar value = 1
// expect-formatted: \toption Int? := 2
// expect-formatted: \tresult := pair(
// expect-formatted: \t\ta: value,
// expect-formatted: \t\tb: match option {
// expect-formatted: \t\t\ti => {
// expect-formatted: \t\t\t\tvalue = 9
// expect-formatted: \t\t\t\ti
// expect-formatted: \t\t\t} null => 0
// expect-formatted: \t\t}
// expect-formatted: \t)
// expect-formatted: \texpect_equal(result, 12)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn optional(value Int?) Int => value or panic("called Optional.get() on null")
// expect-formatted:
// expect-formatted: fn defaulted(value Int = 3) Int => value
// expect-formatted:
// expect-formatted: fn identity[T](value T) T => value
// expect-formatted:
// expect-formatted: test "source call dispatch contracts" {
// expect-formatted: \texpect_equal(optional(4), 4)?
// expect-formatted: \texpect_equal(defaulted(5), 5)?
// expect-formatted: \texpect_equal(defaulted(), 3)?
// expect-formatted: \texpect_equal(pair(b: 2, a: 1), 12)?
// expect-formatted:
// expect-formatted: \tcallback := pair
// expect-formatted: \texpect_equal(callback(a: 3, b: 4), 34)?
// expect-formatted: \texpect_equal(identity(6), 6)?
// expect-formatted: }

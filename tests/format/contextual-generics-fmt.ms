// conform: tags=closures,control-flow,faults,formatter,generics,interfaces,lists,modules,optional,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/contextual-generics.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn fail[T](move message String) T!Error => error(Error(message))

fn fail_cause[T, E](move cause E) T!E => error(cause)

fn absent[T]() T? => null

fn identity[T](hold value T) &T => value

fn from_callback[T](factory fn() T) T => factory()

fn transform[T, U](callback fn(T) U) fn(T) U => callback

type Failure {
	detail String
}

fn failure_error(cause Failure) Error => Error(cause.detail.clone())

fn first() List[Int]!Error => fail("empty")

fn failed() Int! => fail_cause(failure_error(Failure("domain")))

fn forward[T]() T? => absent()

fn consume(value Int?) Int => value or 0

type Events {
	values List[Int]
}

fn record[T](var events Events, value Int) T? {
	events.values.append(value)
	return null
}

fn combine[T](var events Events, hold first T?, second T?) &T? {
	events.values.append(3)
	return first
}

test "expected generic results preserve behavior and call order" {
	result List[Int]!Error := first()
	expect_false(result.is_ok())?
	expect_equal(result.err().message, "empty")?

	domain := failed()
	expect_false(domain.is_ok())?
	expect_equal(domain.err().message, "domain")?

	empty Int? := forward()
	expect_false(not (empty == null))?

	values List[Int?] := [1, 2].map(item => absent())
	expect_equal(values.length(), 2)?
	expect_false(not (values[0] == null))?

	callback fn(Int) String := transform(item => item.to_string())
	expect_equal(callback(7), "7")?

	defaulted fn(Int) Int := from_callback(() => fn(value Int = 4) => (value + 1))
	expect_equal(defaulted(8), 9)?
	expect_equal(consume(identity(5)), 5)?

	var events = Events([])
	combined Int? := combine(
		events,
		second: record(events, 2),
		first: record(events, 1),
	)
	expect_false(not (combined == null))?
	expect_equal(events.values, [2, 1, 3])?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn fail[T](move message String) T! => error(Error(message))
// expect-formatted:
// expect-formatted: fn fail_cause[T, E](move cause E) T!E => error(cause)
// expect-formatted:
// expect-formatted: fn absent[T]() T? => null
// expect-formatted:
// expect-formatted: fn identity[T](hold value T) &T => value
// expect-formatted:
// expect-formatted: fn from_callback[T](factory fn() T) T => factory()
// expect-formatted:
// expect-formatted: fn transform[T, U](callback fn(T) U) fn(T) U => callback
// expect-formatted:
// expect-formatted: type Failure {
// expect-formatted: \tdetail String
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn failure_error(cause Failure) Error => Error(cause.detail.clone())
// expect-formatted:
// expect-formatted: fn first() List[Int]! => fail("empty")
// expect-formatted:
// expect-formatted: fn failed() Int! => fail_cause(failure_error(Failure("domain")))
// expect-formatted:
// expect-formatted: fn forward[T]() T? => absent()
// expect-formatted:
// expect-formatted: fn consume(value Int?) Int => value or 0
// expect-formatted:
// expect-formatted: type Events {
// expect-formatted: \tvalues List[Int]
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn record[T](var events Events, value Int) T? {
// expect-formatted: \tevents.values.append(value)
// expect-formatted: \treturn null
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn combine[T](var events Events, hold first T?, second T?) &T? {
// expect-formatted: \tevents.values.append(3)
// expect-formatted: \treturn first
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "expected generic results preserve behavior and call order" {
// expect-formatted: \tresult List[Int]! := first()
// expect-formatted: \texpect_false(result.is_ok())?
// expect-formatted: \texpect_equal(result.err().message, "empty")?
// expect-formatted:
// expect-formatted: \tdomain := failed()
// expect-formatted: \texpect_false(domain.is_ok())?
// expect-formatted: \texpect_equal(domain.err().message, "domain")?
// expect-formatted:
// expect-formatted: \tempty Int? := forward()
// expect-formatted: \texpect_false(not (empty == null))?
// expect-formatted:
// expect-formatted: \tvalues List[Int?] := [1, 2].map(item => absent())
// expect-formatted: \texpect_equal(values.length(), 2)?
// expect-formatted: \texpect_false(not (values[0] == null))?
// expect-formatted:
// expect-formatted: \tcallback fn(Int) String := transform(item => item.to_string())
// expect-formatted: \texpect_equal(callback(7), "7")?
// expect-formatted:
// expect-formatted: \tdefaulted fn(Int) Int := from_callback(() => fn(value Int = 4) => (value + 1))
// expect-formatted: \texpect_equal(defaulted(8), 9)?
// expect-formatted: \texpect_equal(consume(identity(5)), 5)?
// expect-formatted:
// expect-formatted: \tvar events = Events([])
// expect-formatted: \tcombined Int? := combine(
// expect-formatted: \t\tevents,
// expect-formatted: \t\tsecond: record(events, 2),
// expect-formatted: \t\tfirst: record(events, 1),
// expect-formatted: \t)
// expect-formatted: \texpect_false(not (combined == null))?
// expect-formatted: \texpect_equal(events.values, [2, 1, 3])?
// expect-formatted: }

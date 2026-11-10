import expect_equal, expect_false from "@std/test/test.ms"

fn apply[T, U](value: T, transform: fn(T) U) U: transform(value)

fn choose[T](first: fn() T, second: fn() T) T: first()

fn optional[T, U](value: T, transform: (fn(T) U)?) U:
	return transform.get()(value)

fn with_result[T](transform: fn() T!Error) T!Error: transform()

type Callback[T, U]:
	transform: fn(T) U

type Failure[T]:
	detail: T

test "callback inference retains captures and contextual metadata":
	offset := 7
	values := [1, 2].map(fn outer: [3, 4].map(fn inner: return outer + inner + offset))
	try expect_equal(values, [[11, 12], [12, 13]])

	callable: fn(Int) fn(Int) Int = apply(
		value: 1, transform: fn base: fn item: fn extra: item + extra + base
	)
	try expect_equal(callable(3)(4), 8)

	callback := Callback(fn(item: Int = 4): item + offset)
	try expect_equal(callback.transform(3), 10)
	try expect_equal(optional(value: 5, transform: fn item: item + offset), 12)

	missing := choose(first: fn: none, second: fn() Int?: 3)
	try expect_false(missing.is_some())

	failure := with_result(
		fn:
			if true: return error(Error("expected"))

			return ok(4)
	)

	try expect_equal(failure, Result[Int, Error].error(Error("expected")))

	failed: Int!Failure[Int] = apply(value: 9, transform: fn item: error(Failure(item)))
	try expect_false(failed.is_ok())
	try expect_equal(failed.err().detail, 9)

fn absent[T]() T?: none

fn from_callback[T](factory: fn() T) T: factory()

test "later returns repair incomplete and convertible evidence":
	value := from_callback(
		fn:
			if true: return absent()

			one: Int? = 1
			return one
	)

	try expect_false(value.is_some())

	cause := from_callback(
		fn:
			if false: return Failure(1)

			return Failure(2)
	)

	try expect_equal(cause.detail, 2)

fn operation() Int!Error: ok(4)

test "try rechecks the inferred enclosing result":
	value := from_callback(
		fn:
			number := try operation()
			return Result[Int, Error].ok(number)
	)

	try expect_equal(value, Result[Int, Error].ok(4))

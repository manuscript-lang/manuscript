// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	expect_contains,
	expect_equal,
	expect_error,
	expect_ok,
	expect_true
) from "@std/test/test.ms"

enum ValidationError:
	BelowMinimum(actual: Int, minimum: Int)

fn checked(value: Int) Int!ValidationError:
	if value < 10: return error(BelowMinimum(value, 10))
	return ok(value)

fn relay[T, E](outcome: T!E) T!E:
	value := outcome?
	return ok(value)

fn actual(cause: ValidationError) Int:
	match cause:
		BelowMinimum(value, _): return value

fn optional_result(value: Int!String?) Int:
	return value.get().get(-1)

test "optional Result arguments supply constructor type context":
	optional_result(ok(4)) | expect_equal(4)?
	optional_result(error("missing")) | expect_equal(-1)?

test "optional failure payloads and nested absence retain their layers":
	absent: Int?? := none
	absent.is_none() | expect_true?

	inner: Int? := none
	present: Int?? := inner
	present.is_some() | expect_true?
	present.get().is_none() | expect_true?

	failure: Result[Int, String?] := error(none)
	failure.is_error() | expect_true?
	failure.err().is_none() | expect_true?

test "named failures propagate without a reporting implementation":
	cause := expect_error(relay(checked(3)))?
	actual(cause) | expect_equal(3)?

	value := expect_ok(relay(checked(12)))?
	value | expect_equal(12)?

test "primitive failures work with contextual constructors and assertion aliases":
	text: Int!String := error("missing")
	message := expect_error(relay(text))?
	message | expect_equal("missing")?

	number: String!Int := error(7)
	code := expect_error(relay(number))?
	code | expect_equal(7)?

	success := expect_ok(Result[Int, String].ok(4))?
	success | expect_equal(4)?

test "Result transforms preserve primitive errors and map to named cases":
	failure: Int!String := error("missing")
	failure.map(fn value: value + 1).err() | expect_equal("missing")?

	var calls = 0

	mapped := failure.map_error(
		fn message:
			calls += 1
			return BelowMinimum(message.length(), 10)
	)

	actual(mapped.err()) | expect_equal(7)?
	calls | expect_equal(1)?

	success: Int!String := ok(4)
	success.map_error(
		fn message:
			calls += 1
			return 9
	).get() | expect_equal(4)?
	calls | expect_equal(1)?

	chained := success.and_then(fn value: Result[String, String].ok(value.to_string()))
	chained.get() | expect_equal("4")?

	recovered := failure.or_else(fn message: Result[Int, String].ok(message.length()))
	recovered.get() | expect_equal(7)?
	failure.get_or_else(fn message: message.length()) | expect_equal(7)?

test "assertion failures can describe values without a reporting implementation":
	expect_ok(checked(3)).err().message | expect_contains("BelowMinimum")?
	(
		expect_ok(Result[Int, String].error("missing")).err().message
		| expect_contains("missing")?
	)
	(
		expect_error(Result[Int, Int].ok(4)).err().message | expect_contains(
			"expected error"
		)?
	)
	(
		expect_error(Result[Int, String].ok(4)).err().message | expect_contains(
			"expected error"
		)?
	)

test "Optional adapters accept primitive errors and remain lazy":
	present: Int? := 4
	missing: Int? := none
	missing.ok_or("absent").err() | expect_equal("absent")?
	present.ok_or(9).get() | expect_equal(4)?

	var calls = 0
	present.ok_or_else(
		fn() Int:
			calls += 1
			return 9
	).get() | expect_equal(4)?
	calls | expect_equal(0)?
	missing.ok_or_else(
		fn() Int:
			calls += 1
			return 9
	).err() | expect_equal(9)?
	calls | expect_equal(1)?

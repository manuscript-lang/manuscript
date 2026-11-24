// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_contains,
	expect_equal,
	expect_error,
	expect_ok,
	expect_true from "@std/test/test.ms",
)

enum ValidationError {
	BelowMinimum(actual Int, minimum Int)
}

fn checked(value Int) Int!ValidationError {
	if value < 10 { return error(BelowMinimum(value, 10)) }
	return ok(value)
}

fn relay[T, E](outcome T!E) T!E {
	value := outcome.clone()?
	return ok(value)
}

fn actual(cause ValidationError) Int {
	match cause {
		BelowMinimum(value, _) => return value
	}
}

fn optional_result(value Int!String?) Int {
	return (value or panic("called Optional.get() on null")).get_or(-1)
}

test "optional Result arguments supply constructor type context" {
	optional_result(ok(4)) | expect_equal(4)?
	optional_result(error("missing")) | expect_equal(-1)?
}

test "optional failure payloads collapse nested absence" {
	absent Int?? := null
	(absent == null) | expect_true?

	inner Int? := null
	present Int?? := inner
	(present == null) | expect_true?

	failure Result[Int, String?] := error(null)
	failure.is_error() | expect_true?
	(failure.err() == null) | expect_true?
}

test "named failures propagate without a reporting implementation" {
	cause := expect_error(relay(checked(3)))?
	actual(cause) | expect_equal(3)?

	value := expect_ok(relay(checked(12)))?
	value | expect_equal(12)?
}

test "primitive failures work with contextual constructors and assertion aliases" {
	text Int!String := error("missing")
	message := expect_error(relay(text))?
	message | expect_equal("missing")?

	number String!Int := error(7)
	code := expect_error(relay(number))?
	code | expect_equal(7)?

	success := expect_ok(Result[Int, String].ok(4))?
	success | expect_equal(4)?
}

test "Result transforms preserve primitive errors and map to named cases" {
	failure Int!String := error("missing")
	failure.clone().map(value => value + 1).err() | expect_equal("missing")?

	var calls = 0

	mapped := failure.clone().map_error(
		message => {
			calls += 1
			return BelowMinimum(message.length(), 10)
		}
	)

	actual(mapped.err()) | expect_equal(7)?
	calls | expect_equal(1)?

	success Int!String := ok(4)
	(
		success.clone().map_error(
			message => {
				calls += 1
				return 9
			}
		).get() | expect_equal(4)?
	)
	calls | expect_equal(1)?

	chained := success.and_then(value => Result[String, String].ok(value.to_string()))
	chained.get() | expect_equal("4")?

	recovered := failure.clone().or_else(
		message => Result[Int, String].ok(message.length())
	)
	recovered.get() | expect_equal(7)?
	failure.get_or_else(message => message.length()) | expect_equal(7)?
}

test "assertion failures can describe values without a reporting implementation" {
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
}

test "Optional adapters accept primitive errors" {
	present Int? := 4
	missing Int? := null
	ok_or(missing, "absent").err() | expect_equal("absent")?
	ok_or(present, 9).get() | expect_equal(4)?
}

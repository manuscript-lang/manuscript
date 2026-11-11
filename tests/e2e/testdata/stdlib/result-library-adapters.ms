import (
	Bytes from "@std/bytes.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
	Duration, parse_duration from "@std/time.ms",
)

enum InputFailure:
	Binary(cause: Error)
	Time(cause: Error)
	MissingPrefix
	MissingKey(value: Int)

fn read_number(data: Bytes) UInt64!InputFailure:
	decoded := data.uvarint(0).map_error(fn cause: InputFailure.Binary(cause.clone()))?
	return ok(decoded.value)

fn read_duration(text: String) Duration!InputFailure:
	return parse_duration(text).map_error(fn cause: InputFailure.Time(cause.clone()))

fn read_prefixed(text: String) String!InputFailure:
	return text.cut_prefix("name=").ok_or(InputFailure.MissingPrefix)

fn sorted_index(values: List[Int], target: Int) Int!InputFailure:
	position := values.binary_search(target)
	if not position.found: return error(InputFailure.MissingKey(target))

	return ok(position.index)

test "library results compose with failure values without a reporting implementation":
	number := expect_ok(read_number(Bytes([172, 2])))?
	expect_equal(number, 300)?
	expect_equal(
		(expect_error(read_number(Bytes([128])))?),
		InputFailure.Binary(Error("binary: incomplete varint", kind: "EBADMSG")),
	)?

	duration := expect_ok(read_duration("1.5us"))?
	expect_equal(duration.to_nanoseconds(), 1500)?
	expect_equal(
		(expect_error(read_duration("invalid"))?),
		InputFailure.Time(Error("time: invalid data", kind: "EBADMSG")),
	)?

test "absence adapters and sorted lookup retain an explicit failure type":
	value := expect_ok(read_prefixed("name=value"))?
	expect_equal(value, "value")?
	expect_equal((expect_error(read_prefixed("missing"))?), InputFailure.MissingPrefix)?
	expect_equal((expect_ok(sorted_index([1, 3, 3], 3))?), 1)?
	expect_equal(
		(expect_error(sorted_index([1, 3, 3], 2))?),
		InputFailure.MissingKey(2),
	)?

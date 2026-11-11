// conform: tags=formatter,modules,parser,stdlib-testing,stdlib-time,testing,tier-io,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/time-methods.ms
import (
	expect_equal, expect_false from "@std/test/test.ms",
	monotonic, nanoseconds, now, parse_timestamp, timestamp from "@std/time.ms",
)

test "duration arithmetic and conversion":
	interval := nanoseconds(1500000000)
	expect_false(
		(
			interval.to_nanoseconds() != 1500000000
			or interval.to_microseconds() != 1500000
			or interval.to_milliseconds() != 1500
		)
	)?
	expect_false(
		(
			interval.to_seconds() != 1.5
			or 90.seconds().to_minutes() != 1.5
			or 90.minutes().to_hours() != 1.5
		)
	)?

	negative := nanoseconds(-1500001)
	expect_false(
		(
			negative.to_microseconds() != -1500
			or negative.to_milliseconds() != -1
		)
	)?
	expect_false(
		(
			interval.add(1.seconds()).subtract(500.milliseconds()).multiply(
				3
			).divide(2) != 3.seconds()
		)
	)?
	expect_false(
		(
			nanoseconds(-7).divide(3) != nanoseconds(-2)
			or interval.negate().abs() != interval
		)
	)?
	expect_false(
		(
			interval.compare(2.seconds()) != -1
			or interval.compare(interval) != 0
			or interval.compare(1.seconds()) != 1
		)
	)?

	convert := interval.to_seconds
	expect_equal(convert(), 1.5)?

test "monotonic instant methods":
	start := monotonic()
	later := start.shift(2.seconds())
	expect_false(
		(
			later.difference(start) != 2.seconds()
			or start.difference(later) != nanoseconds((-2000000000))
		)
	)?
	expect_false(
		(
			start.compare(later) != -1
			or later.compare(start) != 1
			or start.compare(start) != 0
		)
	)?
	expect_equal(later.shift(nanoseconds(-2000000000)), start)?

test "timestamp methods and expected range failures":
	value := timestamp(-1, 500000000)?
	expect_false(
		(
			value.unix_seconds() != -1
			or value.nanoseconds() != 500000000
			or value.to_string() != "1969-12-31T23:59:59.5Z"
		)
	)?

	later := value.shift(1500.milliseconds())?
	expect_false(
		(
			later.unix_seconds() != 1
			or later.nanoseconds() != 0
			or later.compare(value) != 1
			or value.compare(later) != -1
		)
	)?

	delta := later.difference(value)?
	expect_equal(delta, 1500.milliseconds())?

	parsed := parse_timestamp("2026-10-12T01:00:00+01:00")?
	expect_false(
		(
			parsed.to_string() != "2026-10-12T00:00:00Z"
			or parsed.compare(parsed) != 0
		)
	)?

	maximum := timestamp(253402300799, 999999999)?
	shifted := maximum.shift(nanoseconds(1))
	expect_false(shifted.is_ok())?
	expect_equal(shifted.err(), Error("time: value out of range", kind: "ERANGE"))?

	minimum := timestamp(-62135596800, 0)?
	difference := maximum.difference(minimum)
	expect_false(difference.is_ok())?
	expect_equal(difference.err(), Error("time: value out of range", kind: "ERANGE"))?
	expect_equal(maximum.compare(minimum), 1)?

	now := now()
	roundtrip := parse_timestamp(now.to_string())?
	expect_equal(roundtrip, now)?

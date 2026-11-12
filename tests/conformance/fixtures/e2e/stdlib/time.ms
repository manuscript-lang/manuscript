// conform: tags=testing,tier-io
// conform: phase=test
import (
	expect_equal, expect_false, expect_true, fail from "@std/test/test.ms",
	Timestamp,
	from_calendar,
	local_zone,
	microseconds,
	milliseconds,
	monotonic,
	nanoseconds,
	now,
	parse_timestamp,
	sleep,
	timestamp from "@std/time.ms",
)

test "timestamps preserve nanoseconds and shift across epoch":
	epoch := timestamp(0, 123)?
	expect_false(epoch.unix_seconds() != 0 or epoch.nanoseconds() != 123)?
	expect_equal((parse_timestamp(epoch.to_string())?), epoch)?

	later := epoch.shift(2.seconds())?
	expect_equal((later.difference(epoch)?), 2.seconds())?
	expect_equal((later.shift((-2).seconds())?), epoch)?

test "time rejects invalid timestamps and out of range nanoseconds":
	invalid: Timestamp! := error(Error("time: invalid data", kind: "EBADMSG"))
	expect_equal(parse_timestamp("2024-02-30T00:00:00Z"), invalid)?

	out_of_range: Timestamp! := error(Error("time: value out of range", kind: "ERANGE"))
	expect_equal(timestamp(0, 1000000000), out_of_range)?

test "timestamp shifts normalize raw fields and preserve wide sums":
	minimum := -9223372036854775807 - 1
	maximum := 9223372036854775807
	expect_equal(
		(Timestamp(-62135596801, 1000000000).shift(nanoseconds(0))?),
		Timestamp(-62135596800, 0),
	)?
	expect_equal(
		(Timestamp(253402300800, 0).shift(nanoseconds(-1000000000))?),
		Timestamp(253402300799, 0),
	)?
	expect_equal((Timestamp(0, -1).shift(nanoseconds(0))?), Timestamp(-1, 999999999))?
	expect_equal(
		(Timestamp(0, maximum).shift(nanoseconds(maximum))?),
		Timestamp(18446744073, 709551614),
	)?
	expect_equal(
		(Timestamp(0, minimum).shift(nanoseconds(minimum))?),
		Timestamp(-18446744074, 290448384),
	)?
	expect_equal(
		(Timestamp(0, maximum).shift(nanoseconds(minimum))?),
		Timestamp(-1, 999999999),
	)?

	out_of_range: Timestamp! := error(Error("time: value out of range", kind: "ERANGE"))
	expect_equal(Timestamp(maximum, 0).shift(nanoseconds(maximum)), out_of_range)?
	expect_equal(Timestamp(minimum, 0).shift(nanoseconds(minimum)), out_of_range)?

test "host clocks are usable and zero sleep completes":
	before := monotonic()
	_ := sleep(0.milliseconds()).wait()
	expect_false(monotonic() < before)?

	current := now()
	expect_equal((parse_timestamp(current.to_string())?), current)?

test "parse_timestamp reports offsets that leave years 1 through 9999 as out of range":
	out_of_range: Timestamp! := error(Error("time: value out of range", kind: "ERANGE"))
	for text in ["0001-01-01T00:00:00+00:01", "9999-12-31T23:59:59-00:01"]:
		if parse_timestamp(text) != out_of_range: return fail("range {text}")

test "calendar fields follow the requested zone":
	moment := parse_timestamp("2024-03-10T12:30:15.250Z")?
	utc := moment.calendar("UTC")?
	expect_equal(utc.year, 2024)?
	expect_equal(utc.month, 3)?
	expect_equal(utc.day, 10)?
	expect_equal(utc.weekday, 0)?
	expect_equal(utc.day_of_year, 70)?
	expect_equal(utc.nanosecond, 250000000)?

	ny := moment.calendar("America/New_York")?
	expect_equal(ny.hour, 8)?
	expect_equal(ny.offset_seconds, -14400)?

	fixed := moment.calendar("+05:30")?
	expect_equal(fixed.hour, 18)?
	expect_equal(fixed.minute, 0)?

test "format renders tokens and from_calendar round trips":
	moment := parse_timestamp("2024-03-10T12:30:15.250Z")?
	expect_equal(
		(moment.format("YYYY-MM-DD HH:mm:ss.SSS ZZ", "+05:30")?),
		"2024-03-10 18:00:15.250 +05:30",
	)?

	back := from_calendar(2024, 3, 10, 8, 30, 15, 250000000, "America/New_York")?
	expect_equal(back, moment)?

test "format preserves Unicode literals and empty patterns across calendar edges":
	moment := parse_timestamp("2024-02-29T23:59:59.123456789Z")?
	expect_equal((moment.format("", "UTC")?), "")?
	expect_equal((moment.format("日本語 🗓", "UTC")?), "日本語 🗓")?
	expect_equal(
		(moment.format("YYYY年MM月DD日 HH:mm:ss zone 🗓", "America/New_York")?),
		"2024年02月29日 18:59:59 EST 🗓",
	)?
	first := parse_timestamp("0001-01-01T00:00:00Z")?
	last := parse_timestamp("9999-12-31T23:59:59Z")?
	expect_equal((first.format("YYYY-MM-DD", "-23:59")?), "0000-12-31")?
	expect_equal((last.format("YYYY-MM-DD", "+23:59")?), "10000-01-01")?
	invalid: String! := error(Error("time: invalid input", kind: "EINVAL"))
	expect_equal(moment.format("", "Nowhere/Land"), invalid)?

test "calendar rejects unknown zones and impossible dates":
	bad_zone: Timestamp! := error(Error("time: invalid input", kind: "EINVAL"))
	expect_equal(from_calendar(2024, 1, 1, 0, 0, 0, 0, "Nowhere/Land"), bad_zone)?

	bad_date: Timestamp! := error(Error("time: value out of range", kind: "ERANGE"))
	expect_equal(from_calendar(2023, 2, 29, 0, 0, 0, 0, "UTC"), bad_date)?
	expect_false(local_zone() == "")?

test "sub-millisecond sleeps are not rounded up to a millisecond":
	var fastest = milliseconds(5000)

	// Rounding each sleep up to 1 ms would take at least 500 ms; 50 us sleeps take
	// about 25 ms. A loaded or coarse-timer runner can stretch one pass, so the fastest
	// of a few passes decides.
	for attempt in 0..5:
		start := monotonic()
		for round in 0..500:
			_ := sleep(microseconds(50)).wait()

		elapsed := monotonic().difference(start)
		if elapsed.compare(fastest) < 0:
			fastest = elapsed

	expect_true(fastest.compare(milliseconds(400)) < 0)?

test "timestamp parsing preserves maximum-width precision and offsets":
	for text in [
		"2024-02-29T12:30:45.123456789Z", "2024-02-29T12:30:45.123456789+23:59",
		"2024-02-29T12:30:45.123456789-23:59"
	]:
		parsed := parse_timestamp(text)?
		expect_equal(parsed.nanoseconds(), 123456789)?
		expect_equal((parse_timestamp(parsed.to_string())?), parsed)?

	out_of_range: Timestamp! := error(Error("time: value out of range", kind: "ERANGE"))
	expect_equal(parse_timestamp("0001-01-01T00:00:00.123456789+00:01"), out_of_range)?
	expect_equal(parse_timestamp("9999-12-31T23:59:59.123456789-00:01"), out_of_range)?

test "timestamp parsing rejects oversized fractions and suffixes":
	invalid: Timestamp! := error(Error("time: invalid data", kind: "EBADMSG"))
	for text in [
		"2024-02-29T12:30:45.1234567890Z",
		"2024-02-29T12:30:45.1234567890+00:00",
		"2024-02-29T12:30:45.123456789+00:00Z",
		"2024-02-29T12:30:45.123456789+00:000",
		"2024-02-29T12:30:45." + "0".repeat(1048576).get() + "Z",
	]:
		expect_equal(parse_timestamp(text), invalid)?

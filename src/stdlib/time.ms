import (
	Promise, adopt from "@std/concurrency/promise.ms",
	Data, panic from "@std/core.ms",
	JsonValue from "@std/data/json.ms",
	ReadStream, Source from "@std/io/io.ms",

	msrt_promise_sleep from "@std/internal/promises.ms",
	msstd_time_clock_now,
	msstd_time_duration_abs,
	msstd_time_duration_add,
	msstd_time_duration_divide,
	msstd_time_duration_multiply,
	msstd_time_duration_negate,
	msstd_time_duration_subtract,
	msstd_time_duration_to_hours,
	msstd_time_duration_to_microseconds,
	msstd_time_duration_to_milliseconds,
	msstd_time_duration_to_minutes,
	msstd_time_duration_to_seconds,
	msstd_time_from_local,
	msstd_time_instant_compare,
	msstd_time_instant_difference,
	msstd_time_instant_shift,
	msstd_time_local_from_calendar,
	msstd_time_parse_timestamp,
	msstd_time_timestamp_calendar,
	msstd_time_timestamp_format,
	msstd_time_timestamp_to_string,
	msstd_time_wall_clock_now from "@std/internal/time.ms",
	load, local_name from "@std/internal/zone.ms",
)

// A span of elapsed time, counted in signed nanoseconds.
export type Duration {
	// The signed count of nanoseconds; `nanoseconds(n)` and the unit constructors build
	// one.
	nanos Int
}

// Writes the signed nanoseconds as a JSON integer.
fn Duration.to_json() JsonValue {
	return JsonValue.NumberValue(f"{self.nanos}")
}

// Adds signed nanoseconds; a result outside Duration's representable range faults.
fn Duration.add(other Duration) Duration {
	return Duration(nanos: msstd_time_duration_add(self.nanos, other.nanos))
}

// Subtracts signed nanoseconds; a result outside Duration's representable range
// faults.
fn Duration.subtract(other Duration) Duration {
	return Duration(nanos: msstd_time_duration_subtract(self.nanos, other.nanos))
}

// Multiplies by an integer factor; overflow faults.
fn Duration.multiply(factor Int) Duration {
	return Duration(nanos: msstd_time_duration_multiply(self.nanos, factor))
}

// Divides by a nonzero integer, truncating toward zero; zero faults.
fn Duration.divide(divisor Int) Duration {
	return Duration(nanos: msstd_time_duration_divide(self.nanos, divisor))
}

// Negates this duration; the minimum Duration faults.
fn Duration.negate() Duration {
	return Duration(nanos: msstd_time_duration_negate(self.nanos))
}

// Returns the absolute value; the minimum Duration faults.
fn Duration.abs() Duration {
	return Duration(nanos: msstd_time_duration_abs(self.nanos))
}

// Returns -1 when this duration is shorter than `other`, 0 when equal and 1 when
// longer.
fn Duration.compare(other Duration) Int {
	if self.nanos < other.nanos { return -1 }
	if self.nanos > other.nanos { return 1 }

	return 0
}

// Returns the lesser of this value and `other`, or this value when they compare
// equal.
fn Duration.min(other Duration) Duration {
	if other.compare(self) < 0 { return other }
	return self
}

// Returns the greater of this value and `other`, or this value when they compare
// equal.
fn Duration.max(other Duration) Duration {
	if other.compare(self) > 0 { return other }
	return self
}

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault.
fn Duration.clamp(low Duration, high Duration) Duration {
	if low.compare(high) > 0 {
		panic("clamp: low must not be greater than high")
	}
	if self.compare(
		low
	) < 0 { return low }
	if self.compare(high) > 0 { return high }

	return self
}

// Converts this duration to an integer number of nanoseconds.
fn Duration.to_nanoseconds() Int {
	return self.nanos
}

// Converts this duration to an integer number of microseconds.
fn Duration.to_microseconds() Int {
	return msstd_time_duration_to_microseconds(self.nanos)
}

// Converts this duration to an integer number of milliseconds.
fn Duration.to_milliseconds() Int {
	return msstd_time_duration_to_milliseconds(self.nanos)
}

// Returns human text such as `1m30.5s`, `250ms`, `1.5µs`, `-2h0m0s`, or `0s`; string
// interpolation uses it too. A larger unit is followed by every smaller whole
// unit down to seconds, so two minutes is `2m0s` and an exact hour is `1h0m0s`.
fn Duration.to_string() String {
	total := self.to_nanoseconds()
	if total == 0 { return "0s" }

	// Work on magnitudes of the truncated parts so the minimum Duration, which has
	// no positive counterpart, formats too.
	step := if total < 0 { - 1 } else { 1 }
	sign := if total < 0 { "-" } else { "" }
	whole := total / 1000000000 * step
	sub := total % 1000000000 * step
	if whole == 0 and sub < 1000 { return f"{sign}{sub}ns" }
	if whole == 0 and sub < 1000000 {
		return f"{sign}{duration_decimal(sub / 1000, sub % 1000, 3)}µs"
	}
	if whole == 0 { return f"{sign}{duration_decimal(sub / 1000000, sub % 1000000, 6)}ms" }

	hours := whole / 3600
	minutes := whole % 3600 / 60
	clock := if hours == 0 { "" } else { f"{hours}h" }
	minute_part := if hours == 0 and minutes == 0 { "" } else { f"{minutes}m" }
	seconds_part := duration_decimal(whole % 60, sub, 9)
	return f"{sign}{clock}{minute_part}{seconds_part}s"
}

// Converts this duration to floating-point seconds.
fn Duration.to_seconds() Float {
	return msstd_time_duration_to_seconds(self.nanos)
}

// Converts this duration to floating-point minutes.
fn Duration.to_minutes() Float {
	return msstd_time_duration_to_minutes(self.nanos)
}

// Converts this duration to floating-point hours.
fn Duration.to_hours() Float {
	return msstd_time_duration_to_hours(self.nanos)
}

// An instant on a monotonic clock; it is not a calendar timestamp.
export type Instant {
	// The clock the reading belongs to; instants from different domains do not compare.
	domain Int
	// Nanoseconds on that clock.
	tick Int
}

// Shifts this monotonic instant by a duration.
fn Instant.shift(duration Duration) Instant {
	return msstd_time_instant_shift(self, duration.nanos)
}

// Returns this instant minus `other`: the time elapsed since `other`, negative when
// `other` is later.
fn Instant.difference(other Instant) Duration {
	return Duration(nanos: msstd_time_instant_difference(self, other))
}

// Returns -1 when this instant is earlier than `other`, 0 when equal and 1 when
// later. Instants from different clock domains fault.
fn Instant.compare(other Instant) Int {
	return msstd_time_instant_compare(self, other)
}

// Returns the lesser of this value and `other`, or this value when they compare
// equal.
fn Instant.min(other Instant) Instant {
	if other.compare(self) < 0 { return other }
	return self
}

// Returns the greater of this value and `other`, or this value when they compare
// equal.
fn Instant.max(other Instant) Instant {
	if other.compare(self) > 0 { return other }
	return self
}

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault.
fn Instant.clamp(low Instant, high Instant) Instant {
	if low.compare(high) > 0 {
		panic("clamp: low must not be greater than high")
	}
	if self.compare(
		low
	) < 0 { return low }
	if self.compare(high) > 0 { return high }

	return self
}

fn out_of_range() Error {
	return Error("time: value out of range", kind: "ERANGE")
}

// Whole seconds and a nanosecond remainder of a nanosecond count, which may lie
// outside 0 through 999999999 because Timestamp's fields are public.
type Split {
	whole Int
	rest Int
}

// Splits nanos so the remainder is in 0 through 999999999 and nothing overflows.
fn floor_split(nanos Int) Split {
	if nanos >= 0 and nanos < 1000000000 { return Split(0, nanos) }

	whole := nanos / 1000000000
	rest := nanos % 1000000000
	if rest < 0 { return Split(whole - 1, rest + 1000000000) }

	return Split(whole, rest)
}

// The duration whole * 1e9 + rest, or ERANGE when it does not fit an Int. The bounds
// are the Int range, -9223372036854775808 through 9223372036854775807, in seconds
// and nanoseconds.
fn duration_of(whole Int, rest Int) Duration! {
	// Align the signs so the two parts count the same way.
	var w = whole
	var r = rest

	if w > 0 and r < 0 {
		w -= 1
		r += 1000000000
	}

	if w < 0 and r > 0 {
		w += 1
		r -= 1000000000
	}

	if w > 9223372036 or w < -9223372036 { return error(out_of_range()) }
	if w == 9223372036 and r > 854775807 { return error(out_of_range()) }
	if w == -9223372036 and r < -854775808 { return error(out_of_range()) }

	return ok(Duration(nanos: w * 1000000000 + r))
}

// A wall-clock time with Unix seconds and nanoseconds.
export type Timestamp {
	// Whole seconds since the Unix epoch.
	seconds Int
	// The nanosecond within the second, 0 through 999999999.
	nanos Int
}

// Formats this timestamp in RFC 3339 form.
fn Timestamp.to_string() String {
	return msstd_time_timestamp_to_string(self)
}

// Writes the RFC 3339 text as a JSON string.
fn Timestamp.to_json() JsonValue {
	return JsonValue.StringValue(self.to_string())
}

// Returns the whole Unix seconds represented by this timestamp.
fn Timestamp.unix_seconds() Int {
	return self.seconds
}

// Returns this timestamp's nanosecond component.
fn Timestamp.nanoseconds() Int {
	return self.nanos
}

// Adds a duration to this wall-clock timestamp. A result outside years 1 through
// 9999 returns `ERANGE`.
fn Timestamp.shift(duration Duration) Timestamp! {
	// A start beyond this can never land in the calendar range: the carry below is at
	// most about 2e10 seconds. It also keeps the sum from overflowing.
	if self.seconds > 300000000000 or self.seconds < -300000000000 {
		return error(out_of_range())
	}

	// Fields built by this module are already normalized; only raw ones need a split.
	var carry = duration.nanos / 1000000000
	var nanos = self.nanos

	if nanos < 0 or nanos >= 1000000000 {
		left := floor_split(nanos)
		carry += left.whole
		nanos = left.rest
	}

	nanos += duration.nanos % 1000000000

	// The remainders sum to between -999999999 and 1999999998.
	if nanos < 0 {
		nanos += 1000000000
		carry -= 1
	} else if nanos >= 1000000000 {
		nanos -= 1000000000
		carry += 1
	}

	seconds := self.seconds + carry
	if seconds > 253402300799 or seconds < -62135596800 { return error(out_of_range()) }

	return ok(Timestamp(seconds: seconds, nanos: nanos))
}

// Returns this timestamp minus `other` as a duration. A result that does not fit a
// Duration returns `ERANGE`.
fn Timestamp.difference(other Timestamp) Duration! {
	// Normalized fields of nearby timestamps: the subtraction and product cannot
	// overflow.
	if (
		self.nanos >= 0
		and self.nanos < 1000000000
		and other.nanos >= 0
		and other.nanos < 1000000000
	) {
		if (
			self.seconds < 4000000000000
			and self.seconds > -4000000000000
			and other.seconds < 4000000000000
			and other.seconds > -4000000000000
		) {
			close := self.seconds - other.seconds
			if close > -9000000000 and close < 9000000000 {
				return ok(
					Duration(
						nanos: close * 1000000000 + self.nanos - other.nanos
					)
				)
			}
		}
	}

	// Seconds of opposite sign can overflow when subtracted; the result would be far
	// outside a Duration anyway.
	if (
		self.seconds >= 0
		and other.seconds < 0
		and self.seconds > 9223372036854775807 + other.seconds
	) {
		return error(out_of_range())
	}
	if (
		self.seconds < 0
		and other.seconds > 0
		and self.seconds < -9223372036854775807 + other.seconds - 1
	) {
		return error(out_of_range())
	}

	sd := self.seconds - other.seconds
	if sd > 100000000000 or sd < -100000000000 { return error(out_of_range()) }

	left := floor_split(self.nanos)
	right := floor_split(other.nanos)
	return duration_of(sd + left.whole - right.whole, left.rest - right.rest)
}

// Returns -1 when this timestamp is earlier than `other`, 0 when equal and 1 when
// later, across the full calendar range.
fn Timestamp.compare(other Timestamp) Int {
	if self.seconds != other.seconds { return if self.seconds > other.seconds { 1 } else { - 1 } }
	if self.nanos != other.nanos { return if self.nanos > other.nanos { 1 } else { - 1 } }

	return 0
}

// Returns the lesser of this value and `other`, or this value when they compare
// equal.
fn Timestamp.min(other Timestamp) Timestamp {
	if other.compare(self) < 0 { return other }
	return self
}

// Returns the greater of this value and `other`, or this value when they compare
// equal.
fn Timestamp.max(other Timestamp) Timestamp {
	if other.compare(self) > 0 { return other }
	return self
}

// Returns this value limited to `low` through `high`; `low` greater than `high` is
// a programming fault.
fn Timestamp.clamp(low Timestamp, high Timestamp) Timestamp {
	if low.compare(high) > 0 {
		panic("clamp: low must not be greater than high")
	}
	if self.compare(
		low
	) < 0 { return low }
	if self.compare(high) > 0 { return high }

	return self
}

// Breaks this timestamp into calendar fields in a time zone: `"UTC"`, `"Local"`, an
// IANA name such as `"America/New_York"`, or a fixed offset such as `"+05:30"`. An
// unknown zone returns `EINVAL`.
fn Timestamp.calendar(zone String) Date! {
	resolved := load(zone)?
	at := resolved.at(self.seconds)
	return ok(msstd_time_timestamp_calendar(self, at.offset, at.abbreviation))
}

/*
Formats this timestamp in a zone with a token pattern.
The tokens are `YYYY`, `MM`, `DD`, `HH`, `mm`, `ss`, `SSS` (milliseconds), `ZZ` (offset such as `+05:30`) and `zone` (abbreviation). Other text is copied.
Tokens are replaced wherever they appear, even inside words (`"Dummy"` becomes `"Du13y"`), and there is no escape.
To include literal letters that spell a token, format the fields separately and join the pieces yourself.
An unknown zone returns `EINVAL`.
*/
fn Timestamp.format(pattern String, zone String) String! {
	resolved := load(zone)?
	at := resolved.at(self.seconds)
	return ok(msstd_time_timestamp_format(self, pattern, at.offset, at.abbreviation))
}

// Date and time fields of a timestamp in one time zone.
export type Date {
	// The year, 1 through 9999 in UTC and nearby values in other zones.
	year Int
	// The month, 1 (January) through 12.
	month Int
	// The day of the month, starting at 1.
	day Int
	// The hour, 0 through 23.
	hour Int
	// The minute, 0 through 59.
	minute Int
	// The second, 0 through 59.
	second Int
	// The nanosecond within the second, 0 through 999999999.
	nanosecond Int
	// The day of the week, 0 (Sunday) through 6 (Saturday).
	weekday Int
	// The day of the year, starting at 1.
	day_of_year Int
	// The zone's offset from UTC in seconds at this moment; positive is east.
	offset_seconds Int
	// The zone abbreviation at this moment, such as `UTC` or `EST`.
	zone String
}

// Writes `whole` with the digits of a fractional part `frac` of `width` places,
// trailing zeros dropped.
fn duration_decimal(whole Int, frac Int, width Int) String {
	if frac == 0 { return f"{whole}" }

	var rest = frac
	var places = width

	while rest % 10 == 0 {
		rest /= 10
		places -= 1
	}

	var digits = ""

	while places > 0 {
		digits = f"{rest % 10}{digits}"
		rest /= 10
		places -= 1
	}

	return f"{whole}.{digits}"
}

// Constructs a duration of `n` nanoseconds, the unit `Duration` counts in; `n` may be
// negative.
export fn nanoseconds(n Int) Duration {
	return Duration(nanos: n)
}

// Constructs a duration of `n` microseconds; `n` may be negative, and a nanosecond
// count outside Int faults like any Int multiplication.
export fn microseconds(n Int) Duration {
	return nanoseconds(n * 1000)
}

// Constructs a duration of `n` milliseconds; `n` may be negative, and a nanosecond
// count outside Int faults like any Int multiplication.
export fn milliseconds(n Int) Duration {
	return nanoseconds(n * 1000000)
}

// Constructs a duration of `n` seconds, as in `sleep(seconds(2))`; `n` may be negative,
// and a nanosecond count outside Int faults like any Int multiplication.
export fn seconds(n Int) Duration {
	return nanoseconds(n * 1000000000)
}

// Constructs a duration of `n` minutes; `n` may be negative, and a nanosecond count
// outside Int faults like any Int multiplication. For example,
// `monotonic().difference(start).compare(minutes(5)) > 0` tests whether more than
// five minutes have elapsed.
export fn minutes(n Int) Duration {
	return nanoseconds(n * 60000000000)
}

// Constructs a duration of `n` hours; `n` may be negative, and a nanosecond count
// outside Int faults like any Int multiplication.
export fn hours(n Int) Duration {
	return nanoseconds(n * 3600000000000)
}

/*
Parses a span such as `1h30m`, `-250ms` or `1.5µs`, including every `Duration.to_string()` result.
Accepts one optional leading `+` or `-`, then decimal components with the units `ns`, `us`, `µs`, `μs`, `ms`, `s`, `m` or `h`.
Components may repeat or appear in any order; `.5s` and `1.s` are valid. A bare `0` is also valid, including `+0` and `-0`.
Fractions may have any number of ASCII digits. Each component truncates toward zero to whole nanoseconds, without floating-point rounding, and negative zero becomes zero.
Whitespace, exponents, missing units and other syntax return `EBADMSG`, even after an overflowing prefix.
A well-formed span outside -9223372036854775808 through 9223372036854775807 nanoseconds returns `ERANGE`.
*/
export fn parse_duration(text String) Duration! {
	data := text.to_bytes()
	size := data.length()
	if size == 0 { return error(Error("time: invalid data", kind: "EBADMSG")) }

	var pos = 0
	negative := data.get(0).to_int() == 45
	if negative or data.get(
		0
	).to_int() == 43 { pos += 1 }
	if pos == size { return error(Error("time: invalid data", kind: "EBADMSG")) }
	if size - pos == 1 and data.get(pos).to_int() == 48 { return ok(nanoseconds(0)) }

	// Accumulate negatively: the minimum Duration has no positive counterpart.
	limit := if negative { - 9223372036854775807 - 1 } else { - 9223372036854775807 }
	var total = 0
	var overflow = false

	while pos < size {
		start := pos
		var whole = 0

		while pos < size {
			digit := data.get(pos).to_int() - 48
			if digit < 0 or digit > 9 { break }

			if not overflow {
				if (
					whole < -922337203685477580
					or (whole == -922337203685477580 and digit > 8)
				) {
					overflow = true
				} else {
					whole = whole * 10 - digit
				}
			}

			pos += 1
		}

		has_whole := pos > start
		var fraction_start = pos

		if pos < size and data.get(pos).to_int() == 46 {
			pos += 1
			fraction_start = pos

			while pos < size {
				digit := data.get(pos).to_int() - 48
				if digit < 0 or digit > 9 { break }

				pos += 1
			}
		}

		fraction_end := pos
		if not has_whole and fraction_start == fraction_end {
			return error(Error("time: invalid data", kind: "EBADMSG"))
		}
		if pos == size { return error(Error("time: invalid data", kind: "EBADMSG")) }

		var scale = 0
		suffix := data.get(pos).to_int()
		pos += 1

		if suffix == 104 {
			scale = 3600000000000
		} else if suffix == 115 {
			scale = 1000000000
		} else if suffix == 109 {
			scale = 60000000000

			if pos < size and data.get(pos).to_int() == 115 {
				scale = 1000000
				pos += 1
			}
		} else if suffix == 110 or suffix == 117 {
			if pos == size or data.get(pos).to_int() != 115 {
				return error(Error("time: invalid data", kind: "EBADMSG"))
			}

			scale = if suffix == 110 { 1 } else { 1000 }
			pos += 1
		} else if suffix == 194 or suffix == 206 {
			second := if suffix == 194 { 181 } else { 188 }
			if (
				size - pos < 2
				or data.get(pos).to_int() != second
				or data.get(pos + 1).to_int() != 115
			) {
				return error(Error("time: invalid data", kind: "EBADMSG"))
			}

			scale = 1000
			pos += 2
		} else {
			return error(Error("time: invalid data", kind: "EBADMSG"))
		}

		// Continue syntax validation after overflow, but skip further arithmetic.
		if overflow { continue }

		if whole < limit / scale {
			overflow = true
			continue
		}

		integral := whole * scale

		if total < limit - integral {
			overflow = true
			continue
		}

		total += integral

		// Reverse decimal evaluation gives floor(fraction * scale) exactly for
		// arbitrarily many digits. Each intermediate is less than 10 * scale.
		var fraction = 0
		var cursor = fraction_end

		while cursor > fraction_start {
			cursor -= 1
			fraction = ((data.get(cursor).to_int() - 48) * scale + fraction) / 10
		}

		if total < limit + fraction {
			overflow = true
		} else {
			total -= fraction
		}
	}

	if overflow { return error(Error("time: value out of range", kind: "ERANGE")) }

	return ok(nanoseconds(if negative { total } else { - total }))
}

// Parses an RFC 3339 timestamp with an explicit time zone.
export fn parse_timestamp(text String) Timestamp! {
	return msstd_time_parse_timestamp(text)
}

/*
Builds a timestamp from calendar fields interpreted in a time zone (see `Timestamp.calendar` for zone names).
Fields outside their calendar range, such as month 13 or February 30, return `ERANGE`; an unknown zone returns `EINVAL`.
A local time skipped or repeated by a daylight-saving change resolves to the earlier valid offset.
*/
export fn from_calendar(
	year Int,
	month Int,
	day Int,
	hour Int,
	minute Int,
	second Int,
	nanosecond Int,
	zone String,
) Timestamp! {
	resolved := load(zone)?
	local := msstd_time_local_from_calendar(
		year,
		month,
		day,
		hour,
		minute,
		second,
		nanosecond,
	)?
	return msstd_time_from_local(local, nanosecond, resolved.offset_for_local(local))
}

// Returns the host's local time zone name, or `UTC` when it cannot be determined.
// ms: effect std.system.read
export fn local_zone() String {
	return local_name()
}

// Starts a timer for the requested duration and returns its promise; `wait()` it to
// pause the current task for at least that long. The timer has no task of its own, and
// dropping the promise cancels it.
// ms: effect std.clock.sleep
export fn sleep(duration Duration) Promise[Void] {
	return adopt[Void](msrt_promise_sleep(duration.nanos))
}

// Constructs a timestamp from Unix seconds and the nanosecond within that second.
// `nanoseconds` must be 0 through 999999999, and `seconds` from -62135596800 (year 1)
// through 253402300799 (year 9999); anything else returns `ERANGE`. It does not carry
// extra nanoseconds into the seconds.
export fn timestamp(seconds Int, nanoseconds Int) Timestamp! {
	if nanoseconds < 0 or nanoseconds >= 1000000000 {
		return error(Error("time: value out of range", kind: "ERANGE"))
	}
	if seconds < -62135596800 or seconds > 253402300799 {
		return error(Error("time: value out of range", kind: "ERANGE"))
	}

	return ok(Timestamp(seconds: seconds, nanos: nanoseconds))
}

// Returns the current reading of the monotonic clock, for measuring elapsed time.
// Readings are only comparable with others from this clock and do not correspond to a
// calendar date.
// ms: effect std.clock.read
export fn monotonic() Instant {
	return msstd_time_clock_now()
}

// Returns the current calendar time as a UTC Timestamp with nanosecond precision.
// It can jump when the system clock is adjusted, so use `monotonic` for elapsed time.
// ms: effect std.clock.read
export fn now() Timestamp {
	return msstd_time_wall_clock_now()
}

// A point on the monotonic clock to wait for or check against, such as the end of a
// request's time budget.
export type Deadline {
	// The instant the deadline expires.
	at Instant
}

// Returns the time left, or zero once the deadline has passed.
fn Deadline.remaining() Duration {
	return self.at.difference(monotonic()).max(nanoseconds(0))
}

// Reports whether the deadline has passed.
fn Deadline.expired() Bool {
	return self.at.compare(monotonic()) <= 0
}

// Suspends the current task until the deadline passes. Returns at once if it
// already has.
fn Deadline.wait() Void {
	void sleep(self.remaining()).wait()
}

// Returns a deadline `duration` from now.
// ms: effect std.clock.read
export fn deadline_after(duration Duration) Deadline {
	return Deadline(at: monotonic().shift(duration))
}

/*
A source of evenly spaced instants, for loops that run work on a schedule.
Each read suspends the task until the next tick; stop by dropping the stream. Ticks do not drift
with the loop body: a body slower than the period gets the next tick at once, and the ticks it missed are dropped.
*/
type TickSource {
	// The time between ticks.
	period Duration
	// The instant of the next tick.
	due Instant
}

// Waits for the next tick and returns the instant it was due; never ends.
fn var TickSource.next() Instant?! {
	tick := self.due.clone()
	sleep(tick.difference(monotonic()).max(nanoseconds(0))).wait()?

	current := monotonic()
	period := self.period.to_nanoseconds()
	elapsed := current.difference(tick).to_nanoseconds()

	// Drop missed ticks, retaining the original phase without multiplying a tick
	// count.
	self.due = current.shift(nanoseconds(period - elapsed % period))
	return ok(tick)
}

fn move TickSource.close() Void! {
	return ok()
}

// Returns a ticker whose first tick comes one `period` from now. A period of zero or
// less is a programming fault.
// ms: effect std.clock.sleep
export fn ticker(period Duration) ReadStream[Instant] {
	if period.compare(nanoseconds(0)) <= 0 {
		panic("ticker: period must be positive")
	}

	due := monotonic().shift(period.clone())
	return ReadStream[Instant](TickSource(period: period.clone(), due: due))
}

// `n.milliseconds()`, `n.seconds()` and `n.minutes()` are the constructors above on the
// receiver. A count whose nanoseconds do not fit in Int faults and names the range.
fn unit_count(operation String, n Int, scale Int) Int {
	low := (-9223372036854775807 - 1) / scale
	high := 9223372036854775807 / scale
	if n < low or n > high {
		panic(f"{operation}: value must be between {low} and {high}, found {n}")
	}
	return n
}

// Returns a Duration of this many milliseconds; a count that overflows nanoseconds
// faults.
fn Int.milliseconds() Duration {
	return milliseconds(unit_count("Int.milliseconds", self, 1000000))
}

// Returns a Duration of this many seconds; a count that overflows nanoseconds faults.
fn Int.seconds() Duration {
	return seconds(unit_count("Int.seconds", self, 1000000000))
}

// Returns a Duration of this many minutes; a count that overflows nanoseconds faults.
fn Int.minutes() Duration {
	return minutes(unit_count("Int.minutes", self, 60000000000))
}

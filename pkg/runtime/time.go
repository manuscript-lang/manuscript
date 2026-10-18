package msruntime

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Duration is a signed count of nanoseconds.
type Duration int64

// ClockDomain identifies the monotonic clock an Instant was read from, so
// instants of different clocks do not compare.
type ClockDomain struct{ _ byte }

// Instant is a monotonic clock reading.
type Instant struct {
	Domain *ClockDomain
	Tick   int64
}

// Timestamp is a wall-clock time: seconds since the Unix epoch and a
// nanosecond component in 0..999999999.
type Timestamp struct {
	Seconds int64
	Nanos   int32
}

// String is the display form of a duration, in nanoseconds.
func (d Duration) String() string { return strconv.FormatInt(int64(d), 10) + "ns" }

// String is the display form of an instant.
func (i Instant) String() string { return "Instant(" + strconv.FormatInt(i.Tick, 10) + ")" }

// String is the display form of a timestamp: UTC RFC 3339.
func (t Timestamp) String() string { return timeOf(t).Format("2006-01-02T15:04:05.999999999Z07:00") }

// timestampOf converts a calendar time to a Timestamp (UTC).
func timestampOf(t time.Time) Timestamp {
	t = t.UTC()
	return Timestamp{Seconds: t.Unix(), Nanos: int32(t.Nanosecond())}
}

// timeOf converts a Timestamp to a UTC calendar time.
func timeOf(t Timestamp) time.Time { return time.Unix(t.Seconds, int64(t.Nanos)).UTC() }

var timestampPattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$`)

func timeFail[T any](e TimeError) Result[T, TimeError] { return Fail[T, TimeError](e) }

func inTimestampRange(t time.Time) bool { return t.UTC().Year() >= 1 && t.UTC().Year() <= 9999 }

// Time_Duration is a duration of nanoseconds.
func Time_Duration(_ *Execution, nanoseconds int) Duration { return Duration(int64(nanoseconds)) }

// Time_Timestamp builds a timestamp from Unix seconds and a nanosecond part.
func Time_Timestamp(_ *Execution, seconds, nanoseconds int) Result[Timestamp, TimeError] {
	s, n := int64(seconds), int64(nanoseconds)
	if n < 0 || n >= 1e9 || s < -62135596800 || s > 253402300799 {
		return timeFail[Timestamp](TimeError_OutOfRange{})
	}
	return Ok[Timestamp, TimeError](Timestamp{Seconds: s, Nanos: int32(n)})
}

// Time_ParseTimestamp parses an RFC 3339 timestamp.
func Time_ParseTimestamp(_ *Execution, text string) Result[Timestamp, TimeError] {
	if !timestampPattern.MatchString(text) {
		return timeFail[Timestamp](TimeError_InvalidData{})
	}
	if dot := strings.IndexByte(text, '.'); dot >= 0 {
		end := dot + 1
		for end < len(text) && text[end] >= '0' && text[end] <= '9' {
			end++
		}
		if end-dot-1 > 9 {
			return timeFail[Timestamp](TimeError_InvalidData{})
		}
	}
	t, err := time.Parse(time.RFC3339Nano, text)
	if err != nil || t.Year() < 1 || t.Year() > 9999 {
		return timeFail[Timestamp](TimeError_InvalidData{})
	}
	// The written year is valid, but the offset moves the instant outside years 1 through 9999.
	if !inTimestampRange(t) {
		return timeFail[Timestamp](TimeError_OutOfRange{})
	}
	return Ok[Timestamp, TimeError](timestampOf(t))
}

// Sleep suspends the task for duration, waking early only to unwind a
// cancellation.
func Sleep(ctx *Execution, duration Duration) Unit {
	if duration < 0 {
		Raise(fmt.Sprintf("sleep: duration (nanoseconds) must be between 0 and %d, found %d", int64(math.MaxInt64), int64(duration)))
	}
	timer := time.NewTimer(time.Duration(duration))
	defer timer.Stop()
	select {
	case <-timer.C:
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	return Unit{}
}

func compareInt64(left, right int64) int {
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}
	return 0
}

// Time arithmetic keeps the signed 64-bit checks of Int arithmetic, but faults
// name the time operation and nanosecond operands.
func timeArithmeticFault(operation, leftLabel, rightLabel string, left, right int64) {
	leftLabel += " (nanoseconds)"
	if rightLabel != "factor" && rightLabel != "divisor" {
		rightLabel += " (nanoseconds)"
	}
	Raise(fmt.Sprintf("%s: overflow; found %s %d and %s %d; result nanoseconds must be between %d and %d", operation, leftLabel, left, rightLabel, right, int64(math.MinInt64), int64(math.MaxInt64)))
}

func checkedTimeAdd(operation, leftLabel, rightLabel string, left, right int64) int64 {
	result := left + right
	if right > 0 && result < left || right < 0 && result > left {
		timeArithmeticFault(operation, leftLabel, rightLabel, left, right)
	}
	return result
}

func checkedTimeSub(operation, leftLabel, rightLabel string, left, right int64) int64 {
	result := left - right
	if right < 0 && result < left || right > 0 && result > left {
		timeArithmeticFault(operation, leftLabel, rightLabel, left, right)
	}
	return result
}

func checkedTimeMul(operation string, value, factor int64) int64 {
	if value == 0 || factor == 0 {
		return 0
	}
	if value == math.MinInt64 && factor == -1 || factor == math.MinInt64 && value == -1 {
		timeArithmeticFault(operation, "value", "factor", value, factor)
	}
	result := value * factor
	if result/factor != value {
		timeArithmeticFault(operation, "value", "factor", value, factor)
	}
	return result
}

func Duration_Add(_ *Execution, left, other Duration) Duration {
	return Duration(checkedTimeAdd("Duration.add", "value", "other", int64(left), int64(other)))
}

// Duration_Plus and Duration_Minus are the + and - operators, which report
// their operands as left and right.
func Duration_Plus(_ *Execution, left, right Duration) Duration {
	return Duration(checkedTimeAdd("Duration.+", "left", "right", int64(left), int64(right)))
}

func Duration_Minus(_ *Execution, left, right Duration) Duration {
	return Duration(checkedTimeSub("Duration.-", "left", "right", int64(left), int64(right)))
}

func Duration_Subtract(_ *Execution, left, other Duration) Duration {
	return Duration(checkedTimeSub("Duration.subtract", "value", "other", int64(left), int64(other)))
}

func Duration_Multiply(_ *Execution, value Duration, factor int) Duration {
	return Duration(checkedTimeMul("Duration.multiply", int64(value), int64(factor)))
}

func Duration_Divide(_ *Execution, value Duration, divisor int) Duration {
	d := int64(divisor)
	if d == 0 {
		Raise("Duration.divide: division by zero; divisor must be nonzero, found 0")
	}
	if int64(value) == math.MinInt64 && d == -1 {
		timeArithmeticFault("Duration.divide", "value", "divisor", int64(value), d)
	}
	return Duration(int64(value) / d)
}

func durationRangeFault(operation string, value Duration) {
	Raise(fmt.Sprintf("%s: value (nanoseconds) must be between %d and %d, found %d", operation, int64(math.MinInt64+1), int64(math.MaxInt64), int64(value)))
}

func Duration_Negate(_ *Execution, value Duration) Duration {
	if value == Duration(math.MinInt64) {
		durationRangeFault("Duration.negate", value)
	}
	return -value
}

func Duration_Abs(_ *Execution, value Duration) Duration {
	if value == Duration(math.MinInt64) {
		durationRangeFault("Duration.abs", value)
	}
	if value < 0 {
		return -value
	}
	return value
}

func Duration_Compare(_ *Execution, left, other Duration) int {
	return compareInt64(int64(left), int64(other))
}

func Duration_ToNanoseconds(_ *Execution, value Duration) int { return FitInt(int64(value)) }
func Duration_ToMicroseconds(_ *Execution, value Duration) int {
	return FitInt(int64(value) / int64(time.Microsecond))
}
func Duration_ToMilliseconds(_ *Execution, value Duration) int {
	return FitInt(int64(value) / int64(time.Millisecond))
}
func Duration_ToSeconds(_ *Execution, value Duration) float64 {
	return float64(value) / float64(time.Second)
}
func Duration_ToMinutes(_ *Execution, value Duration) float64 {
	return float64(value) / float64(time.Minute)
}
func Duration_ToHours(_ *Execution, value Duration) float64 {
	return float64(value) / float64(time.Hour)
}

func sameClock(a, b Instant) {
	if a.Domain != b.Domain {
		Raise("instants belong to different clock domains")
	}
}

func Instant_Shift(_ *Execution, value Instant, duration Duration) Instant {
	return Instant{Domain: value.Domain, Tick: checkedTimeAdd("Instant.shift", "value", "duration", value.Tick, int64(duration))}
}

func Instant_Difference(_ *Execution, left, other Instant) Duration {
	sameClock(left, other)
	return Duration(checkedTimeSub("Instant.difference", "value", "other", left.Tick, other.Tick))
}

func Instant_Compare(_ *Execution, left, other Instant) int {
	sameClock(left, other)
	return compareInt64(left.Tick, other.Tick)
}

func Timestamp_ToString(_ *Execution, value Timestamp) string {
	return timeOf(value).Format(time.RFC3339Nano)
}
func Timestamp_UnixSeconds(_ *Execution, value Timestamp) int { return FitInt(value.Seconds) }
func Timestamp_Nanoseconds(_ *Execution, value Timestamp) int { return int(value.Nanos) }

func Timestamp_Shift(_ *Execution, value Timestamp, duration Duration) Result[Timestamp, TimeError] {
	t := timeOf(value).Add(time.Duration(duration))
	if !inTimestampRange(t) {
		return timeFail[Timestamp](TimeError_OutOfRange{})
	}
	return Ok[Timestamp, TimeError](timestampOf(t))
}

func Timestamp_Difference(_ *Execution, left, other Timestamp) Result[Duration, TimeError] {
	x, y := timeOf(left), timeOf(other)
	d := x.Sub(y)
	if !y.Add(d).Equal(x) {
		return timeFail[Duration](TimeError_OutOfRange{})
	}
	return Ok[Duration, TimeError](Duration(d))
}

func Timestamp_Compare(_ *Execution, left, other Timestamp) int {
	return int(timeOf(left).Compare(timeOf(other)))
}

// Instant_Unshift is Instant - Duration.
func Instant_Unshift(_ *Execution, value Instant, duration Duration) Instant {
	return Instant{Domain: value.Domain, Tick: checkedTimeSub("Instant.-", "value", "duration", value.Tick, int64(duration))}
}

// Instant_Equal compares instants of one clock domain.
func Instant_Equal(_ *Execution, a, b Instant) bool {
	sameClock(a, b)
	return a.Tick == b.Tick
}

// Equal makes Instant satisfy native equality; it faults across clock domains.
func (i Instant) Equal(ctx *Execution, other Instant) bool { return Instant_Equal(ctx, i, other) }

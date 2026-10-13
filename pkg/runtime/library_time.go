package msruntime

import (
	"fmt"
	"math"
	"time"
)

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	libraryAdd("time", "duration", "Duration", []LibraryParam{p("nanoseconds", "Int64")}, func(_ *Execution, _ string, a []Value) Value {
		return Duration(nativeInteger(a[0]))
	})
	for _, operation := range []struct{ name, operator string }{{"add", "+"}, {"subtract", "-"}} {
		libraryAdd("time", "duration_"+operation.name, "Duration", []LibraryParam{p("left", "Duration"), p("right", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
			left, right := int64(a[0].(Duration)), int64(a[1].(Duration))
			if operation.operator == "+" {
				return Duration(checkedTimeAdd("Duration.add", "value", "right", left, right))
			}
			return Duration(checkedTimeSub("Duration.subtract", "value", "right", left, right))
		})
	}
	libraryAdd("time", "duration_multiply", "Duration", []LibraryParam{p("value", "Duration"), p("factor", "Int64")}, func(_ *Execution, _ string, a []Value) Value {
		return Duration(checkedTimeMul("Duration.multiply", int64(a[0].(Duration)), nativeInteger(a[1])))
	})
	libraryAdd("time", "duration_divide", "Duration", []LibraryParam{p("value", "Duration"), p("divisor", "Int64")}, func(_ *Execution, _ string, a []Value) Value {
		value, divisor := int64(a[0].(Duration)), nativeInteger(a[1])
		if divisor == 0 {
			return Panic("Duration.divide: division by zero; divisor must be nonzero, found 0")
		}
		if value == math.MinInt64 && divisor == -1 {
			timeArithmeticFault("Duration.divide", "value", "divisor", value, divisor)
		}
		return Duration(value / divisor)
	})
	libraryAdd("time", "duration_negate", "Duration", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		value := int64(a[0].(Duration))
		if value == math.MinInt64 {
			return libraryRangeFault("Duration.negate", "value (nanoseconds)", value, math.MinInt64+1, math.MaxInt64)
		}
		return Duration(-value)
	})
	libraryAdd("time", "duration_abs", "Duration", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		value := a[0].(Duration)
		if value == Duration(math.MinInt64) {
			return libraryRangeFault("Duration.abs", "value (nanoseconds)", int64(value), math.MinInt64+1, math.MaxInt64)
		}
		if value < 0 {
			return -value
		}
		return value
	})
	libraryAdd("time", "duration_compare", "Int", []LibraryParam{p("left", "Duration"), p("right", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		return libraryTimeCompare(int64(a[0].(Duration)), int64(a[1].(Duration)))
	})
	for _, unit := range []struct {
		name  string
		scale int64
	}{{"nanoseconds", 1}, {"microseconds", 1000}, {"milliseconds", 1000000}} {
		libraryAdd("time", "duration_"+unit.name, "Int64", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
			return int64(a[0].(Duration)) / unit.scale
		})
	}
	for _, unit := range []struct {
		name  string
		scale time.Duration
	}{{"seconds", time.Second}, {"minutes", time.Minute}, {"hours", time.Hour}} {
		libraryAdd("time", "duration_"+unit.name, "Float64", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
			return float64(a[0].(Duration)) / float64(unit.scale)
		})
	}
	libraryAdd("time", "instant_shift", "Instant", []LibraryParam{p("value", "Instant"), p("duration", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		value, offset := a[0].(Instant), int64(a[1].(Duration))
		return Instant{value.Domain, checkedTimeAdd("Instant.shift", "value", "duration", value.Tick, offset)}
	})
	libraryAdd("time", "instant_difference", "Duration", []LibraryParam{p("left", "Instant"), p("right", "Instant")}, func(_ *Execution, _ string, a []Value) Value {
		left, right := a[0].(Instant), a[1].(Instant)
		sameClock(left, right)
		return Duration(checkedTimeSub("Instant.difference", "value", "right", left.Tick, right.Tick))
	})
	libraryAdd("time", "instant_compare", "Int", []LibraryParam{p("left", "Instant"), p("right", "Instant")}, func(_ *Execution, _ string, a []Value) Value {
		left, right := a[0].(Instant), a[1].(Instant)
		sameClock(left, right)
		return libraryTimeCompare(left.Tick, right.Tick)
	})
	libraryAdd("time", "timestamp_compare", "Int", []LibraryParam{p("left", "Timestamp"), p("right", "Timestamp")}, func(_ *Execution, _ string, a []Value) Value {
		return int64(a[0].(libraryTimestamp).t.Compare(a[1].(libraryTimestamp).t))
	})
}

func libraryTimeCompare(left, right int64) int64 {
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}
	return 0
}

// Time arithmetic retains the same signed 64-bit checks as Int arithmetic, but
// faults name the time operation and nanosecond operands. Int hot paths remain
// independent of these diagnostic labels.
func timeArithmeticFault(operation, leftLabel, rightLabel string, left, right int64) {
	leftLabel += " (nanoseconds)"
	if rightLabel != "factor" && rightLabel != "divisor" {
		rightLabel += " (nanoseconds)"
	}
	Panic(fmt.Sprintf("%s: overflow; found %s %d and %s %d; result nanoseconds must be between %d and %d", operation, leftLabel, left, rightLabel, right, math.MinInt64, math.MaxInt64))
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

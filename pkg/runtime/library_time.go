package msruntime

import "time"

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	libraryAdd("time", "duration", "Duration", []LibraryParam{p("nanoseconds", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		return Duration(a[0].(int64))
	})
	for _, operation := range []struct{ name, operator string }{{"add", "+"}, {"subtract", "-"}} {
		libraryAdd("time", "duration_"+operation.name, "Duration", []LibraryParam{p("left", "Duration"), p("right", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
			return Binary(operation.operator, a[0], a[1])
		})
	}
	libraryAdd("time", "duration_multiply", "Duration", []LibraryParam{p("value", "Duration"), p("factor", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		return Duration(checkedMul(int64(a[0].(Duration)), a[1].(int64)))
	})
	libraryAdd("time", "duration_divide", "Duration", []LibraryParam{p("value", "Duration"), p("divisor", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		return Duration(Binary("/", int64(a[0].(Duration)), a[1]).(int64))
	})
	libraryAdd("time", "duration_negate", "Duration", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		return Duration(checkedSub(0, int64(a[0].(Duration))))
	})
	libraryAdd("time", "duration_abs", "Duration", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		value := a[0].(Duration)
		if value < 0 {
			return Duration(checkedSub(0, int64(value)))
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
		libraryAdd("time", "duration_"+unit.name, "Int", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
			return int64(a[0].(Duration)) / unit.scale
		})
	}
	for _, unit := range []struct {
		name  string
		scale time.Duration
	}{{"seconds", time.Second}, {"minutes", time.Minute}, {"hours", time.Hour}} {
		libraryAdd("time", "duration_"+unit.name, "Float", []LibraryParam{p("value", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
			return float64(a[0].(Duration)) / float64(unit.scale)
		})
	}
	libraryAdd("time", "instant_shift", "Instant", []LibraryParam{p("value", "Instant"), p("duration", "Duration")}, func(_ *Execution, _ string, a []Value) Value {
		return Binary("+", a[0], a[1])
	})
	libraryAdd("time", "instant_difference", "Duration", []LibraryParam{p("left", "Instant"), p("right", "Instant")}, func(_ *Execution, _ string, a []Value) Value {
		return Binary("-", a[0], a[1])
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

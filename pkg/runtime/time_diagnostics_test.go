package msruntime

import (
	"context"
	"math"
	"testing"
)

func TestTimeDiagnosticsAndCancellation(t *testing.T) {
	domain := &clockDomain{}
	cases := []struct {
		receiver Value
		method   string
		args     []Argument
		want     string
	}{
		{Instant{Domain: domain, Tick: math.MaxInt64}, "shift", []Argument{{"duration", Duration(1)}}, "Instant.shift: overflow; found value (nanoseconds) 9223372036854775807 and duration (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{Instant{Domain: domain, Tick: math.MinInt64}, "shift", []Argument{{"duration", Duration(-1)}}, "Instant.shift: overflow; found value (nanoseconds) -9223372036854775808 and duration (nanoseconds) -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{Instant{Domain: domain, Tick: math.MaxInt64}, "difference", []Argument{{"other", Instant{Domain: domain, Tick: -1}}}, "Instant.difference: overflow; found value (nanoseconds) 9223372036854775807 and other (nanoseconds) -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807"},
		{Duration(1), "divide", []Argument{{"divisor", int64(0)}}, "Duration.divide: division by zero; divisor must be nonzero, found 0"},
		{Duration(math.MinInt64), "abs", nil, "Duration.abs: value (nanoseconds) must be between -9223372036854775807 and 9223372036854775807, found -9223372036854775808"},
	}
	for _, tc := range cases {
		fault, ok := recovered(func() { Invoke(RootExecution(), Bind(tc.receiver, "", tc.method), tc.args) }).(Fault)
		if !ok || fault.Message != tc.want {
			t.Fatalf("%s fault = %#v, want %q", tc.method, fault, tc.want)
		}
		ctx, cancel := context.WithCancel(context.Background())
		execution := newExecution(RootExecution(), ctx)
		cancel()
		failure := recovered(func() { Invoke(execution, Bind(tc.receiver, "", tc.method), tc.args) })
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("%s cancellation became %#v", tc.method, failure)
		}
	}
	for _, tick := range []int64{math.MinInt64, math.MaxInt64} {
		instant := Instant{Domain: domain, Tick: tick}
		if Invoke(RootExecution(), Bind(instant, "", "shift"), []Argument{{"duration", Duration(0)}}) != instant {
			t.Fatal("zero shift changed an instant boundary")
		}
		if Invoke(RootExecution(), Bind(instant, "", "difference"), []Argument{{"other", instant}}) != Duration(0) {
			t.Fatal("same-instant difference overflowed")
		}
	}
}

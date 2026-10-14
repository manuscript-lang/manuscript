package msruntime

import (
	"math"
	"strings"
	"testing"
)

func TestTimeReceiverFaultsAndBoundaries(t *testing.T) {
	ctx := RootExecution()
	domain, otherDomain := &clockDomain{}, &clockDomain{}
	call := func(value Value, method string, args ...Argument) Value {
		return Invoke(ctx, Bind(value, "", method), args)
	}
	for name, action := range map[string]func(){
		"add overflow":      func() { call(Duration(math.MaxInt64), "add", Argument{"other", Duration(1)}) },
		"subtract overflow": func() { call(Duration(math.MinInt64), "subtract", Argument{"other", Duration(1)}) },
		"multiply overflow": func() { call(Duration(math.MaxInt64), "multiply", Argument{"factor", int64(2)}) },
		"divide overflow":   func() { call(Duration(math.MinInt64), "divide", Argument{"divisor", int64(-1)}) },
		"zero division":     func() { call(Duration(1), "divide", Argument{"divisor", int64(0)}) },
		"negate overflow":   func() { call(Duration(math.MinInt64), "negate") },
		"abs overflow":      func() { call(Duration(math.MinInt64), "abs") },
		"shift overflow":    func() { call(Instant{Domain: domain, Tick: math.MaxInt64}, "shift", Argument{"duration", Duration(1)}) },
		"difference overflow": func() {
			call(Instant{Domain: domain, Tick: math.MaxInt64}, "difference", Argument{"other", Instant{Domain: domain, Tick: -1}})
		},
	} {
		t.Run(name, func(t *testing.T) {
			fault, ok := recovered(action).(Fault)
			if !ok || !(strings.Contains(fault.Message, "overflow") || strings.Contains(fault.Message, "division by zero") || strings.Contains(fault.Message, "value (nanoseconds) must be between")) {
				t.Fatalf("expected arithmetic fault, got %#v", fault)
			}
		})
	}
	for _, method := range []string{"compare", "difference"} {
		fault, ok := recovered(func() {
			call(Instant{Domain: domain, Tick: 0}, method, Argument{"other", Instant{Domain: otherDomain, Tick: 0}})
		}).(Fault)
		if !ok || !strings.Contains(fault.Message, "clock domains") {
			t.Fatalf("%s must reject different domains: %#v", method, fault)
		}
	}
	if call(Duration(math.MinInt64), "compare", Argument{"other", Duration(math.MaxInt64)}) != int64(-1) {
		t.Fatal("comparison must not subtract and overflow")
	}
	if call(Duration(0), "abs") != Duration(0) || call(Duration(math.MaxInt64), "abs") != Duration(math.MaxInt64) {
		t.Fatal("absolute value changed a nonnegative duration")
	}
}

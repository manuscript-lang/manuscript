package msruntime

import (
	"math"
	"testing"
)

func TestWideIntegerCheckedFaultsAndBoundaries(t *testing.T) {
	cases := map[string]func(){
		"addition":          func() { Binary("+", Int64(math.MaxInt64), Int64(1)) },
		"subtraction":       func() { Binary("-", Int64(math.MinInt64), Int64(1)) },
		"multiplication":    func() { Binary("*", Int64(math.MaxInt64), Int64(2)) },
		"minimum multiply":  func() { Binary("*", Int64(math.MinInt64), Int64(-1)) },
		"minimum division":  func() { Binary("/", Int64(math.MinInt64), Int64(-1)) },
		"division by zero":  func() { Binary("/", Int64(3), Int64(0)) },
		"remainder by zero": func() { Binary("%", Int64(3), Int64(0)) },
		"minimum negation":  func() { Unary("-", Int64(math.MinInt64)) },
	}
	for name, action := range cases {
		t.Run(name, func(t *testing.T) {
			defer func() {
				fault, ok := recover().(Fault)
				if !ok || len(fault.Message) < 5 || fault.Message[:5] != "Int64" {
					t.Fatalf("expected Int64 fault, got %#v", fault)
				}
			}()
			action()
			t.Fatal("wide operation did not fault")
		})
	}
	if Binary("%", Int64(math.MinInt64), Int64(-1)) != Int64(0) {
		t.Fatal("minimum remainder is not zero")
	}
	if Equal(Int64(3), int64(3)) || Equal(Float64(3), float64(3)) {
		t.Fatal("explicit width identity erased")
	}
	if libraryRuntimeType("Result[Int64][NumberError]") != "@std/Result[Int64][@std/NumberError]" {
		t.Fatal("numeric type digits were treated as nominal stdlib names")
	}
}

func TestWideFloatConversionChecksBeforeHostCast(t *testing.T) {
	for _, value := range []float64{math.NaN(), math.Inf(1), math.Inf(-1), 0x1p63, math.Nextafter(-0x1p63, math.Inf(-1))} {
		if truncateInt64(value).(Alternative).Tag != "none" {
			t.Fatalf("accepted out-of-range %g", value)
		}
	}
	for _, value := range []float64{-0x1p63, math.Nextafter(0x1p63, 0), -3.5, 3.5} {
		result := truncateInt64(value).(Alternative)
		if result.Tag != "some" || result.Fields[0] != Int64(value) {
			t.Fatalf("invalid truncation for %g: %#v", value, result)
		}
	}
}

func TestWideNativeResultsAndFreshHostFields(t *testing.T) {
	const count = int64(3000000000)
	for typ, fields := range nativeWideHostFields {
		values := map[string]Value{}
		for _, field := range fields {
			values[field] = count
		}
		record := nativeHostRecord(typ, values)
		for _, field := range fields {
			if value, ok := record.Fields[field].(Int64); !ok || value != Int64(count) {
				t.Fatalf("%s.%s narrowed or lost Int64 identity: %#v", typ, field, record.Fields[field])
			}
		}
	}
	if nativeNumericResult("@std/Result[Int64][@std/IoError]", count) != Int64(count) {
		t.Fatal("wide count result narrowed")
	}
	if nativeNumericResult("Float64", 1e300) != Float64(1e300) {
		t.Fatal("wide host Float narrowed")
	}
}

func TestWideEqualViews(t *testing.T) {
	ctx := RootExecution()
	for _, value := range []Value{Int64(3), Float64(3)} {
		view := ViewOf("@std/Equal", value)
		for _, pair := range [][2]Value{{value, view}, {view, value}, {view, view}} {
			if !EqualIn(ctx, pair[0], pair[1]) {
				t.Fatalf("equal wide views compare false: %#v, %#v", pair[0], pair[1])
			}
		}
		if !Invoke(ctx, NativeMember(value, "equals"), []Argument{{"other", view}}).(bool) {
			t.Fatal("wide equals method erased its viewed argument")
		}
	}
	values := &Set{Type: "@std/Set[Int64]"}
	values.add(ctx, ViewOf("@std/Equal", Int64(3)))
	if values.find(ctx, ViewOf("@std/Equal", Int64(3))) < 0 {
		t.Fatal("viewed wide hash membership lost equal key")
	}
}

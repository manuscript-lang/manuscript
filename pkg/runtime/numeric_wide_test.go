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

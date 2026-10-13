package msruntime

import (
	"math"
	"reflect"
	"testing"
)

func TestDefaultNumericRepresentationAndBoundaries(t *testing.T) {
	if reflect.TypeOf(Integer("2147483647")).Size() != 4 || reflect.TypeOf(Float("1.25")).Size() != 4 {
		t.Fatal("default box payload must be four bytes")
	}
	for name, operation := range map[string]func(){
		"add": func() { IntAdd(math.MaxInt32, 1) }, "subtract": func() { IntSubtract(math.MinInt32, 1) },
		"multiply": func() { IntMultiply(math.MaxInt32, 2) }, "divide": func() { IntDivide(math.MinInt32, -1) },
		"negate": func() { Unary("-", int32(math.MinInt32)) }, "zero divide": func() { IntDivide(1, 0) },
		"zero remainder": func() { IntRemainder(1, 0) },
	} {
		t.Run(name, func(t *testing.T) {
			defer func() {
				if _, ok := recover().(Fault); !ok {
					t.Fatal("expected checked numeric fault")
				}
			}()
			operation()
		})
	}
	if IntRemainder(math.MinInt32, -1) != 0 || IntDivide(-7, 2) != -3 || IntRemainder(-7, 3) != -1 {
		t.Fatal("division semantics changed")
	}
	// Per-operation binary32 rounding forbids fused multiply/subtract behavior.
	product := Binary("*", float32(1.0001220703125), float32(0.9998779296875))
	if Binary("-", product, float32(1)) != float32(0) {
		t.Fatal("float operations were fused or widened")
	}
	if Format(float32(0.1)) != "0.1" || Format(float32(math.Copysign(0, -1))) != "-0" {
		t.Fatal("binary32 shortest formatting/signed zero")
	}
	if Equal(float32(math.NaN()), float32(math.NaN())) || !Equal(float32(0), float32(math.Copysign(0, -1))) {
		t.Fatal("IEEE equality")
	}
	if math.Float32bits(Float("1e-45").(float32)) != 1 {
		t.Fatal("smallest subnormal literal")
	}
}
func TestExplicitNumericConversionBoundaries(t *testing.T) {
	for _, v := range []float64{-2147483648.5, -2147483648, 2147483647.5} {
		got := truncateInt32(v).(Alternative)
		if got.Tag != "some" || got.Fields[0] != int32(math.Trunc(v)) {
			t.Fatalf("truncate before checking: %v -> %#v", v, got)
		}
	}
	for _, v := range []float64{-2147483649, 2147483648, math.NaN(), math.Inf(1)} {
		if truncateInt32(v).(Alternative).Tag != "none" {
			t.Fatalf("accepted %v", v)
		}
	}
	const value = Int64(4611686293305294849) // 2^62 + 2^38 + 1; a double-rounding trap.
	member, _ := wideNumericMember(value, "to_float", "")
	got := Invoke(RootExecution(), member, nil)
	if got != float32(4611686568183201792) || got == float32(float64(value)) {
		t.Fatalf("Int64 -> Float must round directly: %#v", got)
	}
	member, _ = wideNumericMember(Int64(2147483648), "to_int", "")
	if Invoke(RootExecution(), member, nil).(Alternative).Tag != "none" {
		t.Fatal("wide int truncation")
	}
	var hash int32 = HashIn(RootExecution(), int32(-3))
	_ = hash
}

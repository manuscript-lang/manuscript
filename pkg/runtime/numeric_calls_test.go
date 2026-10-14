package msruntime

import (
	"context"
	"math"
	"testing"
)

func TestTypedNumericNativesMatchCallableIEEE(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	for _, test := range []struct {
		name   string
		native func(*Execution, float64) float64
	}{{"sqrt", NativeFloatSqrt}, {"abs", NativeFloatAbs}, {"floor", NativeFloatFloor}, {"ceil", NativeFloatCeil}} {
		boxed := StandardFunction("math/"+test.name, "Float").(Function)
		for _, value := range []float64{math.NaN(), math.Inf(1), math.Inf(-1), math.Copysign(0, -1), 0, math.SmallestNonzeroFloat64, -1.25, 4, math.MaxFloat64} {
			got := test.native(ctx, value)
			want := boxed.Body(ctx, []Value{value}).(float64)
			if math.Float64bits(got) != math.Float64bits(want) {
				t.Fatalf("%s(%v): %x != %x", test.name, value, math.Float64bits(got), math.Float64bits(want))
			}
		}
	}
	for _, value := range []int64{math.MinInt64, -10000, 0, 10000, math.MaxInt64} {
		if got := NativeIntToFloat(ctx, value); got != float64(value) {
			t.Fatal(value, got)
		}
	}
	if allocations := testing.AllocsPerRun(100, func() { _ = NativeFloatSqrt(ctx, 2) }); allocations != 0 {
		t.Fatal("typed native allocated", allocations)
	}
}

type numericCancelContext struct {
	context.Context
	checks   int
	cancelAt int
}

func (c *numericCancelContext) Err() error {
	c.checks++
	if c.checks >= c.cancelAt {
		return context.Canceled
	}
	return nil
}
func TestTypedNumericNativeCheckpoints(t *testing.T) {
	for _, cancelAt := range []int{1, 2, 3} {
		ctx := RootExecution()
		observed := &numericCancelContext{Context: ctx.Context, cancelAt: cancelAt}
		ctx.Context = observed
		failure := sourceFailure(func() { NativeFloatSqrt(ctx, 4) })
		if observed.checks != 2 && cancelAt != 1 {
			t.Fatalf("checks=%d", observed.checks)
		}
		if cancelAt <= 2 {
			if _, ok := failure.(cancelled); !ok {
				t.Fatalf("cancel at %d: %v", cancelAt, failure)
			}
		} else if failure != nil {
			t.Fatal(failure)
		}
		FinishExecution(ctx)
	}
}

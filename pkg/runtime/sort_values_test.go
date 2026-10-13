package msruntime

import (
	"context"
	"math"
	"reflect"
	"testing"
)

func TestPrimitiveSortingCancellationPreservesInput(t *testing.T) {
	for _, operation := range []struct {
		name, typ string
		item      Value
	}{
		{"sorted_int", "Int", int64(2)},
		{"sorted_float", "Float", float64(2)},
		{"sorted_strings", "String", "é"},
	} {
		items := make([]Value, 4096)
		for i := range items {
			items[i] = operation.item
		}
		input := libraryList(operation.typ, items)
		ctx := RootExecution()
		workContext, cancel := context.WithCancel(ctx.Context)
		work := &stringWorkCancellation{Context: workContext, cancel: cancel}
		ctx.Context = work
		failure := recovered(func() {
			libraryFunctions["collections/"+operation.name].Body(ctx, input.Type, []Value{input})
		})
		cancel()
		if _, ok := failure.(cancelled); !ok || work.checks < 2 {
			t.Fatalf("%s lost cancellation: %#v", operation.name, failure)
		}
		if input.Len() != len(items) || input.kind == listBoxed {
			t.Fatal("cancelled sorting replaced input storage")
		}
		for _, item := range Iterate(input) {
			if item != operation.item {
				t.Fatal("cancelled sorting changed input values")
			}
		}
	}
}

func TestPrimitiveSortingPreservesTypedStableStorage(t *testing.T) {
	negativeZero := math.Copysign(0, -1)
	for _, test := range []struct {
		name, typ   string
		input, want []Value
	}{
		{"sorted_int", "Int", []Value{int64(math.MaxInt64), int64(-1), int64(math.MinInt64)}, []Value{int64(math.MinInt64), int64(-1), int64(math.MaxInt64)}},
		{"sorted_float", "Float", []Value{math.Inf(1), negativeZero, 0.0, math.Inf(-1)}, []Value{math.Inf(-1), negativeZero, 0.0, math.Inf(1)}},
		{"sorted_strings", "String", []Value{"é", "a", "aa"}, []Value{"a", "aa", "é"}},
	} {
		for _, legacy := range []bool{false, true} {
			input := NewList("@std/List["+test.typ+"]", test.input)
			if legacy {
				input = &List{Type: input.Type, Items: append([]Value(nil), test.input...)}
			}
			out := libraryFunctions["collections/"+test.name].Body(RootExecution(), input.Type, []Value{input}).(*List)
			if out == input || out.kind == listBoxed || out.Items != nil || !reflect.DeepEqual(out.Boxed(), test.want) || !reflect.DeepEqual(input.Boxed(), test.input) {
				t.Fatalf("%s legacy=%v storage/order/identity", test.name, legacy)
			}
			if test.typ == "Float" && (!math.Signbit(out.Get(1).(float64)) || math.Signbit(out.Get(2).(float64))) {
				t.Fatal("sorting changed stable signed-zero order")
			}
			out.Set(0, test.input[0])
			if input.Get(0) != test.input[0] {
				t.Fatal("sorted output shares mutable input backing")
			}
		}
	}
	first, second := math.Float64frombits(0x7ff8000000000001), math.Float64frombits(0x7ff8000000000002)
	input := NewFloatList("@std/List[Float]", []float64{1, first, -1, second})
	out := libraryFunctions["collections/sorted_float"].Body(RootExecution(), input.Type, []Value{input}).(*List)
	if math.Float64bits(out.Get(0).(float64)) != math.Float64bits(first) || math.Float64bits(out.Get(1).(float64)) != math.Float64bits(second) || out.Get(2) != float64(-1) || out.Get(3) != float64(1) {
		t.Fatal("NaNs first, stable payloads and numeric order")
	}
}

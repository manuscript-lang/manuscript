package msruntime

import (
	"context"
	"math"
	"slices"
	"strings"
	"testing"
)

func TestCollectionCallbackOrderAndShortCircuit(t *testing.T) {
	values := libraryList("Int", []Value{int32(1), int32(2), int32(3), int32(4)})
	for _, test := range []struct {
		name   string
		want   []int32
		result Value
	}{
		{"find", []int32{1, 2}, optional("Int", int32(2), true)},
		{"find_last", []int32{4}, optional("Int", int32(4), true)},
		{"find_index", []int32{1, 2}, optional("Int", int32(1), true)},
		{"find_last_index", []int32{4}, optional("Int", int32(3), true)},
		{"some", []int32{1, 2}, true},
		{"every", []int32{1}, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			var seen []int32
			predicate := NewFunction([]string{"value"}, "Bool", func(_ *Execution, a []Value) Value { n := a[0].(int32); seen = append(seen, n); return n%2 == 0 })
			result := Invoke(RootExecution(), NativeMember(values, test.name), []Argument{{"predicate", predicate}})
			if !Equal(result, test.result) || !slices.Equal(seen, test.want) {
				t.Fatalf("result %#v; calls %v", result, seen)
			}
		})
	}
	var seen []int32
	operation := NewFunction([]string{"value"}, "Unit", func(_ *Execution, a []Value) Value { seen = append(seen, a[0].(int32)); return Unit{} })
	Invoke(RootExecution(), NativeMember(values, "for_each"), []Argument{{"operation", operation}})
	if !slices.Equal(seen, []int32{1, 2, 3, 4}) {
		t.Fatal(seen)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, ok := recovered(func() {
		Invoke(&Execution{Context: ctx}, NativeMember(values, "for_each"), []Argument{{"operation", operation}})
	}).(cancelled); !ok {
		t.Fatal("lost cancellation")
	}
}

func TestListCloneSeparatesUpdateStorage(t *testing.T) {
	original := libraryList("Int", []Value{int32(1), int32(2), int32(3), int32(4)})
	for _, test := range []struct {
		name string
		args []Argument
	}{
		{"with_value", []Argument{{"index", int32(-1)}, {"value", int32(9)}}},
		{"without", []Argument{{"index", int32(1)}}},
		{"fill", []Argument{{"value", int32(9)}, {"start", int32(0)}, {"end", int32(4)}}},
		{"copy_within", []Argument{{"target", int32(1)}, {"start", int32(0)}, {"end", int32(3)}}},
		{"reverse", nil},
		{"slice", []Argument{{"start", int32(0)}, {"end", int32(4)}}},
		{"with_values", []Argument{{"start", int32(0)}, {"delete_count", int32(0)}, {"replacement", original}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := Invoke(RootExecution(), NativeMember(Clone(original), test.name), test.args).(*List)
			result.Items[0] = int32(99) // model a subsequent builder/native adapter write
			if !Equal(original, libraryList("Int", []Value{int32(1), int32(2), int32(3), int32(4)})) {
				t.Fatal("update shared source storage", original)
			}
		})
	}
	for _, args := range [][]Argument{
		{{"start", int32(-1)}, {"delete_count", int32(0)}, {"replacement", original}},
		{{"start", int32(1)}, {"delete_count", int32(math.MaxInt32)}, {"replacement", original}},
	} {
		if _, ok := recovered(func() { Invoke(RootExecution(), NativeMember(original, "with_values"), args) }).(Fault); !ok {
			t.Fatal("invalid splice did not fault")
		}
	}
	if _, ok := recovered(func() {
		Invoke(RootExecution(), NativeMember(original, "with_value"), []Argument{{"index", int32(math.MinInt32)}, {"value", int32(9)}})
	}).(Fault); !ok {
		t.Fatal("invalid index did not fault")
	}
}

func TestRangeOverflowAndLimits(t *testing.T) {
	for _, test := range []struct {
		start, end, step, max int32
		want                  []Value
	}{
		{math.MaxInt32 - 1, math.MaxInt32, 2, 1, []Value{int32(math.MaxInt32 - 1)}},
		{math.MinInt32 + 1, math.MinInt32, -2, 1, []Value{int32(math.MinInt32 + 1)}},
		{math.MaxInt32, math.MinInt32, math.MinInt32, 2, []Value{int32(math.MaxInt32), int32(-1)}},
		{1, 0, 1, 0, nil},
		{0, 1, -1, 0, nil},
		{0, 0, 1, 0, nil},
	} {
		value := librarySuccess(t, libraryCall(t, "collections/range", test.start, test.end, test.step, test.max)).(*List)
		if value.Type != "@std/List[Int]" || !slices.Equal(value.Items, test.want) {
			t.Fatal(value)
		}
	}
	libraryFailure(t, libraryCall(t, "collections/range", int32(0), int32(math.MaxInt32), int32(1), int32(2)), "LimitExceeded")
	libraryFailure(t, libraryCall(t, "collections/filled", int32(1), int32(-1), int32(2)), "InvalidInput")
}

func TestTextPaddingAndNormalizationBoundaries(t *testing.T) {
	for _, test := range []struct {
		text, padding string
		target, max   int32
		want          string
	}{
		{"x", "é🙂", 4, 9, "é🙂éx"},
		{"x", "é🙂", 3, 7, "é🙂x"},
		{"x", "é🙂", 2, 3, "éx"},
		{"x", "é🙂", 1, 1, "x"},
		{"", "é🙂", 0, 0, ""},
		{"x", "", math.MaxInt32, 1, "x"},
	} {
		got := librarySuccess(t, libraryCall(t, "string/pad_start", test.text, test.target, test.padding, test.max))
		if got != test.want {
			t.Fatal(test, got)
		}
	}
	libraryFailure(t, libraryCall(t, "string/pad_start", "x", int32(math.MaxInt32), "é", int32(3)), "LimitExceeded")
	libraryFailure(t, libraryCall(t, "string/pad_start", "x", int32(2), "🙂", int32(4)), "LimitExceeded")
	libraryFailure(t, libraryCall(t, "string/pad_end", "x", int32(2), " ", int32(-1)), "InvalidInput")
	libraryFailure(t, libraryCall(t, "string/replace_all", "", "", "é", int32(1)), "LimitExceeded")
	if got := librarySuccess(t, libraryCall(t, "string/replace_all", "", "", "é", int32(2))); got != "é" {
		t.Fatal(got)
	}
	// Normalization must enforce output size, even when normalization shrinks input.
	text := strings.Repeat("e\u0301", 3000)
	got := librarySuccess(t, libraryCall(t, "string/normalize", text, "NFC", int32(6000)))
	if got != strings.Repeat("é", 3000) {
		t.Fatal("normalization across chunks")
	}
	libraryFailure(t, libraryCall(t, "string/normalize", text, "NFD", int32(8999)), "LimitExceeded")
}

func TestFloatPrecisionFormatting(t *testing.T) {
	for _, test := range []struct {
		name   string
		value  float32
		digits int32
		want   string
	}{
		{"format_fixed", 1.5, 3, "1.500"},
		{"format_fixed", 2.5, 0, "2"}, // Manuscript's binary32 ties-to-even convention
		{"format_fixed", 1e21, 0, "1e+21"},
		{"format_exponential", 1.5, 3, "1.500e+0"},
		{"format_precision", 1.5, 4, "1.500"},
		{"format_precision", 0, 3, "0.00"},
		{"format_precision", 9.999, 3, "10.0"},
		{"format_precision", 0.000001, 2, "0.0000010"},
		{"format_precision", 0.0000001, 2, "1.0e-7"},
		{"format_precision", float32(math.Inf(1)), 2, "Infinity"},
		{"format_exponential", float32(math.Inf(-1)), 2, "-Infinity"},
		{"format_fixed", float32(math.NaN()), 2, "NaN"},
		{"format_fixed", float32(math.Copysign(0, -1)), 2, "-0.00"},
	} {
		t.Run(test.name+"/"+test.want, func(t *testing.T) {
			got := librarySuccess(t, libraryCall(t, "numbers/"+test.name, test.value, test.digits))
			if got != test.want {
				t.Fatal(got, test.want)
			}
		})
	}
	libraryFailure(t, libraryCall(t, "numbers/format_precision", 1.0, int32(0)), "InvalidInput")
	libraryFailure(t, libraryCall(t, "numbers/format_fixed", 1.0, int32(101)), "InvalidInput")
}

package msruntime

import (
	"context"
	"math"
	"slices"
	"strings"
	"testing"
)

func TestCollectionCallbackOrderAndShortCircuit(t *testing.T) {
	values := libraryList("Int", []Value{int64(1), int64(2), int64(3), int64(4)})
	for _, test := range []struct {
		name   string
		want   []int64
		result Value
	}{
		{"find", []int64{1, 2}, optional("Int", int64(2), true)},
		{"find_last", []int64{4}, optional("Int", int64(4), true)},
		{"find_index", []int64{1, 2}, optional("Int", int64(1), true)},
		{"find_last_index", []int64{4}, optional("Int", int64(3), true)},
		{"some", []int64{1, 2}, true},
		{"every", []int64{1}, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			var seen []int64
			predicate := NewFunction([]string{"value"}, "Bool", func(_ *Execution, a []Value) Value { n := a[0].(int64); seen = append(seen, n); return n%2 == 0 })
			result := Invoke(RootExecution(), NativeMember(values, test.name), []Argument{{"predicate", predicate}})
			if !Equal(result, test.result) || !slices.Equal(seen, test.want) {
				t.Fatalf("result %#v; calls %v", result, seen)
			}
		})
	}
	var seen []int64
	operation := NewFunction([]string{"value"}, "Unit", func(_ *Execution, a []Value) Value { seen = append(seen, a[0].(int64)); return Unit{} })
	Invoke(RootExecution(), NativeMember(values, "for_each"), []Argument{{"operation", operation}})
	if !slices.Equal(seen, []int64{1, 2, 3, 4}) {
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
	original := libraryList("Int", []Value{int64(1), int64(2), int64(3), int64(4)})
	for _, test := range []struct {
		name string
		args []Argument
	}{
		{"set", []Argument{{"index", int64(-1)}, {"value", int64(9)}}},
		{"remove", []Argument{{"index", int64(1)}}},
		{"fill", []Argument{{"value", int64(9)}, {"start", int64(0)}, {"end", int64(4)}}},
		{"copy_within", []Argument{{"target", int64(1)}, {"start", int64(0)}, {"end", int64(3)}}},
		{"reverse_in_place", nil},
		{"slice", []Argument{{"start", int64(0)}, {"end", int64(4)}}},
		{"splice", []Argument{{"start", int64(0)}, {"delete_count", int64(0)}, {"replacement", original}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			value := Invoke(RootExecution(), NativeMember(Clone(original), test.name), test.args)
			if alt, ok := value.(Alternative); ok && alt.Tag == "ok" {
				value = alt.Fields[0]
			}
			result := value.(*List)
			result.Items[0] = int64(99) // model a subsequent builder/native adapter write
			if !Equal(original, libraryList("Int", []Value{int64(1), int64(2), int64(3), int64(4)})) {
				t.Fatal("update shared source storage", original)
			}
		})
	}
	for _, args := range [][]Argument{
		{{"start", int64(-1)}, {"delete_count", int64(0)}, {"replacement", original}},
		{{"start", int64(1)}, {"delete_count", int64(math.MaxInt64)}, {"replacement", original}},
	} {
		if _, ok := recovered(func() { Invoke(RootExecution(), NativeMember(original, "splice"), args) }).(Fault); !ok {
			t.Fatal("invalid splice did not fault")
		}
	}
	if _, ok := recovered(func() {
		Invoke(RootExecution(), NativeMember(original, "set"), []Argument{{"index", int64(math.MinInt64)}, {"value", int64(9)}})
	}).(Fault); !ok {
		t.Fatal("invalid index did not fault")
	}
}

func TestRangeOverflowAndLimits(t *testing.T) {
	for _, test := range []struct {
		start, end, step, max int64
		want                  []Value
	}{
		{math.MaxInt64 - 1, math.MaxInt64, 2, 1, []Value{int64(math.MaxInt64 - 1)}},
		{math.MinInt64 + 1, math.MinInt64, -2, 1, []Value{int64(math.MinInt64 + 1)}},
		{math.MaxInt64, math.MinInt64, math.MinInt64, 2, []Value{int64(math.MaxInt64), int64(-1)}},
		{1, 0, 1, 0, nil},
		{0, 1, -1, 0, nil},
		{0, 0, 1, 0, nil},
	} {
		value := librarySuccess(t, libraryCall(t, "collections/range", test.start, test.end, test.step, test.max)).(*List)
		if value.Type != "@std/List[Int]" || !slices.Equal(value.Items, test.want) {
			t.Fatal(value)
		}
	}
	libraryFailure(t, libraryCall(t, "collections/range", int64(0), int64(math.MaxInt64), int64(1), int64(2)), "LimitExceeded")
	libraryFailure(t, libraryCall(t, "collections/filled", int64(1), int64(-1), int64(2)), "InvalidInput")
}

func TestTextPaddingAndNormalizationBoundaries(t *testing.T) {
	for _, test := range []struct {
		text, padding string
		target, max   int64
		want          string
	}{
		{"x", "é🙂", 4, 9, "é🙂éx"},
		{"x", "é🙂", 3, 7, "é🙂x"},
		{"x", "é🙂", 2, 3, "éx"},
		{"x", "é🙂", 1, 1, "x"},
		{"", "é🙂", 0, 0, ""},
		{"x", "", math.MaxInt64, 1, "x"},
	} {
		got := librarySuccess(t, libraryCall(t, "string/pad_start", test.text, test.target, test.padding, test.max))
		if got != test.want {
			t.Fatal(test, got)
		}
	}
	libraryFailure(t, libraryCall(t, "string/pad_start", "x", int64(math.MaxInt64), "é", int64(3)), "LimitExceeded")
	libraryFailure(t, libraryCall(t, "string/pad_start", "x", int64(2), "🙂", int64(4)), "LimitExceeded")
	libraryFailure(t, libraryCall(t, "string/pad_end", "x", int64(2), " ", int64(-1)), "InvalidInput")
	libraryFailure(t, libraryCall(t, "string/replace_all", "", "", "é", int64(1)), "LimitExceeded")
	if got := librarySuccess(t, libraryCall(t, "string/replace_all", "", "", "é", int64(2))); got != "é" {
		t.Fatal(got)
	}
	// Normalization must enforce output size, even when normalization shrinks input.
	text := strings.Repeat("e\u0301", 3000)
	got := librarySuccess(t, libraryCall(t, "string/normalize", text, "NFC", int64(6000)))
	if got != strings.Repeat("é", 3000) {
		t.Fatal("normalization across chunks")
	}
	libraryFailure(t, libraryCall(t, "string/normalize", text, "NFD", int64(8999)), "LimitExceeded")
}

func TestFloatPrecisionFormatting(t *testing.T) {
	for _, test := range []struct {
		name   string
		value  float64
		digits int64
		want   string
	}{
		{"format_fixed", 1.5, 3, "1.500"},
		{"format_fixed", 2.5, 0, "2"}, // Manuscript's binary64 ties-to-even convention
		{"format_fixed", 1e21, 0, "1e+21"},
		{"format_exponential", 1.5, 3, "1.500e+0"},
		{"format_precision", 1.5, 4, "1.500"},
		{"format_precision", 0, 3, "0.00"},
		{"format_precision", 9.999, 3, "10.0"},
		{"format_precision", 0.000001, 2, "0.0000010"},
		{"format_precision", 0.0000001, 2, "1.0e-7"},
		{"format_precision", math.Inf(1), 2, "Infinity"},
		{"format_exponential", math.Inf(-1), 2, "-Infinity"},
		{"format_fixed", math.NaN(), 2, "NaN"},
		{"format_fixed", math.Copysign(0, -1), 2, "-0.00"},
	} {
		t.Run(test.name+"/"+test.want, func(t *testing.T) {
			got := librarySuccess(t, libraryCall(t, "numbers/"+test.name, test.value, test.digits))
			if got != test.want {
				t.Fatal(got, test.want)
			}
		})
	}
	libraryFailure(t, libraryCall(t, "numbers/format_precision", 1.0, int64(0)), "InvalidInput")
	libraryFailure(t, libraryCall(t, "numbers/format_fixed", 1.0, int64(101)), "InvalidInput")
}

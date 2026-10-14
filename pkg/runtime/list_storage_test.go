package msruntime

import (
	"context"
	"encoding/json"
	"math"
	"os"
	"reflect"
	"runtime"
	"slices"
	"sort"
	"strconv"
	"testing"
)

func TestPrimitiveListConstructorsAndAliases(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	table := []int64{math.MinInt64, 17, math.MaxInt64}
	list := NewIntList("@std/List[Int]", table)
	other := NewIntList(list.Type, table)
	table[1] = 99
	if list.Get(1) != int64(17) || list.Items != nil || list.kind != listInt {
		t.Fatal("constructor shared table or retained boxed storage")
	}
	var alias Value = list
	bound := NativeMemberResult(alias, "append", list.Type)
	for i := int64(0); i < 4096; i++ {
		Invoke(ctx, bound, []Argument{{"value", i}})
	}
	if alias != list || list.Len() != 4099 || other.Len() != 3 {
		t.Fatal("growth stranded alias or shared a fresh evaluation")
	}
	clone := Clone(list).(*List)
	list.Set(0, int64(5))
	if clone.Get(0) != int64(math.MinInt64) || clone.kind != listInt {
		t.Fatal("clone shared outer storage or boxed primitives")
	}
	for _, list := range []*List{
		NewFloatList("@std/List[Float]", []float64{math.SmallestNonzeroFloat64, math.MaxFloat64}),
		NewBoolList("@std/List[Bool]", []bool{true, false}),
		NewStringList("@std/List[String]", []string{"a", "b"}),
	} {
		if list.Items != nil || !Equal(list, NewList(list.Type, list.Boxed())) {
			t.Fatal("primitive storage disagrees with dynamic construction", list.Type)
		}
	}
	for _, values := range [][]Value{{int64(1), "mixed"}, {optional("Int", int64(1), true)}} {
		list := NewList("@std/List[Int]", values)
		if list.kind != listBoxed || !reflect.DeepEqual(list.Items, values) {
			t.Fatal("dynamic fallback lost values")
		}
	}
}

// Ordinary Go slices are the oracle; runtime dispatch is only the subject.
func testPrimitiveListRange[T comparable](t *testing.T, initial []T, create func([]T) *List) {
	t.Helper()
	for _, name := range []string{"write", "prepend", "reverse", "remove", "self_splice", "append", "grow"} {
		t.Run(name, func(t *testing.T) {
			list := create(initial)
			ref := make([]T, len(initial), list.Cap())
			copy(ref, initial)
			var want []T
			for i, value := range ref {
				want = append(want, value)
				if i != 0 {
					continue
				}
				switch name {
				case "write":
					ref[1] = initial[2]
				case "prepend":
					ref = append(ref, initial[0])
					copy(ref[1:], ref[:len(ref)-1])
					ref[0] = initial[2]
				case "reverse":
					slices.Reverse(ref)
				case "remove":
					copy(ref[1:], ref[2:])
					ref = ref[:len(ref)-1]
				case "self_splice":
					copyOfRef := slices.Clone(ref)
					oldLength := len(ref)
					ref = slices.Grow(ref, len(copyOfRef)-1)[:oldLength+len(copyOfRef)-1]
					copy(ref[1+len(copyOfRef):], ref[2:oldLength])
					copy(ref[1:], copyOfRef)
				case "append":
					ref = append(ref, initial[2])
				case "grow":
					for range 100 {
						ref = append(ref, initial[2])
					}
					ref[1] = initial[2]
				}
			}
			ctx := RootExecution()
			defer FinishExecution(ctx)
			var seen []T
			for i, value := range Iterate(list) {
				seen = append(seen, value.(T))
				if i != 0 {
					continue
				}
				var operation string
				var args []Argument
				switch name {
				case "write":
					operation = "set"
					args = []Argument{{"index", int64(1)}, {"value", initial[2]}}
				case "prepend":
					operation = "prepend"
					args = []Argument{{"value", initial[2]}}
				case "reverse":
					operation = "reverse_in_place"
				case "remove":
					operation = "remove"
					args = []Argument{{"index", int64(1)}}
				case "self_splice":
					operation = "splice"
					args = []Argument{{"start", int64(1)}, {"delete_count", int64(1)}, {"replacement", list}}
				case "append":
					operation = "append"
					args = []Argument{{"value", initial[2]}}
				case "grow":
					for range 100 {
						ListAppend(ctx, list, initial[2])
					}
					list.Set(1, initial[2])
					continue
				}
				Invoke(ctx, NativeMember(list, operation), args)
			}
			if !slices.Equal(seen, want) || list.Len() != len(ref) {
				t.Fatalf("captured values %v, want %v; length %d/%d", seen, want, list.Len(), len(ref))
			}
			for i, value := range ref {
				if list.Get(i).(T) != value {
					t.Fatalf("receiver[%d] differs", i)
				}
			}
		})
	}
}

func TestPrimitiveListCapturedGoHeaders(t *testing.T) {
	t.Run("Int", func(t *testing.T) {
		testPrimitiveListRange(t, []int64{1, 2, 3}, func(v []int64) *List { return NewIntList("@std/List[Int]", v) })
	})
	t.Run("Float", func(t *testing.T) {
		testPrimitiveListRange(t, []float64{1.25, 2.5, 3.75}, func(v []float64) *List { return NewFloatList("@std/List[Float]", v) })
	})
	t.Run("Bool", func(t *testing.T) {
		testPrimitiveListRange(t, []bool{true, false, true}, func(v []bool) *List { return NewBoolList("@std/List[Bool]", v) })
	})
	t.Run("String", func(t *testing.T) {
		testPrimitiveListRange(t, []string{"a", "b", "c"}, func(v []string) *List { return NewStringList("@std/List[String]", v) })
	})
}

var primitiveIntSink int64
var primitiveListSink *List

func TestPrimitiveListAccessAllocationsAndCancellation(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	list := NewIntList("@std/List[Int]", []int64{10000, 20000})
	if n := testing.AllocsPerRun(100, func() { primitiveIntSink = ListAtInt(ctx, list, -1).Unwrap(ctx) }); n != 0 {
		t.Fatalf("typed access allocates %g", n)
	}
	if n := testing.AllocsPerRun(100, func() { r := CaptureList(list); primitiveIntSink = r.Int(0) + r.Int(1) }); n != 0 {
		t.Fatalf("typed capture allocates %g", n)
	}
	for _, index := range []int64{math.MinInt64, -3, -2, -1, 0, 1, 2, math.MaxInt64} {
		got := ListAtInt(ctx, list, index)
		if !Equal(got.Box("@std/Optional[Int]"), ListAt(ctx, list, index, "@std/Optional[Int]")) {
			t.Fatal("Optional boundary changed", index)
		}
	}
	fault := recovered(func() { ListAtInt(ctx, list, 2).Unwrap(ctx) })
	if fault.(Fault).Message != recovered(func() { OptionalUnwrap(ctx, ListAt(ctx, list, int64(2), "@std/Optional[Int]")) }).(Fault).Message {
		t.Fatal("none fault changed")
	}
	stopped, cancel := context.WithCancel(ctx.Context)
	cancel()
	child := *ctx
	child.Context = stopped
	for _, call := range []func(){func() { ListAtInt(&child, list, 0) }, func() { IntOptional{1, true}.Unwrap(&child) }, func() { ListAppendInt(&child, list, 1) }} {
		if _, ok := recovered(call).(cancelled); !ok {
			t.Fatal("primitive boundary ignored cancellation")
		}
	}
}

func TestPrimitiveListSortStableAndCallableParity(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	input := NewIntList("@std/List[Int]", []int64{7, 1, 4, 8, 2, 5})
	compare := NewIntCompareFunction([]string{"left", "right"}, "Int", "compare.ms:1:1", func(_ *Execution, a, b int64) int64 { return a%3 - b%3 })
	if got := Invoke(ctx, compare, []Argument{{"right", int64(8)}, {"left", int64(7)}}); got != int64(-1) {
		t.Fatal("ordinary comparator callable changed")
	}
	typed := ListSorted(ctx, input, compare)
	boxed := compare
	boxed.IntCompare = nil
	fallback := ListSorted(ctx, input, boxed)
	if !Equal(typed, fallback) || !slices.Equal(typed.ints, []int64{7, 1, 4, 8, 2, 5}) {
		t.Fatal("stable ties or boxed callback differ")
	}
	typed.Set(0, int64(9))
	if input.Get(0) != int64(7) {
		t.Fatal("sort result shares source backing")
	}
	returning := NewIntCompareFunction([]string{"left", "right"}, "Int", "return.ms:1:1", func(_ *Execution, a, b int64) int64 { Return(a - b); return 0 })
	if returning.IntCompare(ctx, 5, 2) != 3 || returning.Body(ctx, []Value{int64(5), int64(2)}) != int64(3) {
		t.Fatal("typed source return changed")
	}
	floating := NewFloatCompareFunction([]string{"left", "right"}, "Int", "float.ms:1:1", func(_ *Execution, a, b float64) int64 {
		if a < b {
			return -1
		}
		if a > b {
			return 1
		}
		return 0
	})
	floats := ListSorted(ctx, NewFloatList("@std/List[Float]", []float64{3.25, -1.5, 2.75}), floating)
	if !slices.Equal(floats.floats, []float64{-1.5, 2.75, 3.25}) {
		t.Fatal("Float sort narrowed or reordered")
	}
}

func BenchmarkPrimitiveList(b *testing.B) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	table := make([]int64, 65536)
	for i := range table {
		table[i] = int64(i) * 7919 % 100003
	}
	list := NewIntList("@std/List[Int]", table)
	compare := NewIntCompareFunction([]string{"left", "right"}, "Int", "bench.ms:1:1", func(_ *Execution, a, b int64) int64 { return a - b })
	b.Run("Construct64K", func(b *testing.B) {
		for b.Loop() {
			primitiveListSink = NewIntList(list.Type, table)
		}
	})
	b.Run("AtUnwrap64K", func(b *testing.B) {
		for b.Loop() {
			var sum int64
			for i := range table {
				sum = IntAdd(sum, ListAtInt(ctx, list, int64(i)).Unwrap(ctx))
			}
			primitiveIntSink = sum
		}
	})
	b.Run("Sort64K", func(b *testing.B) {
		for b.Loop() {
			primitiveListSink = ListSorted(ctx, list, compare)
		}
	})
}

// A fresh process per kind/count records construction allocations and retained
// storage without scalar-local boxing or compilation/startup timing.
func TestPrimitiveListMemory(t *testing.T) {
	text := os.Getenv("MS_PRIMITIVE_COUNT")
	if text == "" {
		t.Skip("fresh-process memory worker")
	}
	n, err := strconv.Atoi(text)
	if err != nil || n < 1 {
		t.Fatal("invalid count")
	}
	kind := os.Getenv("MS_PRIMITIVE_KIND")
	ctx := RootExecution()
	defer FinishExecution(ctx)
	runtime.GC()
	var before, after, live runtime.MemStats
	runtime.ReadMemStats(&before)
	var list *List
	switch kind {
	case "Int":
		list = NewIntList("@std/List[Int]", nil)
		for i := 0; i < n; i++ {
			ListAppendInt(ctx, list, int64(i%100003))
		}
	case "Float":
		list = NewFloatList("@std/List[Float]", nil)
		for i := 0; i < n; i++ {
			ListAppendFloat(ctx, list, float64(i%100003)+0.25)
		}
	case "Bool":
		list = NewBoolList("@std/List[Bool]", nil)
		for i := 0; i < n; i++ {
			ListAppendBool(ctx, list, i%2 == 0)
		}
	case "String":
		list = NewStringList("@std/List[String]", nil)
		for i := 0; i < n; i++ {
			ListAppendString(ctx, list, "constant")
		}
	default:
		t.Fatal("invalid kind")
	}
	runtime.ReadMemStats(&after)
	if list.Len() != n || list.Items != nil {
		t.Fatal("primitive backing was boxed")
	}
	r := CaptureList(list)
	switch kind {
	case "Int":
		if r.Int(n-1) != int64((n-1)%100003) {
			t.Fatal("Int checksum")
		}
	case "Float":
		if r.Float(n-1) != float64((n-1)%100003)+0.25 {
			t.Fatal("Float checksum")
		}
	case "Bool":
		if r.Bool(n-1) != ((n-1)%2 == 0) {
			t.Fatal("Bool checksum")
		}
	case "String":
		if r.String(n-1) != "constant" {
			t.Fatal("String checksum")
		}
	}
	runtime.GC()
	runtime.ReadMemStats(&live)
	data, err := json.Marshal(map[string]any{"kind": kind, "elements": n, "capacity": list.Cap(), "allocated_bytes": after.TotalAlloc - before.TotalAlloc, "allocations": after.Mallocs - before.Mallocs, "retained_heap_bytes": live.HeapAlloc - before.HeapAlloc, "header_bytes": reflect.TypeOf(*list).Size()})
	if err != nil {
		t.Fatal(err)
	}
	t.Log(string(data))
	runtime.KeepAlive(list)
}

func TestFreshSizedListInitialization(t *testing.T) {
	var result *List
	if n := testing.AllocsPerRun(100, func() {
		list := NewSizedIntList("@std/List[Int]", 4096)
		for i := 0; i < 4096; i++ {
			InitListInt(list, i, int64(i))
		}
		result = FinishListInitialization(list)
	}); n != 2 {
		t.Fatalf("fresh initialization allocates %g, want 2", n)
	}
	if result.Len() != 4096 || result.Get(4095) != int64(4095) {
		t.Fatal("sized contents")
	}
	for _, call := range []func(){func() { InitListInt(result, 0, 9) }, func() { FinishListInitialization(result) }, func() { InitListValue(NewSizedList("@std/List[Int]", 1), 1, int64(7)) }} {
		if _, ok := recovered(call).(Fault); !ok {
			t.Fatal("initialization accepted published or invalid storage")
		}
	}
	list := NewSizedList("@std/List[@std/Optional[Int]]", 2)
	InitListValue(list, 0, optional("Int", int64(1), true))
	InitListValue(list, 1, optional("Int", nil, false))
	FinishListInitialization(list)
	if list.kind != listBoxed || list.Get(0).(Alternative).Fields[0] != int64(1) {
		t.Fatal("generic initializer lost Optional boundary")
	}
}

func TestTypedComparatorGuardParity(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	depth := NewIntCompareFunction([]string{"left", "right"}, "Int", "depth.ms:1:1", func(ctx *Execution, _, _ int64) int64 { return ctx.calls.depth })
	if depth.IntCompare(ctx, 1, 2) != 1 || depth.Body(ctx, []Value{int64(1), int64(2)}) != int64(1) {
		t.Fatal("comparator admission was skipped or doubled")
	}
	previous := sourceProfiling.Swap(true)
	got := depth.IntCompare(ctx, 1, 2)
	sourceProfiling.Store(previous)
	if got != 1 || ctx.calls.depth != 0 {
		t.Fatal("profiling doubled source admission")
	}
	ctx.calls.depth = MaxCallDepth
	failure := recovered(func() { depth.IntCompare(ctx, 1, 2) })
	remaining := ctx.calls.depth
	ctx.calls.depth = 0
	if _, ok := failure.(Fault); !ok || remaining != MaxCallDepth {
		t.Fatal("depth guard did not restore accounting")
	}
	faulting := NewIntCompareFunction([]string{"left", "right"}, "Int", "compare.ms:7:3", func(ctx *Execution, _, _ int64) int64 {
		position := "compare.ms:7:3"
		defer TraceSource(ctx, &position, "compare")
		return IntDivide(1, 0)
	})
	fault := recovered(func() { faulting.IntCompare(ctx, 1, 2) }).(Fault)
	if len(fault.Frames) != 1 || fault.Frames[0] != "compare.ms:7:3 in compare" {
		t.Fatalf("source frame lost: %#v", fault)
	}
	work, cancel := context.WithCancel(ctx.Context)
	child := *ctx
	child.Context = work
	stopping := NewIntCompareFunction([]string{"left", "right"}, "Int", "cancel.ms:1:1", func(*Execution, int64, int64) int64 { cancel(); return 0 })
	if _, ok := recovered(func() { stopping.IntCompare(&child, 1, 2) }).(cancelled); !ok {
		t.Fatal("typed delivery ignored cancellation")
	}
}

func TestPrimitiveNaturalSortAndFloatEdges(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	negativeZero := math.Copysign(0, -1)
	input := NewFloatList("@std/List[Float]", []float64{1, negativeZero, math.NaN(), math.Inf(1), 0, math.Inf(-1), math.NaN()})
	out := ListSorted(ctx, input, nil)
	if !math.IsNaN(out.floats[0]) || !math.IsNaN(out.floats[1]) || out.floats[2] != math.Inf(-1) || !math.Signbit(out.floats[3]) || math.Signbit(out.floats[4]) || out.floats[5] != 1 || out.floats[6] != math.Inf(1) {
		t.Fatal("natural Float edge order or zero bits changed", out.floats)
	}
	if input.floats[0] != 1 {
		t.Fatal("natural sorted mutated input")
	}
	integers := NewIntList("@std/List[Int]", []int64{math.MaxInt64, 0, math.MinInt64})
	if ListSortInPlace(ctx, integers, nil) != integers || !slices.Equal(integers.ints, []int64{math.MinInt64, 0, math.MaxInt64}) {
		t.Fatal("natural Int overflow or identity change")
	}
	booleans := ListSorted(ctx, NewBoolList("@std/List[Bool]", []bool{true, false, true}), nil)
	strings := ListSorted(ctx, NewStringList("@std/List[String]", []string{"z", "α", "a"}), nil)
	if !slices.Equal(booleans.bools, []bool{false, true, true}) || !slices.Equal(strings.strings, []string{"a", "z", "α"}) {
		t.Fatal("natural Bool/String order")
	}
	if _, ok := recovered(func() { ListSorted(ctx, NewList("@std/List[Unit]", []Value{Unit{}}), nil) }).(Fault); !ok {
		t.Fatal("nonprimitive natural sort accepted")
	}
}

func TestListSortInPlaceMutationMatchesGo(t *testing.T) {
	for _, grow := range []bool{false, true} {
		ref := []int64{5, 3, 4, 1, 2}
		captured := ref
		first := true
		sort.SliceStable(captured, func(i, j int) bool {
			left, right := captured[i], captured[j]
			if first {
				first = false
				if grow {
					for range 100 {
						ref = append(ref, 7)
					}
				}
				ref[2] = -4
			}
			return left < right
		})
		for _, typed := range []bool{false, true} {
			ctx := RootExecution()
			list := NewIntList("@std/List[Int]", []int64{5, 3, 4, 1, 2})
			first := true
			body := func(ctx *Execution, left, right int64) int64 {
				if first {
					first = false
					if grow {
						for range 100 {
							ListAppendInt(ctx, list, 7)
						}
					}
					list.Set(2, int64(-4))
				}
				if left < right {
					return -1
				}
				if left > right {
					return 1
				}
				return 0
			}
			compare := NewIntCompareFunction([]string{"left", "right"}, "Int", "mutation.ms:1:1", body)
			if !typed {
				compare.IntCompare = nil
			}
			if ListSortInPlace(ctx, list, compare) != list || !slices.Equal(list.ints, ref) {
				t.Fatalf("grow=%v typed=%v: %v / %v", grow, typed, list.ints, ref)
			}
			FinishExecution(ctx)
		}
	}
	legacy := &List{Type: "@std/List[Int]", Items: []Value{int64(3), int64(1), int64(2)}}
	ctx := RootExecution()
	defer FinishExecution(ctx)
	if got := ListSorted(ctx, legacy, nil); !Equal(got, NewIntList(legacy.Type, []int64{1, 2, 3})) {
		t.Fatal("legacy primitive natural ordering failed")
	}
}

func TestPrimitiveMembershipAllocations(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	values := make([]int64, 4096)
	for i := range values {
		values[i] = int64(i + 10000)
	}
	list := NewIntList("@std/List[Int]", values)
	if n := testing.AllocsPerRun(100, func() {
		if !ListContains(ctx, list, int64(14095), TypeScope{}).(bool) {
			t.Fatal("missing member")
		}
	}); n != 0 {
		t.Fatalf("primitive membership boxes %g cells", n)
	}
	if ListContains(ctx, list, int64(9), TypeScope{}).(bool) {
		t.Fatal("absent member found")
	}
}

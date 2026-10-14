package msruntime

import (
	"context"
	"reflect"
	"testing"
)

func TestForEachUnmarkedArgumentRetention(t *testing.T) {
	for _, source := range []bool{false, true} {
		ctx := RootExecution()
		var retained [][]Value
		body := func(_ *Execution, args []Value) Value { retained = append(retained, args); return Unit{} }
		function := NewFunction([]string{"value"}, "Unit", body)
		if source {
			function = NewSourceFunction(function.Labels, function.Result, "retain.ms:1:1", body)
		}
		if function.BorrowedArguments {
			t.Fatal("arbitrary callback marked as nonretaining")
		}
		listForEach(ctx, NewIntList("@std/List[Int]", []int64{10000, 20000, 30000}), function)
		for i, want := range []int64{10000, 20000, 30000} {
			if len(retained[i]) != 1 || retained[i][0] != want {
				t.Fatal("retained argument array overwritten", retained)
			}
			if i > 0 && &retained[i][0] == &retained[i-1][0] {
				t.Fatal("unmarked callbacks reused argument array")
			}
		}
		FinishExecution(ctx)
	}
}

func TestCompiledForEachReentryAndCopiedCaptures(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	list := NewIntList("@std/List[Int]", []int64{10000, 20000})
	inner := NewIntList("@std/List[Int]", []int64{30000, 40000})
	var function Function
	depth := 0
	var seen []int64
	var saved []Function
	function = NewCompiledSourceFunction([]string{"value"}, "Unit", "reentry.ms:1:1", func(ctx *Execution, args []Value) Value {
		value := args[0] // An individual Value copy may escape; the slice may not.
		seen = append(seen, value.(int64))
		saved = append(saved, NewFunction(nil, "Int", func(*Execution, []Value) Value { return value }))
		if depth == 0 {
			depth++
			listForEach(ctx, inner, function)
			depth--
			if args[0] != value {
				t.Fatal("reentry overwrote outer invocation buffer")
			}
		}
		return Unit{}
	})
	if !function.BorrowedArguments {
		t.Fatal("compiled constructor lost its proof")
	}
	listForEach(ctx, list, function)
	want := []int64{10000, 30000, 40000, 20000, 30000, 40000}
	if !reflect.DeepEqual(seen, want) {
		t.Fatal("reentry order", seen)
	}
	for i, closure := range saved {
		if Invoke(ctx, closure, nil) != want[i] {
			t.Fatal("individual captured Value changed")
		}
	}
	// Mutable reference Values retain their identity after the buffer is reused.
	first := Record{Type: "BorrowedRecord", Fields: map[string]Value{"id": int64(1)}}
	second := Record{Type: first.Type, Fields: map[string]Value{"id": int64(2)}}
	var refs []Value
	copyValues := NewCompiledSourceFunction([]string{"value"}, "Unit", "refs.ms:1:1", func(_ *Execution, args []Value) Value { value := args[0]; refs = append(refs, value); return Unit{} })
	listForEach(ctx, NewList("@std/List[BorrowedRecord]", []Value{first, second}), copyValues)
	SetField(first, "id", int64(9))
	if Field(refs[0], "id") != int64(9) || Field(refs[1], "id") != int64(2) {
		t.Fatal("reference capture lost identity")
	}
}

func TestBorrowedArgumentsRequireExactLabelsAndDropAtAdapters(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	var values []Value
	wrong := NewCompiledSourceFunction([]string{"other"}, "Unit", "labels.ms:1:1", func(_ *Execution, args []Value) Value {
		value := args[0]
		values = append(values, value)
		return Unit{}
	})
	listForEach(ctx, NewIntList("@std/List[Int]", []int64{1, 2}), wrong)
	if !reflect.DeepEqual(values, []Value{nil, nil}) {
		t.Fatal("exact label condition bypassed ordinary Invoke", values)
	}
	marked := NewCompiledSourceFunction([]string{"value"}, "Unit", "wrapped.ms:1:1", func(*Execution, []Value) Value { return Unit{} })
	prepare := NewFunction([]string{"value"}, "Unit", func(*Execution, []Value) Value { return PreparedDefaults{Unit{}} })
	wrapped := WithDefaults(marked, prepare, []int{0}).(Function)
	if wrapped.BorrowedArguments {
		t.Fatal("arbitrary defaults adapter propagated proof")
	}
	native := borrowedNativeFunction{marked}
	if !NativeMemberResult(native, "test", "Unit").(Function).BorrowedArguments {
		t.Fatal("direct native selection replaced the callable")
	}
	if NativeMemberResult(native, "test", "Unit", TypeScope{}).(Function).BorrowedArguments {
		t.Fatal("scoped adapter propagated proof")
	}
}

type borrowedNativeFunction struct{ function Function }

func (n borrowedNativeFunction) Operation(string) Function { return n.function }

func TestCompiledSourceFunctionGuardParity(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	function := NewCompiledSourceFunction(nil, "Int", "compiled.ms:1:1", func(ctx *Execution, _ []Value) Value {
		return ctx.calls.depth.Load()
	})
	if function.Body(ctx, nil) != int64(1) || ctx.calls.depth.Load() != 0 {
		t.Fatal("compiled constructor skipped or doubled admission")
	}
	previous := sourceProfiling.Swap(true)
	got := function.Body(ctx, nil)
	sourceProfiling.Store(previous)
	if got != int64(1) || ctx.calls.depth.Load() != 0 {
		t.Fatal("compiled profiling doubled admission")
	}
	ctx.calls.depth.Store(MaxCallDepth)
	failure := recovered(func() { function.Body(ctx, nil) })
	remaining := ctx.calls.depth.Load()
	ctx.calls.depth.Store(0)
	if _, ok := failure.(Fault); !ok || remaining != MaxCallDepth {
		t.Fatal("compiled constructor depth guard or accounting changed")
	}
	returning := NewCompiledSourceFunction(nil, "Int", "compiled.ms:2:1", func(*Execution, []Value) Value { return Return(int64(42)) })
	if returning.Body(ctx, nil) != int64(42) || ctx.calls.depth.Load() != 0 {
		t.Fatal("compiled source return changed")
	}
	faulting := NewCompiledSourceFunction(nil, "Int", "compiled.ms:3:1", func(ctx *Execution, _ []Value) Value {
		position := "compiled.ms:3:1"
		defer TraceSource(ctx, &position, "compiled")
		return IntDivide(1, 0)
	})
	fault := recovered(func() { faulting.Body(ctx, nil) }).(Fault)
	if len(fault.Frames) != 1 || fault.Frames[0] != "compiled.ms:3:1 in compiled" {
		t.Fatal("compiled fault frame changed", fault)
	}
	work, cancel := context.WithCancel(ctx.Context)
	child := *ctx
	child.Context = work
	stopping := NewCompiledSourceFunction(nil, "Unit", "compiled.ms:4:1", func(*Execution, []Value) Value { cancel(); return Unit{} })
	if _, ok := recovered(func() { stopping.Body(&child, nil) }).(cancelled); !ok {
		t.Fatal("compiled delivery ignored cancellation")
	}
}

type borrowedCancelContext struct {
	context.Context
	checks, cancelAt int
}

func (c *borrowedCancelContext) Err() error {
	c.checks++
	if c.checks >= c.cancelAt {
		return context.Canceled
	}
	return nil
}
func TestBorrowedForEachCancellationCheckpointParity(t *testing.T) {
	for cancelAt := 1; cancelAt <= 5; cancelAt++ {
		var wantChecks, wantCalls int
		var wantFailure reflect.Type
		for _, marked := range []bool{false, true} {
			ctx := RootExecution()
			observed := &borrowedCancelContext{Context: ctx.Context, cancelAt: cancelAt}
			ctx.Context = observed
			calls := 0
			body := func(*Execution, []Value) Value { calls++; return Unit{} }
			fn := NewSourceFunction([]string{"value"}, "Unit", "checkpoint.ms:1:1", body)
			if marked {
				fn = NewCompiledSourceFunction(fn.Labels, fn.Result, "checkpoint.ms:1:1", body)
			}
			failure := recovered(func() { listForEach(ctx, NewIntList("@std/List[Int]", []int64{1, 2}), fn) })
			if !marked {
				wantChecks, wantCalls, wantFailure = observed.checks, calls, reflect.TypeOf(failure)
			} else if observed.checks != wantChecks || calls != wantCalls || reflect.TypeOf(failure) != wantFailure {
				t.Fatalf("checkpoint %d differs: %d/%d/%T versus %d/%d/%v", cancelAt, observed.checks, calls, failure, wantChecks, wantCalls, wantFailure)
			}
			if _, ok := failure.(cancelled); !ok {
				t.Fatal("cancellation was delivered as a value")
			}
			ctx.Context = observed.Context
			FinishExecution(ctx)
		}
	}
}

var borrowedArgumentValueSink Value

func TestBorrowedForEachAllocationControl(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	body := func(_ *Execution, args []Value) Value { borrowedArgumentValueSink = args[0]; return Unit{} }
	fresh := NewSourceFunction([]string{"value"}, "Unit", "alloc.ms:1:1", body)
	marked := NewCompiledSourceFunction(fresh.Labels, fresh.Result, "alloc.ms:1:1", body)
	items := make([]Value, 4096)
	for i := range items {
		items[i] = int64(i + 10000)
	}
	list := &List{Type: "@std/List[Int]", Items: items} // Isolate argument arrays from payload boxing.
	unmarked := testing.AllocsPerRun(100, func() { listForEach(ctx, list, fresh) })
	compiled := testing.AllocsPerRun(100, func() { listForEach(ctx, list, marked) })
	if unmarked != float64(len(items)) || compiled != 1 {
		t.Fatalf("argument array allocations: fresh=%g compiled=%g", unmarked, compiled)
	}
	if empty := testing.AllocsPerRun(100, func() { listForEach(ctx, NewIntList(list.Type, nil), marked) }); empty != 0 {
		t.Fatalf("empty callback boundary allocated %g", empty)
	}
}

func BenchmarkForEachBorrowedArguments(b *testing.B) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	items := make([]Value, 65536)
	ints := make([]int64, len(items))
	for i := range items {
		ints[i] = int64(i) * 7919 % 100003
		items[i] = ints[i]
	}
	boxed := &List{Type: "@std/List[Int]", Items: items}
	typed := NewIntList(boxed.Type, ints)
	body := func(_ *Execution, args []Value) Value { borrowedArgumentValueSink = args[0]; return Unit{} }
	fresh := NewSourceFunction([]string{"value"}, "Unit", "bench.ms:1:1", body)
	marked := NewCompiledSourceFunction(fresh.Labels, fresh.Result, "bench.ms:1:1", body)
	for _, input := range []struct {
		name string
		list *List
	}{{"BoxedBacking", boxed}, {"TypedBacking", typed}} {
		for _, fn := range []struct {
			name     string
			function Function
		}{{"FreshArgs", fresh}, {"BorrowedArgs", marked}} {
			b.Run(input.name+"/"+fn.name, func(b *testing.B) {
				b.ReportAllocs()
				for b.Loop() {
					listForEach(ctx, input.list, fn.function)
				}
			})
		}
	}
}

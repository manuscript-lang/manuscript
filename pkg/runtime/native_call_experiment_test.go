package msruntime

import (
	"context"
	"reflect"
	"testing"
)

// Test-only ABI experiment. It does not alter production execution or select
// numeric representations. A future lowering entry must use checked identities.
func experimentSourceCall[T any](ctx *Execution, result string, body func() T) T {
	if SourceCallNeedsProfile(ctx) {
		return ProfileSourceCall(ctx, result, "experiment.ms:1:1", func(*Execution) T { return body() })
	}
	return SourceCall(ctx, result, func(*Execution) T { return body() })
}

var experimentBoxedAdd = NewSourceFunction([]string{"left", "right"}, "Int", "experiment.ms:1:1", func(ctx *Execution, args []Value) Value {
	position := "experiment.ms:1:1"
	defer TraceSource(ctx, &position, "add")
	return IntAdd(IntValue(args[0]), SourceAt(&position, "experiment.ms:1:41", IntValue(args[1])))
})

func experimentTypedAdd(ctx *Execution, left, right int64) int64 {
	return experimentSourceCall(ctx, "Int", func() int64 {
		position := "experiment.ms:1:1"
		defer TraceSource(ctx, &position, "add")
		return IntAdd(left, SourceAt(&position, "experiment.ms:1:41", right))
	})
}

func TestNativeCallExperimentParity(t *testing.T) {
	defer sourceProfiling.Store(false)
	for _, profiling := range []bool{false, true} {
		sourceProfiling.Store(profiling)
		ctx := RootExecution()
		if got, want := experimentTypedAdd(ctx, 1024, 2048), experimentBoxedAdd.Body(ctx, []Value{int64(1024), int64(2048)}); got != want {
			t.Fatalf("profiling=%v: got %v want %v", profiling, got, want)
		}
		FinishExecution(ctx)
	}
	sourceProfiling.Store(false)
	// The topology must enter one source-call depth, not guard an already
	// guarded native entry from a first-class wrapper.
	boundaryCtx := RootExecution()
	for _, boxed := range []bool{false, true} {
		body := func() int64 {
			if got := boundaryCtx.calls.depth.Load(); got != 1 {
				t.Fatalf("boxed=%v depth=%d", boxed, got)
			}
			return 1
		}
		if boxed {
			NewSourceFunction(nil, "Int", "experiment.ms:1:1", func(*Execution, []Value) Value { return body() }).Body(boundaryCtx, nil)
		} else {
			experimentSourceCall(boundaryCtx, "Int", body)
		}
		if boundaryCtx.calls.depth.Load() != 0 {
			t.Fatal("boundary did not unwind")
		}
	}
	FinishExecution(boundaryCtx)
	for _, boxed := range []bool{false, true} {
		ctx := RootExecution()
		var cancel context.CancelFunc
		ctx.Context, cancel = context.WithCancel(ctx.Context)
		cancel()
		entered := false
		body := func() int64 { entered = true; return 1 }
		failure := experimentFailure(func() {
			if boxed {
				NewSourceFunction(nil, "Int", "experiment.ms:1:1", func(*Execution, []Value) Value { return body() }).Body(ctx, nil)
			} else {
				experimentSourceCall(ctx, "Int", body)
			}
		})
		if _, ok := failure.(cancelled); !ok || entered || ctx.calls.depth.Load() != 0 {
			t.Fatalf("boxed=%v cancelled admission: failure=%#v entered=%v depth=%d", boxed, failure, entered, ctx.calls.depth.Load())
		}
		FinishExecution(ctx)
	}
	for _, returned := range []bool{false, true} {
		ctx := RootExecution()
		var cancel context.CancelFunc
		ctx.Context, cancel = context.WithCancel(ctx.Context)
		failure := experimentFailure(func() {
			experimentSourceCall(ctx, "Int", func() int64 {
				cancel()
				if returned {
					Return(int64(1))
				}
				return 1
			})
		})
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("delivery: %T %v", failure, failure)
		}
		if ctx.calls.depth.Load() != 0 {
			t.Fatal("call depth leaked")
		}
		FinishExecution(ctx)
	}
	ctx := RootExecution()
	defer FinishExecution(ctx)
	got := experimentSourceCall[Value](ctx, "@std/Result[Int][String]", func() Value {
		return Try(Alternative{Type: "@std/Result[Int][String]", Tag: "error", Fields: []Value{"bad"}})
	})
	want := NewSourceFunction(nil, "@std/Result[Int][String]", "experiment.ms:1:1", func(*Execution, []Value) Value {
		return Try(Alternative{Type: "@std/Result[Int][String]", Tag: "error", Fields: []Value{"bad"}})
	}).Body(ctx, nil)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("propagation: got %#v want %#v", got, want)
	}
	ctx.calls.depth.Store(MaxCallDepth)
	failure := experimentFailure(func() { experimentTypedAdd(ctx, 1, 1) })
	if _, ok := failure.(Fault); !ok {
		t.Fatalf("depth limit: %T %v", failure, failure)
	}
	if ctx.calls.depth.Load() != MaxCallDepth {
		t.Fatal("failed admission changed depth")
	}
	ctx.calls.depth.Store(0)
	// Ordinary faults must not be replaced by a cancellation arriving in the
	// body. Cleanup and trace defers execute inside the source boundary.
	var cancel context.CancelFunc
	ctx.Context, cancel = context.WithCancel(ctx.Context)
	cleaned := false
	failure = experimentFailure(func() {
		experimentSourceCall(ctx, "Int", func() int64 {
			position := "experiment.ms:2:7"
			defer TraceSource(ctx, &position, "fault")
			defer func() { cleaned = true }()
			cancel()
			Panic("original")
			return 0
		})
	})
	fault, ok := failure.(Fault)
	if !ok || fault.Message != "original" || !reflect.DeepEqual(fault.Frames, []string{"experiment.ms:2:7 in fault"}) || !cleaned {
		t.Fatalf("fault/cleanup changed: %#v cleaned=%v", failure, cleaned)
	}
	if ctx.calls.depth.Load() != 0 {
		t.Fatal("fault leaked depth")
	}
}

func experimentFailure(body func()) (failure any) {
	defer func() { failure = recover() }()
	body()
	return
}

var experimentResult Value
var experimentNativeResult int64

func BenchmarkNativeCallExperiment(b *testing.B) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	b.Run("PreparedBody", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			experimentResult = experimentBoxedAdd.Body(ctx, []Value{int64(1024), int64(2048)})
		}
	})
	b.Run("TypedGuarded", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			experimentNativeResult = experimentTypedAdd(ctx, 1024, 2048)
		}
	})
}

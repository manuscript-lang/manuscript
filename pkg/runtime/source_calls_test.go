package msruntime

import (
	"context"
	"fmt"
	"reflect"
	"testing"
)

func sourceFailure(body func()) (failure any) { defer func() { failure = recover() }(); body(); return }

func TestSourceCallSingleGuard(t *testing.T) {
	for _, mode := range []string{"native", "boxed", "direct", "bound"} {
		t.Run(mode, func(t *testing.T) {
			ctx := RootExecution()
			defer FinishExecution(ctx)
			body := func(ctx *Execution) int64 {
				if ctx.calls.depth.Load() != 1 {
					panic(fmt.Sprintf("depth %d", ctx.calls.depth.Load()))
				}
				return 1024
			}
			var got Value
			switch mode {
			case "native":
				got = SourceCall(ctx, "Int", body)
			case "boxed":
				got = NewSourceFunction(nil, "Int", "guard.ms:1", func(ctx *Execution, _ []Value) Value { return body(ctx) }).Body(ctx, nil)
			case "direct":
				got = SourceDirect("guard.ms:1", "Int", func(ctx *Execution, _ Value, _ []Value) Value { return body(ctx) })(ctx, nil, nil)
			case "bound":
				got = BoundDirect(nil, nil, "Int", SourceDirect("guard.ms:1", "Int", func(ctx *Execution, _ Value, _ []Value) Value { return body(ctx) })).Body(ctx, nil)
			}
			if got != int64(1024) || ctx.calls.depth.Load() != 0 {
				t.Fatalf("value/depth: %v/%d", got, ctx.calls.depth.Load())
			}
		})
	}
}

func TestSourceCallReturnPropagationCancellation(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	if got := SourceCall(ctx, "Int", func(*Execution) int64 { Return(int64(1000)); return 0 }); got != 1000 {
		t.Fatal(got)
	}
	if got := SourceCall[Value](ctx, "Unit", func(*Execution) Value { return Return(nil) }); got != nil {
		t.Fatal(got)
	}
	cause := "cause"
	got := SourceCall[Value](ctx, "@std/Result[Int][String]", func(*Execution) Value {
		return Try(Alternative{Type: "@std/Result[Int][String]", Tag: "error", Fields: []Value{cause}})
	})
	if !reflect.DeepEqual(got, Alternative{Type: "@std/Result[Int][String]", Tag: "error", Fields: []Value{cause}}) {
		t.Fatal(got)
	}
	for _, returned := range []bool{false, true} {
		execution := RootExecution()
		var cancel context.CancelFunc
		execution.Context, cancel = context.WithCancel(execution.Context)
		failure := sourceFailure(func() {
			SourceCall(execution, "Int", func(*Execution) int64 {
				cancel()
				if returned {
					Return(int64(1000))
				}
				return 1000
			})
		})
		if _, ok := failure.(cancelled); !ok || execution.calls.depth.Load() != 0 {
			t.Fatalf("cancel/depth %v/%d", failure, execution.calls.depth.Load())
		}
		FinishExecution(execution)
	}
	cancelledExecution := RootExecution()
	defer FinishExecution(cancelledExecution)
	cancelledExecution.Context = context.Background()
	var cancel context.CancelFunc
	cancelledExecution.Context, cancel = context.WithCancel(cancelledExecution.Context)
	cancel()
	entered := false
	failure := sourceFailure(func() { SourceCall(cancelledExecution, "Int", func(*Execution) int64 { entered = true; return 1 }) })
	if _, ok := failure.(cancelled); !ok || entered || cancelledExecution.calls.depth.Load() != 0 {
		t.Fatalf("admission %v entered %v", failure, entered)
	}
}

func TestSourceCallDepthUnwinds(t *testing.T) {
	for _, boxed := range []bool{false, true} {
		ctx := RootExecution()
		var native func(*Execution) int64
		var function Function
		if boxed {
			function = NewSourceFunction(nil, "Int", "depth.ms:1", func(ctx *Execution, _ []Value) Value { return function.Body(ctx, nil) })
		} else {
			native = func(ctx *Execution) int64 { return SourceCall(ctx, "Int", native) }
		}
		failure := sourceFailure(func() {
			if boxed {
				function.Body(ctx, nil)
			} else {
				native(ctx)
			}
		})
		fault, ok := failure.(Fault)
		if !ok || fault.Message != fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth) || ctx.calls.depth.Load() != 0 {
			t.Fatalf("depth fault %v depth %d", failure, ctx.calls.depth.Load())
		}
		FinishExecution(ctx)
	}
}

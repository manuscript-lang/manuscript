package msruntime

import (
	"context"
	"math"
	"reflect"
	"sync/atomic"
	"testing"
)

type sourceObservedContext struct {
	context.Context
	observations atomic.Int32
}

func (c *sourceObservedContext) Err() error {
	c.observations.Add(1)
	return c.Context.Err()
}

func TestSourceCallSingleBoundary(t *testing.T) {
	defer sourceProfiling.Store(false)
	for _, profiling := range []bool{false, true} {
		sourceProfiling.Store(profiling)
		for _, mode := range []string{"native", "boxed", "direct", "bound"} {
			ctx := RootExecution()
			observed := &sourceObservedContext{Context: ctx.Context}
			ctx.Context = observed
			entered := 0
			body := func(execution *Execution) int64 {
				entered++
				if execution.calls != ctx.calls || execution.calls.depth.Load() != 1 {
					t.Fatalf("profiling=%v %s: body changed call accounting", profiling, mode)
				}
				position := "boundary.ms:2:9"
				defer TraceSource(execution, &position, "one")
				return 7
			}
			run := func() Value {
				if mode == "native" {
					if SourceCallNeedsProfile(ctx) {
						return ProfileSourceCall(ctx, "Int", "boundary.ms:1:1", body)
					}
					return SourceCall(ctx, "Int", body)
				}
				if mode == "boxed" {
					return NewSourceFunction(nil, "Int", "boundary.ms:1:1", func(execution *Execution, _ []Value) Value { return body(execution) }).Body(ctx, nil)
				}
				direct := SourceDirect("boundary.ms:1:1", "Int", func(execution *Execution, _ Value, _ []Value) Value { return body(execution) })
				if mode == "bound" {
					return BoundDirect(nil, nil, "Int", direct).Body(ctx, nil)
				}
				return direct(ctx, nil, nil)
			}
			if got := run(); got != int64(7) || entered != 1 || observed.observations.Load() != 2 || ctx.calls.depth.Load() != 0 {
				t.Fatalf("profiling=%v %s: value=%v entered=%d observations=%d depth=%d", profiling, mode, got, entered, observed.observations.Load(), ctx.calls.depth.Load())
			}
			var cancel context.CancelFunc
			observed.Context, cancel = context.WithCancel(observed.Context)
			cancel()
			if failure := experimentFailure(func() { run() }); reflect.TypeOf(failure) != reflect.TypeOf(cancelled{}) || entered != 1 || ctx.calls.depth.Load() != 0 {
				t.Fatalf("profiling=%v %s: cancelled admission changed: %#v entered=%d", profiling, mode, failure, entered)
			}
			FinishExecution(ctx)
		}
	}
}

func TestSourceCallNativeBoxedFaultParity(t *testing.T) {
	defer sourceProfiling.Store(false)
	for _, profiling := range []bool{false, true} {
		sourceProfiling.Store(profiling)
		var expected any
		for _, boxed := range []bool{false, true} {
			ctx := RootExecution()
			body := func(execution *Execution) int64 {
				position := "overflow.ms:3:20"
				defer TraceSource(execution, &position, "overflow")
				return IntAdd(math.MaxInt64, 1)
			}
			failure := experimentFailure(func() {
				if boxed {
					NewSourceFunction(nil, "Int", "overflow.ms:1:1", func(execution *Execution, _ []Value) Value { return body(execution) }).Body(ctx, nil)
				} else {
					if SourceCallNeedsProfile(ctx) {
						ProfileSourceCall(ctx, "Int", "overflow.ms:1:1", body)
					} else {
						SourceCall(ctx, "Int", body)
					}
				}
			})
			fault, ok := failure.(Fault)
			if !ok || !reflect.DeepEqual(fault.Frames, []string{"overflow.ms:3:20 in overflow"}) || ctx.calls.depth.Load() != 0 {
				t.Fatalf("overflow boundary changed: %#v", failure)
			}
			if boxed && !reflect.DeepEqual(failure, expected) {
				t.Fatalf("profiling=%v: boxed fault=%#v native=%#v", profiling, failure, expected)
			}
			expected = failure
			FinishExecution(ctx)
		}
	}
}

func TestSourceCallActualRecursionUnwinds(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	entered := 0
	var recurse func(*Execution) int64
	recurse = func(execution *Execution) int64 {
		return SourceCall(execution, "Int", func(execution *Execution) int64 {
			entered++
			return recurse(execution)
		})
	}
	if failure := experimentFailure(func() { recurse(ctx) }); failure == nil || entered != MaxCallDepth || ctx.calls.depth.Load() != 0 || ctx.calls.traceFull.Load() {
		t.Fatalf("actual recursion failed to unwind: failure=%#v entered=%d depth=%d", failure, entered, ctx.calls.depth.Load())
	}
	if got := SourceCall(ctx, "Int", func(*Execution) int64 { return 7 }); got != 7 || ctx.calls.depth.Load() != 0 {
		t.Fatal("execution could not call after recursion failure")
	}
	entered = 0
	var boxed Function
	boxed = NewSourceFunction(nil, "Int", "recursive.ms:1:1", func(execution *Execution, _ []Value) Value {
		entered++
		return boxed.Body(execution, nil)
	})
	failure := experimentFailure(func() { boxed.Body(ctx, nil) })
	if _, ok := failure.(Fault); !ok || entered != MaxCallDepth || ctx.calls.depth.Load() != 0 || ctx.calls.traceFull.Load() {
		t.Fatalf("boxed recursion failed to unwind: failure=%#v entered=%d depth=%d", failure, entered, ctx.calls.depth.Load())
	}
}

func TestSourceCallBoxedNilReturn(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	fn := NewSourceFunction(nil, "Unit", "nil.ms:1:1", func(*Execution, []Value) Value { return Return(nil) })
	if value := fn.Body(ctx, nil); value != nil || ctx.calls.depth.Load() != 0 {
		t.Fatal("boxed nil source return changed", value)
	}
}

func TestCallMethodSourceBoundary(t *testing.T) {
	defer sourceProfiling.Store(false)
	for _, profiling := range []bool{false, true} {
		sourceProfiling.Store(profiling)
		ctx := RootExecution()
		observed := &sourceObservedContext{Context: ctx.Context}
		ctx.Context = observed
		entered := 0
		direct := SourceDirect("method.ms:2:1", "Int", func(execution *Execution, _ Value, _ []Value) Value {
			entered++
			if execution.calls.depth.Load() != 1 {
				t.Fatal("method acquired another depth guard")
			}
			return int64(7)
		})
		typ := "source-boundary/Probe"
		Register(Implementation{Receiver: typ, Contract: "source-boundary/Call", Name: "probe", Scope: "method.ms", Direct: direct, DirectGuarded: true,
			Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
				return BoundDirect(receiver, nil, "Int", direct)
			}})
		var site MethodSite
		for _, hot := range []bool{false, true} {
			observed.observations.Store(0)
			if got := CallMethod(ctx, &site, Record{Type: typ}, "source-boundary/Call", "probe", TypeScope{Module: "method.ms"}, nil); got != int64(7) || observed.observations.Load() != 2 || ctx.calls.depth.Load() != 0 {
				t.Fatalf("profiling=%v hot=%v: value=%v observations=%d depth=%d", profiling, hot, got, observed.observations.Load(), ctx.calls.depth.Load())
			}
		}
		var cancel context.CancelFunc
		observed.Context, cancel = context.WithCancel(observed.Context)
		cancel()
		for _, cached := range []bool{false, true} {
			if !cached {
				site = MethodSite{}
			}
			before := entered
			failure := experimentFailure(func() {
				CallMethod(ctx, &site, Record{Type: typ}, "source-boundary/Call", "probe", TypeScope{Module: "method.ms"}, nil)
			})
			if _, ok := failure.(cancelled); !ok || entered != before || ctx.calls.depth.Load() != 0 {
				t.Fatalf("profiling=%v cached=%v: failed admission=%#v entered=%d", profiling, cached, failure, entered)
			}
		}
		FinishExecution(ctx)
	}
}

func TestCallMethodUnguardedAdmission(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	entered := 0
	typ := "router-admission/Probe"
	Register(Implementation{Receiver: typ, Contract: "router-admission/Call", Name: "probe", Scope: "router.ms", Direct: func(*Execution, Value, []Value) Value { entered++; return int64(1) }})
	var hot MethodSite
	if got := CallMethod(ctx, &hot, Record{Type: typ}, "router-admission/Call", "probe", TypeScope{Module: "router.ms"}, nil); got != int64(1) {
		t.Fatal(got)
	}
	var cancel context.CancelFunc
	ctx.Context, cancel = context.WithCancel(ctx.Context)
	cancel()
	var cold MethodSite
	for _, site := range []*MethodSite{&cold, &hot} {
		failure := experimentFailure(func() {
			CallMethod(ctx, site, Record{Type: typ}, "router-admission/Call", "probe", TypeScope{Module: "router.ms"}, nil)
		})
		if _, ok := failure.(cancelled); !ok || entered != 1 {
			t.Fatalf("unguarded registration lost admission: failure=%#v entered=%d", failure, entered)
		}
	}
}

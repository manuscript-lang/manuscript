package msruntime

import "fmt"

// Direct source functions are emitted as ordinary Go functions that call Enter
// on entry and defer Leave. Together they carry what NewSourceFunction and
// TraceSource provide around a dynamic call: cancellation, the call-depth
// limit, fault frames, and cancellation delivery after the body returns.

// Enter admits one nested source call.
func Enter(ctx *Execution) {
	if ctx == nil {
		return
	}
	if isDone(ctx.Context) {
		panic(cancelled{})
	}
	if calls := ctx.calls; calls != nil {
		if calls.depth++; calls.depth > MaxCallDepth {
			calls.depth--
			Panic(fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth))
		}
	}
}

// Leave runs once per direct source function, after its cleanup has completed.
func Leave(ctx *Execution, position *string, name string) {
	if ctx == nil {
		if failure := recover(); failure != nil {
			panic(appendFrame(nil, failure, position, name))
		}
		return
	}
	calls := ctx.calls
	var failure any
	traceFull := calls != nil && calls.traceFull
	if !traceFull {
		failure = recover()
	}
	if failure != nil {
		failure = appendFrame(ctx, failure, position, name)
	}
	if calls != nil {
		if calls.depth--; calls.depth == 0 {
			calls.traceFull = false
		}
	}
	if failure != nil {
		panic(failure)
	}
	// A still-unwinding fault with full frames is not recovered above, so
	// delivery is only checked on a normal return.
	if !traceFull && isDone(ctx.Context) {
		panic(cancelled{})
	}
}

func appendFrame(ctx *Execution, failure any, position *string, name string) any {
	fault, ok := failure.(Fault)
	if !ok {
		return failure
	}
	fault.Frames = append(append([]string{}, fault.Frames...), *position+" in "+name)
	if len(fault.Frames) >= maxFaultFrames && ctx != nil && ctx.calls != nil {
		// Re-raising at every frame makes unwinding a deep stack quadratic, so
		// outer frames are no longer recorded.
		fault.Truncated = true
		ctx.calls.traceFull = true
	}
	return fault
}

// ControlResult turns a propagation or source-return panic raised inside a
// direct function into that function's result. Other panics are not handled.
func ControlResult(ctx *Execution, failure any, result string) (Value, bool) {
	switch c := failure.(type) {
	case sourceReturn:
		controlPanics.Add(-1)
		return c.value, true
	case propagation:
		controlPanics.Add(-1)
		CheckCancelled(ctx)
		return Alternative{Type: result, Tag: "error", Fields: []Value{c.Cause}}, true
	}
	return nil, false
}

// ControlPending reports whether a propagation, source-return or loop-exit
// panic may be in flight, so unwinding layers can skip recover otherwise.
func ControlPending() bool { return controlPanics.Load() != 0 }

// NewDirectFunction wraps a direct source function for dynamic calls. The
// direct function already enters and leaves its own frame.
func NewDirectFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	return Function{Labels: labels, Result: result, Body: func(ctx *Execution, args []Value) Value {
		if sourceProfiling.Load() {
			return profileSource(ctx, position, args, body)
		}
		return body(ctx, args)
	}}
}

// Poll checks cancellation on every 64th call, for loops whose iterations
// make no checked call of their own.
// PollIndex is Poll for range loops, which already count their iterations.
func PollIndex(ctx *Execution, index int) {
	if index&63 == 63 {
		CheckCancelled(ctx)
	}
}

func Poll(ctx *Execution, tick *uint32) {
	if *tick++; *tick&63 == 0 {
		CheckCancelled(ctx)
	}
}

// NewCompiledDirectFunction is compiler proof that the wrapper copies its
// argument Values into direct parameters and never retains the incoming slice.
func NewCompiledDirectFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	f := NewDirectFunction(labels, result, position, body)
	f.BorrowedArguments = true
	return f
}

// Direct comparators already own Enter/Leave; attaching a typed entry must not
// add a second guard. Profiled calls retain the ordinary boxed wrapper.
func WithDirectIntCompare(f Function, body func(*Execution, int64, int64) int64) Function {
	f.IntCompare = func(ctx *Execution, a, b int64) int64 {
		if sourceProfiling.Load() {
			return f.Body(ctx, []Value{a, b}).(int64)
		}
		return body(ctx, a, b)
	}
	return f
}
func WithDirectFloatCompare(f Function, body func(*Execution, float64, float64) int64) Function {
	f.FloatCompare = func(ctx *Execution, a, b float64) int64 {
		if sourceProfiling.Load() {
			return f.Body(ctx, []Value{a, b}).(int64)
		}
		return body(ctx, a, b)
	}
	return f
}

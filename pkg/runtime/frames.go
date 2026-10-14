package msruntime

import (
	"fmt"
	"reflect"
	goruntime "runtime"
	"strconv"
	"sync"
)

// maxFaultFrames bounds the trace kept on a fault; deeper frames are counted.
const maxFaultFrames = 32

// Direct source functions are emitted as ordinary Go functions. A function in
// a recursive cycle of direct calls admits itself with Enter and leaves with
// Exit, which carry the call-depth limit and a periodic cancellation check;
// other direct functions emit nothing around their body. Fault frames are not
// recorded while unwinding: a Fault captures the Go stack where it is raised
// and names its source frames from the functions registered below.

// Enter admits one nested call of a function in a recursive cycle. The common
// path inlines; every 256th call checks the depth limit and cancellation, so
// the limit can be overshot by that many frames.
func Enter(ctx *Execution) {
	calls := ctx.calls
	calls.depth++
	if calls.ticks++; calls.ticks == 0 {
		enterSlow(ctx)
	}
}

func enterSlow(ctx *Execution) {
	calls := ctx.calls
	if calls.depth > MaxCallDepth {
		calls.depth--
		Panic(fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth))
	}
	if isDone(ctx.Context) {
		calls.depth--
		panic(cancelled{})
	}
}

// Exit pairs with Enter on a normal return. A panic unwinds past it; the code
// that recovers restores the depth it saw (see Depth and ControlResult).
func Exit(ctx *Execution) { ctx.calls.depth-- }

// Depth reports the current call depth, for code that recovers a panic.
func Depth(ctx *Execution) int64 {
	if ctx == nil || ctx.calls == nil {
		return 0
	}
	return ctx.calls.depth
}

// sourceNames maps the Go name of a source function to the name its frames
// show; sourcePointers records which code pointers are already named.
var (
	sourceNames    sync.Map
	sourcePointers sync.Map
)

func goFunctionName(fn any) (uintptr, string) {
	pointer := reflect.ValueOf(fn).Pointer()
	if f := goruntime.FuncForPC(pointer); f != nil {
		return pointer, f.Name()
	}
	return pointer, ""
}

// RegisterSource names a direct source function in fault traces.
func RegisterSource(fn any, name string) {
	if _, key := goFunctionName(fn); key != "" {
		sourceNames.Store(key, name)
	}
}

// Named names a source function body in fault traces and returns it.
func Named(name string, body func(*Execution, []Value) Value) func(*Execution, []Value) Value {
	pointer := reflect.ValueOf(body).Pointer()
	if _, seen := sourcePointers.Load(pointer); !seen {
		if _, key := goFunctionName(body); key != "" {
			sourceNames.Store(key, name)
		}
		sourcePointers.Store(pointer, true)
	}
	return body
}

// NamedMethod is Named for the receiver-first bodies of implementations.
func NamedMethod(name string, body func(*Execution, Value, []Value) Value) func(*Execution, Value, []Value) Value {
	pointer := reflect.ValueOf(body).Pointer()
	if _, seen := sourcePointers.Load(pointer); !seen {
		if _, key := goFunctionName(body); key != "" {
			sourceNames.Store(key, name)
		}
		sourcePointers.Store(pointer, true)
	}
	return body
}

// captureFrames names the registered source functions on the current stack,
// innermost first, as "file:line in name". The file and line come from the
// source directives of the generated Go, so they are statement positions.
func captureFrames() (frames []string, truncated bool) {
	var pcs [128]uintptr
	n := goruntime.Callers(2, pcs[:])
	iterator := goruntime.CallersFrames(pcs[:n])
	for {
		frame, more := iterator.Next()
		if name, ok := sourceNames.Load(frame.Function); ok {
			if len(frames) == maxFaultFrames {
				return frames, true
			}
			frames = append(frames, frame.File+":"+strconv.Itoa(frame.Line)+" in "+name.(string))
		}
		if !more {
			break
		}
	}
	return frames, n == len(pcs)
}

// ControlResult turns a propagation or source-return panic raised inside a
// direct function into that function's result. Other panics are not handled.
func ControlResult(ctx *Execution, depth int64, failure any, result string) (Value, bool) {
	switch c := failure.(type) {
	case sourceReturn:
		controlPanics.Add(-1)
		restoreDepth(ctx, depth)
		return c.value, true
	case propagation:
		controlPanics.Add(-1)
		restoreDepth(ctx, depth)
		CheckCancelled(ctx)
		return Alternative{Type: result, Tag: "error", Fields: []Value{c.Cause}}, true
	}
	return nil, false
}

func restoreDepth(ctx *Execution, depth int64) {
	if ctx != nil && ctx.calls != nil {
		ctx.calls.depth = depth
	}
}

// ControlPending reports whether a propagation, source-return or loop-exit
// panic may be in flight, so unwinding layers can skip recover otherwise.
func ControlPending() bool { return controlPanics.Load() != 0 }

// NewDirectFunction wraps a direct source function for dynamic calls. The
// direct function already enters and leaves its own frame.
func NewDirectFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	return Function{Labels: labels, Result: result, Body: func(ctx *Execution, args []Value) Value {
		// The wrapper counts depth: a cycle through dynamic calls is bounded here.
		Enter(ctx)
		var value Value
		if sourceProfiling.Load() {
			value = profileSource(ctx, position, args, body)
		} else {
			value = body(ctx, args)
		}
		Exit(ctx)
		return value
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

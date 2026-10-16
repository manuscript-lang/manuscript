package msruntime

import (
	"reflect"
	goruntime "runtime"
	"strconv"
	"sync"
	"sync/atomic"
)

// MaxCallDepth bounds nested calls of functions in a recursive cycle.
const MaxCallDepth = 200000

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
		Raise("call depth limit exceeded (" + strconv.Itoa(MaxCallDepth) + " nested calls)")
	}
	if isDone(ctx.Context) {
		calls.depth--
		panic(cancelled{})
	}
}

// Exit pairs with Enter on a normal return. A panic unwinds past it; the code
// that recovers restores the depth it saw (see Depth and RestoreDepth).
func Exit(ctx *Execution) { ctx.calls.depth-- }

// Depth reports the current call depth, for code that recovers a panic.
func Depth(ctx *Execution) int {
	if ctx == nil || ctx.calls == nil {
		return 0
	}
	return ctx.calls.depth
}

// RestoreDepth resets the call depth to a value read earlier with Depth.
func RestoreDepth(ctx *Execution, depth int) {
	if ctx != nil && ctx.calls != nil {
		ctx.calls.depth = depth
	}
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

// RegisterSource names a direct source function in fault traces. The argument
// is used only for its code pointer; it is not a value ABI.
func RegisterSource(fn any, name string) {
	if _, key := goFunctionName(fn); key != "" {
		sourceNames.Store(key, name)
	}
}

// NamedFunc names a function literal in fault traces and returns it.
func NamedFunc[F any](name string, fn F) F {
	pointer := reflect.ValueOf(fn).Pointer()
	if _, seen := sourcePointers.Load(pointer); !seen {
		if _, key := goFunctionName(fn); key != "" {
			sourceNames.Store(key, name)
		}
		sourcePointers.Store(pointer, true)
	}
	return fn
}

// Site records that the code of one lambda expression is already registered,
// so evaluating the expression again costs one atomic load.
type Site struct{ done atomic.Bool }

// Named names a lambda in fault traces on first evaluation and returns it.
func Named[F any](site *Site, name string, fn F) F {
	if !site.done.Load() {
		NamedFunc(name, fn)
		site.done.Store(true)
	}
	return fn
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

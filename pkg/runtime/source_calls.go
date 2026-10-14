package msruntime

import "fmt"

// SourceCall is the single source boundary used by native entries and boxed
// adapters. The body is unguarded and owns its source trace and cleanup defers.
// T must use the same dynamic representation as its checked Value boundary.
func SourceCall[T any](ctx *Execution, result string, body func(*Execution) T) (value T) {
	CheckCancelled(ctx)
	if ctx != nil && ctx.calls != nil {
		calls := ctx.calls
		if calls.depth.Add(1) > MaxCallDepth {
			calls.depth.Add(-1)
			Panic(fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth))
		}
		defer func() {
			if calls.depth.Add(-1) == 0 {
				calls.traceFull.Store(false)
			}
		}()
	}
	completed := false
	defer func() {
		if controlPanics.Load() != 0 {
			if failure := recover(); failure != nil {
				switch failure := failure.(type) {
				case sourceReturn:
					controlPanics.Add(-1)
					// A boxed runtime callback may return nil. Preserve that Value
					// without accepting nil as a typed scalar representation.
					if failure.value == nil {
						var zero T
						if any(zero) == nil {
							value, completed = zero, true
							break
						}
					}
					value = any(failure.value).(T)
					completed = true
				case propagation:
					controlPanics.Add(-1)
					CheckCancelled(ctx)
					value = any(Alternative{Type: result, Tag: "error", Fields: []Value{failure.Cause}}).(T)
					return
				default:
					panic(failure)
				}
			}
		}
		if completed && ctx != nil && ctx.Context.Err() != nil {
			panic(cancelled{})
		}
	}()
	value = body(ctx)
	completed = true
	return value
}

// Keep the boxed adapter in the runtime package: cross-package inlining can
// otherwise make the generic guard's body closure escape on every call.
//
//go:noinline
func NewSourceFunction(labels []string, result, position string, body func(*Execution, []Value) Value) Function {
	return Function{Labels: labels, Result: result, Body: func(ctx *Execution, args []Value) Value {
		if SourceCallNeedsProfile(ctx) {
			return ProfileSourceCall(ctx, result, position, func(ctx *Execution) Value { return body(ctx, args) })
		}
		return SourceCall(ctx, result, func(ctx *Execution) Value { return body(ctx, args) })
	}}
}

package msruntime

import "fmt"

// NewIntCompareFunction keeps an ordinary callable and a typed comparison entry
// on the same value. The supplied body retains generated source tracing/cleanup.
func NewIntCompareFunction(labels []string, result, position string, body func(*Execution, int64, int64) int64) Function {
	f := NewCompiledSourceFunction(labels, result, position, func(ctx *Execution, args []Value) Value {
		return body(ctx, args[0].(int64), args[1].(int64))
	})
	f.IntCompare = sourceComparator(body, f.Body)
	return f
}

func NewFloatCompareFunction(labels []string, result, position string, body func(*Execution, float64, float64) int64) Function {
	f := NewCompiledSourceFunction(labels, result, position, func(ctx *Execution, args []Value) Value {
		return body(ctx, args[0].(float64), args[1].(float64))
	})
	f.FloatCompare = sourceComparator(body, f.Body)
	return f
}

// Keep this wrapper aligned with NewSourceFunction: scalar callbacks still have
// source returns, the depth guard, profiling and entry/delivery cancellation.
func sourceComparator[T any](body func(*Execution, T, T) int64, boxed func(*Execution, []Value) Value) func(*Execution, T, T) int64 {
	return func(ctx *Execution, left, right T) (value int64) {
		if sourceProfiling.Load() {
			return boxed(ctx, []Value{left, right}).(int64)
		}
		CheckCancelled(ctx)
		if ctx != nil && ctx.calls != nil {
			calls := ctx.calls
			calls.depth++
			if calls.depth > MaxCallDepth {
				calls.depth--
				Panic(fmt.Sprintf("call depth limit exceeded (%d nested calls)", MaxCallDepth))
			}
			defer func() {
				calls.depth--
				if calls.depth == 0 {
					calls.traceFull = false
				}
			}()
		}
		defer func() {
			if controlPanics.Load() == 0 {
				return
			}
			if failure := recover(); failure != nil {
				if returned, ok := failure.(sourceReturn); ok {
					controlPanics.Add(-1)
					value = returned.value.(int64)
					CheckCancelled(ctx)
					return
				}
				panic(failure)
			}
		}()
		value = body(ctx, left, right)
		CheckCancelled(ctx)
		return value
	}
}

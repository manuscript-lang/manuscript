package msruntime

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

// Scalar callbacks retain an inline guard and typed delivery checkpoint. Source
// return consumption and limit faults are shared with boxed calls.
func sourceComparator[T any](body func(*Execution, T, T) int64, boxed func(*Execution, []Value) Value) func(*Execution, T, T) int64 {
	return func(ctx *Execution, left, right T) (value int64) {
		if sourceProfiling.Load() {
			return boxed(ctx, []Value{left, right}).(int64)
		}
		CheckCancelled(ctx)
		if ctx != nil && ctx.calls != nil {
			calls := ctx.calls
			if calls.depth++; calls.depth > MaxCallDepth {
				sourceDepthFault(calls)
			}
			defer func() { calls.depth-- }()
		}
		defer func() {
			if controlPanics.Load() == 0 {
				return
			}
			if failure := recover(); failure != nil {
				if returned, ok := consumeSourceReturn(failure); ok {
					value = returned.(int64)
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

package msruntime

// NewIntCompareFunction keeps an ordinary callable and a typed comparison entry
// on the same value. The supplied body retains generated source tracing/cleanup.
func NewIntCompareFunction(labels []string, result, position string, body func(*Execution, int64, int64) int64) Function {
	f := NewSourceFunction(labels, result, position, func(ctx *Execution, args []Value) Value {
		return body(ctx, args[0].(int64), args[1].(int64))
	})
	f.IntCompare = sourceComparator(result, position, body)
	return f
}

func NewFloatCompareFunction(labels []string, result, position string, body func(*Execution, float64, float64) int64) Function {
	f := NewSourceFunction(labels, result, position, func(ctx *Execution, args []Value) Value {
		return body(ctx, args[0].(float64), args[1].(float64))
	})
	f.FloatCompare = sourceComparator(result, position, body)
	return f
}

// Both callback entries select the canonical source boundary exactly once.
func sourceComparator[T any](result, position string, body func(*Execution, T, T) int64) func(*Execution, T, T) int64 {
	return func(ctx *Execution, left, right T) int64 {
		if SourceCallNeedsProfile(ctx) {
			return ProfileSourceCall(ctx, result, position, func(ctx *Execution) int64 { return body(ctx, left, right) })
		}
		return SourceCall(ctx, result, func(ctx *Execution) int64 { return body(ctx, left, right) })
	}
}

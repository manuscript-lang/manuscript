package msruntime

// Each invocation owns its buffer, including recursion/reentry. Only proven
// compiled bodies with exact label order may borrow it; other callbacks keep
// Invoke's fresh incoming argument array and may retain it.
func listForEach(ctx *Execution, list *List, operation Value) Value {
	captured := list.Capture()
	operate := newCallback(operation, "value")
	for i := 0; i < captured.Len(); i++ {
		value := captured.Get(i)
		CheckCancelled(ctx)
		operate.call1(ctx, operation, value)
	}
	return Unit{}
}

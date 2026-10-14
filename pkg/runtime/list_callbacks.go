package msruntime

// Each invocation owns its buffer, including recursion/reentry. Only proven
// compiled bodies with exact label order may borrow it; other callbacks keep
// Invoke's fresh incoming argument array and may retain it.
func listForEach(ctx *Execution, list *List, operation Value) Value {
	captured := list.Capture()
	if function, ok := operation.(Function); ok && function.BorrowedArguments && len(function.Labels) == 1 && function.Labels[0] == "value" {
		if captured.Len() == 0 {
			return Unit{}
		}
		args := make([]Value, 1)
		for i := 0; i < captured.Len(); i++ {
			value := captured.Get(i)
			CheckCancelled(ctx)
			args[0] = value
			// This is Invoke's admission checkpoint; the guarded Body owns its
			// existing source admission and delivery, with no wrapper added.
			CheckCancelled(ctx)
			function.Body(ctx, args)
		}
		return Unit{}
	}
	for i := 0; i < captured.Len(); i++ {
		value := captured.Get(i)
		CheckCancelled(ctx)
		Invoke(ctx, operation, []Argument{{"value", value}})
	}
	return Unit{}
}

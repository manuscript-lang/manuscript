package msruntime

func init() {
	for _, operation := range []struct{ name, element string }{
		{"sorted_int", "Int"},
		{"sorted_float", "Float"},
		{"sorted_strings", "String"},
	} {
		libraryAdd("collections", operation.name, "List["+operation.element+"]", []LibraryParam{{"values", "List[" + operation.element + "]"}}, func(ctx *Execution, result string, args []Value) Value {
			CheckCancelled(ctx)
			captured := CaptureList(args[0])
			out := captured.list.copySliceChecked(ctx, 0, captured.Len())
			if out.kind == listBoxed {
				// Normalize legacy boxed primitive input only at this boundary.
				out = NewList(result, out.Items)
			} else {
				out.Type = result
			}
			ListSortInPlace(ctx, out, nil)
			CheckCancelled(ctx)
			return out
		})
	}
}

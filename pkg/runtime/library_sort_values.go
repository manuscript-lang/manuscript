package msruntime

func init() {
	for _, operation := range []struct{ name, element string }{
		{"sorted_int", "Int"},
		{"sorted_float", "Float"},
		{"sorted_strings", "String"},
	} {
		libraryAdd("collections", operation.name, "List["+operation.element+"]", []LibraryParam{{"values", "List[" + operation.element + "]"}}, func(ctx *Execution, result string, args []Value) Value {
			CheckCancelled(ctx)
			out := NewList(result, nil)
			for i, value := range Iterate(args[0]) {
				if i%1024 == 0 {
					CheckCancelled(ctx)
				}
				out.Append(value)
			}
			ListSortInPlace(ctx, out, nil)
			CheckCancelled(ctx)
			return out
		})
	}
}

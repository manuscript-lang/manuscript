package msruntime

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	elements := []LibraryParam{p("T", "")}
	listParam := []LibraryParam{p("values", "List[T]")}
	libraryGeneric("collections", "count", "Int", elements, []LibraryParam{p("values", "List[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		items := Iterate(args[0])
		count := int64(0)
		for _, value := range items {
			CheckCancelled(ctx)
			if Invoke(ctx, args[1], []Argument{{"value", value}}).(bool) {
				count++
			}
		}
		return count
	})
	libraryGeneric("collections", "zip", "List[ListPair[T][U]]", []LibraryParam{p("T", ""), p("U", "")}, []LibraryParam{p("values", "List[T]"), p("other", "List[U]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		left, right := CaptureList(args[0]), CaptureList(args[1])
		length := min(left.Len(), right.Len())
		pairType := typeArguments(result)[0]
		out := make([]Value, length)
		for i := range length {
			CheckCancelled(ctx)
			out[i] = Record{Type: pairType, Fields: map[string]Value{"first": left.Get(i), "second": right.Get(i)}}
		}
		return NewList(result, out)
	})
	libraryGeneric("collections", "distinct", "List[T]", []LibraryParam{p("T", "Equal")}, listParam, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := CaptureList(args[0])
		out := NewList(result, nil)
		for _, value := range items.Values() {
			CheckCancelled(ctx)
			duplicate := false
			for _, previous := range out.Capture().Values() {
				CheckCancelled(ctx)
				if EqualIn(ctx, previous, value) {
					duplicate = true
					break
				}
			}
			if !duplicate {
				out.Append(value)
			}
		}
		return out
	})
	libraryGeneric("collections", "partition", "ListPartition[T]", elements, []LibraryParam{p("values", "List[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := Iterate(args[0])
		listType := "@std/List[" + typeArguments(result)[0] + "]"
		matching, remaining := NewList(listType, nil), NewList(listType, nil)
		for _, value := range items {
			CheckCancelled(ctx)
			if Invoke(ctx, args[1], []Argument{{"value", value}}).(bool) {
				matching.Append(value)
			} else {
				remaining.Append(value)
			}
		}
		return Record{Type: result, Fields: map[string]Value{"matching": matching, "remaining": remaining}}
	})
	for _, name := range []string{"min", "max"} {
		libraryGeneric("collections", name, "Optional[T]", elements, []LibraryParam{p("values", "List[T]"), p("compare", "fn(left:T;right:T)->Int")}, func(ctx *Execution, result string, args []Value) Value {
			CheckCancelled(ctx)
			items := CaptureList(args[0])
			if items.Len() == 0 {
				return Alternative{Type: result, Tag: "none"}
			}
			best := items.Get(0)
			for i := 1; i < items.Len(); i++ {
				CheckCancelled(ctx)
				value := items.Get(i)
				comparison := Invoke(ctx, args[1], []Argument{{"left", value}, {"right", best}}).(int64)
				if name == "min" && comparison < 0 || name == "max" && comparison > 0 {
					best = value
				}
			}
			return Alternative{Type: result, Tag: "some", Fields: []Value{best}}
		})
	}
	libraryGeneric("collections", "insert", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int"), p("value", "T")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		list, index := args[0].(*List), args[1].(int64)
		if index < 0 || index > int64(list.Len()) {
			return libraryRangeFault("List.insert", "index", index, 0, int64(list.Len()))
		}
		spliceList(list, int(index), 0, NewList(list.Type, []Value{args[2]}))
		CheckCancelled(ctx)
		return list
	})
	libraryGeneric("collections", "pop", "Optional[T]", elements, listParam, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		list := args[0].(*List)
		if list.Len() == 0 {
			return Alternative{Type: result, Tag: "none"}
		}
		index := list.Len() - 1
		value := list.Get(index)
		spliceList(list, index, 1, NewList(list.Type, nil))
		CheckCancelled(ctx)
		return Alternative{Type: result, Tag: "some", Fields: []Value{value}}
	})
	libraryGeneric("collections", "sort_in_place", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("compare", "fn(left:T;right:T)->Int")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		ListSortInPlace(ctx, args[0], args[1])
		CheckCancelled(ctx)
		return args[0]
	})
}

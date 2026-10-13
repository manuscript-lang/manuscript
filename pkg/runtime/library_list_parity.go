package msruntime

import "sort"

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
		left, right := Iterate(args[0]), Iterate(args[1])
		length := min(len(left), len(right))
		pairType := typeArguments(result)[0]
		out := make([]Value, length)
		for i := range length {
			CheckCancelled(ctx)
			out[i] = Record{Type: pairType, Fields: map[string]Value{"first": left[i], "second": right[i]}}
		}
		return &List{Type: result, Items: out}
	})
	libraryGeneric("collections", "distinct", "List[T]", []LibraryParam{p("T", "Equal")}, listParam, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := Iterate(args[0])
		out := make([]Value, 0, len(items))
		for _, value := range items {
			CheckCancelled(ctx)
			duplicate := false
			for _, previous := range out {
				CheckCancelled(ctx)
				if EqualIn(ctx, previous, value) {
					duplicate = true
					break
				}
			}
			if !duplicate {
				out = append(out, value)
			}
		}
		return &List{Type: result, Items: out}
	})
	libraryGeneric("collections", "partition", "ListPartition[T]", elements, []LibraryParam{p("values", "List[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := Iterate(args[0])
		listType := "@std/List[" + typeArguments(result)[0] + "]"
		matching, remaining := &List{Type: listType}, &List{Type: listType}
		for _, value := range items {
			CheckCancelled(ctx)
			if Invoke(ctx, args[1], []Argument{{"value", value}}).(bool) {
				matching.Items = append(matching.Items, value)
			} else {
				remaining.Items = append(remaining.Items, value)
			}
		}
		return Record{Type: result, Fields: map[string]Value{"matching": matching, "remaining": remaining}}
	})
	for _, name := range []string{"min", "max"} {
		libraryGeneric("collections", name, "Optional[T]", elements, []LibraryParam{p("values", "List[T]"), p("compare", "fn(left:T;right:T)->Int")}, func(ctx *Execution, result string, args []Value) Value {
			CheckCancelled(ctx)
			items := Iterate(args[0])
			if len(items) == 0 {
				return Alternative{Type: result, Tag: "none"}
			}
			best := items[0]
			for _, value := range items[1:] {
				CheckCancelled(ctx)
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
		if index < 0 || index > int64(len(list.Items)) {
			return libraryRangeFault("List.insert", "index", index, 0, int64(len(list.Items)))
		}
		spliceList(list, int(index), 0, &List{Type: list.Type, Items: []Value{args[2]}})
		CheckCancelled(ctx)
		return list
	})
	libraryGeneric("collections", "pop", "Optional[T]", elements, listParam, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		list := args[0].(*List)
		if len(list.Items) == 0 {
			return Alternative{Type: result, Tag: "none"}
		}
		index := len(list.Items) - 1
		value := list.Items[index]
		spliceList(list, index, 1, &List{Type: list.Type})
		CheckCancelled(ctx)
		return Alternative{Type: result, Tag: "some", Fields: []Value{value}}
	})
	libraryGeneric("collections", "sort_in_place", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("compare", "fn(left:T;right:T)->Int")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		items := Iterate(args[0])
		sort.SliceStable(items, func(i, j int) bool {
			CheckCancelled(ctx)
			left, right := items[i], items[j]
			return Invoke(ctx, args[1], []Argument{{"left", left}, {"right", right}}).(int64) < 0
		})
		CheckCancelled(ctx)
		return args[0]
	})
}

package msruntime

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	vars := []LibraryParam{p("T", "")}
	libraryGeneric("collections", "map", "List[U]", []LibraryParam{p("T", ""), p("U", "")}, []LibraryParam{p("values", "List[T]"), p("transform", "fn(value:T)->U")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Capture()
		out := make([]Value, items.Len())
		for i, v := range items.Values() {
			CheckCancelled(ctx)
			out[i] = Invoke(ctx, a[1], []Argument{{"value", v}})
		}
		return NewList(r, out)
	})
	libraryGeneric("collections", "filter", "List[T]", vars, []LibraryParam{p("values", "List[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, r string, a []Value) Value {
		var out []Value
		for _, v := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			if Invoke(ctx, a[1], []Argument{{"value", v}}).(bool) {
				out = append(out, v)
			}
		}
		return NewList(r, out)
	})
	libraryGeneric("collections", "fold", "A", []LibraryParam{p("T", ""), p("A", "")}, []LibraryParam{p("values", "List[T]"), p("initial", "A"), p("step", "fn(accumulator:A;value:T)->A")}, func(ctx *Execution, _ string, a []Value) Value {
		acc := a[1]
		for _, v := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			acc = Invoke(ctx, a[2], []Argument{{"accumulator", acc}, {"value", v}})
		}
		return acc
	})
	libraryGeneric("collections", "sorted", "List[T]", vars, []LibraryParam{p("values", "List[T]"), p("compare", "fn(left:T;right:T)->Int")}, func(ctx *Execution, r string, a []Value) Value {
		return ListSorted(ctx, a[0], a[1])
	})
	libraryGeneric("collections", "map_keys", "List[K]", []LibraryParam{p("K", "Hashable"), p("V", "")}, []LibraryParam{p("values", "Map[K][V]")}, func(ctx *Execution, r string, a []Value) Value {
		entries := a[0].(*Map).Entries
		out := make([]Value, len(entries))
		for i, e := range entries {
			out[i] = e.Key
		}
		return NewList(r, out)
	})
	libraryGeneric("collections", "map_values", "List[V]", []LibraryParam{p("K", "Hashable"), p("V", "")}, []LibraryParam{p("values", "Map[K][V]")}, func(ctx *Execution, r string, a []Value) Value {
		entries := a[0].(*Map).Entries
		out := make([]Value, len(entries))
		for i, e := range entries {
			out[i] = e.Value
		}
		return NewList(r, out)
	})
	for _, name := range []string{"union", "intersection", "difference"} {
		libraryGeneric("collections", name, "Set[T]", []LibraryParam{p("T", "Hashable")}, []LibraryParam{p("left", "Set[T]"), p("right", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
			left, right := a[0].(*Set), a[1].(*Set)
			var out []Value
			for _, v := range left.Items {
				CheckCancelled(ctx)
				contains := right.find(ctx, v) >= 0
				if name == "union" || name == "intersection" && contains || name == "difference" && !contains {
					out = append(out, v)
				}
			}
			if name == "union" {
				for _, v := range right.Items {
					CheckCancelled(ctx)
					if left.find(ctx, v) < 0 {
						out = append(out, v)
					}
				}
			}
			return &Set{Type: r, Items: out}
		})
	}
	libraryAdd("io", "copy", libraryResult("Int", "IoError"), []LibraryParam{p("input", "ReadStream"), p("output", "WriteStream"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		max := a[2].(int64)
		if max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		total := int64(0)
		for {
			CheckCancelled(ctx)
			n := int64(32768)
			if max-total < n {
				n = max - total + 1
			}
			value := Invoke(ctx, Bind(a[0], "", "read"), []Argument{{"max_bytes", optional("Int", n, true)}}).(Alternative)
			if value.Tag == "error" {
				return Alternative{r, "error", value.Fields}
			}
			part := value.Fields[0].(Alternative)
			if part.Tag == "none" {
				return libraryOK(r, total)
			}
			data := part.Fields[0].(Bytes)
			if len(data.Items) == 0 || int64(len(data.Items)) > n {
				return libraryError(r, "Failed", "invalid stream chunk")
			}
			if int64(len(data.Items)) > max-total {
				return libraryError(r, "LimitExceeded", "")
			}
			written := Invoke(ctx, Bind(a[1], "", "write"), []Argument{{"data", data}}).(Alternative)
			if written.Tag == "error" {
				return Alternative{r, "error", written.Fields}
			}
			total += int64(len(data.Items))
		}
	})
	libraryAdd("io", "read_all", libraryResult("Bytes", "IoError"), []LibraryParam{p("input", "ReadStream"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		max := a[1].(int64)
		if max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var out []byte
		for {
			n := int64(32768)
			if max-int64(len(out)) < n {
				n = max - int64(len(out)) + 1
			}
			value := Invoke(ctx, Bind(a[0], "", "read"), []Argument{{"max_bytes", optional("Int", n, true)}}).(Alternative)
			if value.Tag == "error" {
				return Alternative{r, "error", value.Fields}
			}
			part := value.Fields[0].(Alternative)
			if part.Tag == "none" {
				return libraryOK(r, Bytes{out})
			}
			data := part.Fields[0].(Bytes).Items
			if len(data) == 0 || int64(len(data)) > n {
				return libraryError(r, "Failed", "invalid stream chunk")
			}
			if int64(len(data)) > max-int64(len(out)) {
				return libraryError(r, "LimitExceeded", "")
			}
			out = append(out, data...)
		}
	})
}

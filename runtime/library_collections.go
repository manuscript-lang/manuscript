package msruntime

import "math"

// relativeIndex implements Array.at-style indexing without negating MinInt64.
func relativeIndex(length int, index int64) int64 {
	if index < 0 {
		return int64(length) + index
	}
	return index
}

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	elements := []LibraryParam{p("T", "")}
	equal := []LibraryParam{p("T", "Equal")}
	hash := []LibraryParam{p("T", "Hashable")}
	mapVars := []LibraryParam{p("K", "Hashable"), p("V", "")}
	listParam := []LibraryParam{p("values", "List[T]")}
	add := func(name, result string, vars, params []LibraryParam, body func(*Execution, string, []Value) Value) {
		libraryGeneric("collections", name, result, vars, params, body)
	}
	for _, name := range []string{"first", "last", "at"} {
		params := append([]LibraryParam{}, listParam...)
		if name == "at" {
			params = append(params, p("index", "Int"))
		}
		add(name, "Optional[T]", elements, params, func(_ *Execution, r string, a []Value) Value {
			v := a[0].(List)
			i := int64(0)
			if name == "last" {
				i = int64(len(v.Items)) - 1
			}
			if name == "at" {
				i = relativeIndex(len(v.Items), a[1].(int64))
			}
			if i < 0 || i >= int64(len(v.Items)) {
				return Alternative{Type: r, Tag: "none"}
			}
			return Alternative{r, "some", []Value{v.Items[i]}}
		})
	}
	add("is_empty", "Bool", elements, listParam, func(_ *Execution, _ string, a []Value) Value { return len(a[0].(List).Items) == 0 })
	for _, name := range []string{"contains", "index_of", "last_index_of"} {
		result := "Optional[Int]"
		if name == "contains" {
			result = "Bool"
		}
		add(name, result, equal, []LibraryParam{p("values", "List[T]"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
			items := a[0].(List).Items
			start, end, step := 0, len(items), 1
			if name == "last_index_of" {
				start, end, step = len(items)-1, -1, -1
			}
			for i := start; i != end; i += step {
				CheckCancelled(ctx)
				if Equal(items[i], a[1]) {
					if name == "contains" {
						return true
					}
					return Alternative{r, "some", []Value{int64(i)}}
				}
			}
			if name == "contains" {
				return false
			}
			return Alternative{Type: r, Tag: "none"}
		})
	}
	add("prepend", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("value", "T")}, func(_ *Execution, r string, a []Value) Value {
		return List{r, append([]Value{a[1]}, a[0].(List).Items...)}
	})
	add("with_value", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int"), p("value", "T")}, func(_ *Execution, r string, a []Value) Value {
		items := a[0].(List).Items
		i := relativeIndex(len(items), a[1].(int64))
		if i < 0 || i >= int64(len(items)) {
			return Panic("list update index out of range")
		}
		out := append([]Value{}, items...)
		out[i] = a[2]
		return List{r, out}
	})
	add("without", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int")}, func(_ *Execution, r string, a []Value) Value {
		items := a[0].(List).Items
		i := relativeIndex(len(items), a[1].(int64))
		if i < 0 || i >= int64(len(items)) {
			return Panic("list removal index out of range")
		}
		out := append([]Value{}, items[:i]...)
		out = append(out, items[i+1:]...)
		return List{r, out}
	})
	for _, name := range []string{"find", "find_last", "find_index", "find_last_index", "some", "every"} {
		result := "Optional[T]"
		if name == "find_index" || name == "find_last_index" {
			result = "Optional[Int]"
		}
		if name == "some" || name == "every" {
			result = "Bool"
		}
		add(name, result, elements, []LibraryParam{p("values", "List[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, r string, a []Value) Value {
			items := a[0].(List).Items
			start, end, step := 0, len(items), 1
			if name == "find_last" || name == "find_last_index" {
				start, end, step = len(items)-1, -1, -1
			}
			for i := start; i != end; i += step {
				CheckCancelled(ctx)
				matches := Invoke(ctx, a[1], []Argument{{"value", items[i]}}).(bool)
				if name == "every" {
					if !matches {
						return false
					}
					continue
				}
				if matches {
					if name == "some" {
						return true
					}
					var value Value = items[i]
					if name == "find_index" || name == "find_last_index" {
						value = int64(i)
					}
					return Alternative{r, "some", []Value{value}}
				}
			}
			if name == "some" {
				return false
			}
			if name == "every" {
				return true
			}
			return Alternative{Type: r, Tag: "none"}
		})
	}
	add("for_each", "Unit", elements, []LibraryParam{p("values", "List[T]"), p("operation", "fn(value:T)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		for _, v := range a[0].(List).Items {
			CheckCancelled(ctx)
			Invoke(ctx, a[1], []Argument{{"value", v}})
		}
		return Unit{}
	})
	add("flat_map", "List[U]", []LibraryParam{p("T", ""), p("U", "")}, []LibraryParam{p("values", "List[T]"), p("transform", "fn(value:T)->List[U]")}, func(ctx *Execution, r string, a []Value) Value {
		var out []Value
		for _, v := range a[0].(List).Items {
			CheckCancelled(ctx)
			out = append(out, Invoke(ctx, a[1], []Argument{{"value", v}}).(List).Items...)
		}
		return List{r, out}
	})
	add("flatten", "List[T]", elements, []LibraryParam{p("values", "List[List[T]]")}, func(ctx *Execution, r string, a []Value) Value {
		var out []Value
		for _, v := range a[0].(List).Items {
			CheckCancelled(ctx)
			out = append(out, v.(List).Items...)
		}
		return List{r, out}
	})
	add("fold_right", "A", []LibraryParam{p("T", ""), p("A", "")}, []LibraryParam{p("values", "List[T]"), p("initial", "A"), p("step", "fn(accumulator:A;value:T)->A")}, func(ctx *Execution, _ string, a []Value) Value {
		acc := a[1]
		items := a[0].(List).Items
		for i := len(items) - 1; i >= 0; i-- {
			CheckCancelled(ctx)
			acc = Invoke(ctx, a[2], []Argument{{"accumulator", acc}, {"value", items[i]}})
		}
		return acc
	})
	add("with_values", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("start", "Int"), p("delete_count", "Int"), p("replacement", "List[T]")}, func(_ *Execution, r string, a []Value) Value {
		items := a[0].(List).Items
		start, count := a[1].(int64), a[2].(int64)
		if start < 0 || start > int64(len(items)) || count < 0 || count > int64(len(items))-start {
			return Panic("invalid list replacement bounds")
		}
		out := append([]Value{}, items[:start]...)
		out = append(out, a[3].(List).Items...)
		out = append(out, items[start+count:]...)
		return List{r, out}
	})
	add("fill", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("value", "T"), p("start", "Int"), p("end", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(List).Items
		s, e := a[2].(int64), a[3].(int64)
		librarySlice(len(items), s, e)
		out := append([]Value{}, items...)
		for i := s; i < e; i++ {
			CheckCancelled(ctx)
			out[i] = a[1]
		}
		return List{r, out}
	})
	add("copy_within", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("target", "Int"), p("start", "Int"), p("end", "Int")}, func(_ *Execution, r string, a []Value) Value {
		items := a[0].(List).Items
		t, s, e := a[1].(int64), a[2].(int64), a[3].(int64)
		librarySlice(len(items), s, e)
		if t < 0 || t > int64(len(items)) {
			return Panic("invalid copy target")
		}
		out := append([]Value{}, items...)
		copy(out[t:], out[s:e])
		return List{r, out}
	})
	add("list_keys", "List[Int]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		out := make([]Value, len(a[0].(List).Items))
		for i := range out {
			CheckCancelled(ctx)
			out[i] = int64(i)
		}
		return List{r, out}
	})
	add("list_entries", "List[ListEntry[T]]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(List).Items
		out := make([]Value, len(items))
		typ := typeArguments(r)[0]
		for i, v := range items {
			CheckCancelled(ctx)
			out[i] = Record{typ, map[string]Value{"index": int64(i), "value": v}}
		}
		return List{r, out}
	})
	add("to_set", "Set[T]", []LibraryParam{p("T", "Hashable")}, listParam, func(ctx *Execution, r string, a []Value) Value {
		var out []Value
		for _, v := range a[0].(List).Items {
			CheckCancelled(ctx)
			if indexOf(out, v) < 0 {
				out = append(out, v)
			}
		}
		return Set{r, out}
	})
	add("filled", libraryResult("List[T]", "CollectionError"), elements, []LibraryParam{p("value", "T"), p("count", "Int"), p("max_items", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		count, max := a[1].(int64), a[2].(int64)
		if count < 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		if count > max {
			return libraryError(r, "LimitExceeded", "")
		}
		out := make([]Value, count)
		for i := range out {
			CheckCancelled(ctx)
			out[i] = a[0]
		}
		return libraryOK(r, List{typeArguments(r)[0], out})
	})
	add("range", libraryResult("List[Int]", "CollectionError"), nil, []LibraryParam{p("start", "Int"), p("end", "Int"), p("step", "Int"), p("max_items", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		start, end, step, max := a[0].(int64), a[1].(int64), a[2].(int64), a[3].(int64)
		if step == 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var out []Value
		for n := start; step > 0 && n < end || step < 0 && n > end; {
			CheckCancelled(ctx)
			if int64(len(out)) == max {
				return libraryError(r, "LimitExceeded", "")
			}
			out = append(out, n)
			// An overflowing next term lies outside every representable end.
			if step > 0 && n > math.MaxInt64-step || step < 0 && n < math.MinInt64-step {
				break
			}
			n += step
		}
		return libraryOK(r, List{typeArguments(r)[0], out})
	})
	add("group_by", "Map[K][List[T]]", []LibraryParam{p("T", ""), p("K", "Hashable")}, []LibraryParam{p("values", "List[T]"), p("key", "fn(value:T)->K")}, func(ctx *Execution, r string, a []Value) Value {
		out := Map{Type: r}
		listType := typeArguments(r)[1]
		for _, v := range a[0].(List).Items {
			CheckCancelled(ctx)
			key := Invoke(ctx, a[1], []Argument{{"value", v}})
			found := -1
			for i, e := range out.Entries {
				if Equal(e.Key, key) {
					found = i
					break
				}
			}
			if found < 0 {
				out.Entries = append(out.Entries, Entry{key, List{listType, []Value{v}}})
			} else {
				group := out.Entries[found].Value.(List)
				group.Items = append(group.Items, v)
				out.Entries[found].Value = group
			}
		}
		return out
	})
	for _, name := range []string{"map_with_default", "map_with_default_from"} {
		params := []LibraryParam{p("values", "Map[K][V]"), p("key", "K"), p("value", "V")}
		if name == "map_with_default_from" {
			params[2] = p("create", "fn(key:K)->V")
		}
		add(name, "Map[K][V]", mapVars, params, func(ctx *Execution, r string, a []Value) Value {
			values := a[0].(Map)
			for _, e := range values.Entries {
				CheckCancelled(ctx)
				if Equal(e.Key, a[1]) {
					return values
				}
			}
			value := a[2]
			if name == "map_with_default_from" {
				value = Invoke(ctx, value, []Argument{{"key", a[1]}})
			}
			return Map{r, append(append([]Entry{}, values.Entries...), Entry{a[1], value})}
		})
	}

	add("map_clear", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]")}, func(_ *Execution, r string, _ []Value) Value { return Map{Type: r} })
	add("map_entries", "List[MapEntry[K][V]]", mapVars, []LibraryParam{p("values", "Map[K][V]")}, func(ctx *Execution, r string, a []Value) Value {
		entries := a[0].(Map).Entries
		out := make([]Value, len(entries))
		typ := typeArguments(r)[0]
		for i, e := range entries {
			CheckCancelled(ctx)
			out[i] = Record{typ, map[string]Value{"key": e.Key, "value": e.Value}}
		}
		return List{r, out}
	})
	add("map_merge", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("other", "Map[K][V]")}, func(ctx *Execution, r string, a []Value) Value {
		out := Map{r, append([]Entry{}, a[0].(Map).Entries...)}
		for _, e := range a[1].(Map).Entries {
			CheckCancelled(ctx)
			out = mapPut(out, e.Key, e.Value)
		}
		return out
	})
	add("map_from_entries", "Map[K][V]", mapVars, []LibraryParam{p("entries", "List[MapEntry[K][V]]")}, func(ctx *Execution, r string, a []Value) Value {
		out := Map{Type: r}
		for _, v := range a[0].(List).Items {
			CheckCancelled(ctx)
			e := v.(Record)
			out = mapPut(out, e.Fields["key"], e.Fields["value"])
		}
		return out
	})
	add("map_for_each", "Unit", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("operation", "fn(key:K;value:V)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		for _, e := range a[0].(Map).Entries {
			CheckCancelled(ctx)
			Invoke(ctx, a[1], []Argument{{"key", e.Key}, {"value", e.Value}})
		}
		return Unit{}
	})
	add("set_clear", "Set[T]", hash, []LibraryParam{p("values", "Set[T]")}, func(_ *Execution, r string, _ []Value) Value { return Set{Type: r} })
	add("set_values", "List[T]", hash, []LibraryParam{p("values", "Set[T]")}, func(_ *Execution, r string, a []Value) Value { return List{r, append([]Value{}, a[0].(Set).Items...)} })
	add("set_entries", "List[List[T]]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(Set).Items
		out := make([]Value, len(items))
		typ := typeArguments(r)[0]
		for i, v := range items {
			CheckCancelled(ctx)
			out[i] = List{typ, []Value{v, v}}
		}
		return List{r, out}
	})
	add("set_for_each", "Unit", hash, []LibraryParam{p("values", "Set[T]"), p("operation", "fn(value:T)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		for _, v := range a[0].(Set).Items {
			CheckCancelled(ctx)
			Invoke(ctx, a[1], []Argument{{"value", v}})
		}
		return Unit{}
	})
	for _, name := range []string{"symmetric_difference", "is_subset_of", "is_superset_of", "is_disjoint_from"} {
		result := "Bool"
		if name == "symmetric_difference" {
			result = "Set[T]"
		}
		add(name, result, hash, []LibraryParam{p("left", "Set[T]"), p("right", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
			left, right := a[0].(Set).Items, a[1].(Set).Items
			if name == "is_superset_of" {
				left, right = right, left
			}
			var out []Value
			for _, v := range left {
				CheckCancelled(ctx)
				found := indexOf(right, v) >= 0
				if name == "symmetric_difference" {
					if !found {
						out = append(out, v)
					}
					continue
				}
				if name == "is_disjoint_from" && found || name != "is_disjoint_from" && !found {
					return false
				}
			}
			if name != "symmetric_difference" {
				return true
			}
			for _, v := range right {
				CheckCancelled(ctx)
				if indexOf(left, v) < 0 {
					out = append(out, v)
				}
			}
			return Set{r, out}
		})
	}
}

func mapPut(values Map, key, value Value) Map {
	for i, e := range values.Entries {
		if Equal(e.Key, key) {
			values.Entries[i].Value = value
			return values
		}
	}
	values.Entries = append(values.Entries, Entry{key, value})
	return values
}

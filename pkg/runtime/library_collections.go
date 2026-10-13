package msruntime

import (
	"math"
)

// relativeIndex implements Array.at-style indexing without negating MinInt64.
func relativeIndex(length int, index int64) int64 {
	if index < 0 {
		return int64(length) + index
	}
	return index
}

// ListAt is the checked direct-call path for List.at. It retains Optional-safe
// indexing and the cancellation boundaries of an ordinary native call.
func ListAt(ctx *Execution, receiver Value, index Value, result string) Value {
	CheckCancelled(ctx)
	list := receiver.(*List)
	i := relativeIndex(len(list.Items), index.(int64))
	value := Alternative{Type: result, Tag: "none"}
	if i >= 0 && i < int64(len(list.Items)) {
		value = Alternative{Type: result, Tag: "some", Fields: []Value{list.Items[i]}}
	}
	CheckCancelled(ctx)
	return value
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
	add("map_is_empty", "Bool", mapVars, []LibraryParam{p("values", "Map[K][V]")}, func(_ *Execution, _ string, a []Value) Value {
		return len(a[0].(*Map).Entries) == 0
	})
	add("map_get_or", "V", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("key", "K"), p("fallback", "V")}, func(ctx *Execution, _ string, a []Value) Value {
		values := a[0].(*Map)
		if index := values.find(ctx, a[1]); index >= 0 {
			return values.Entries[index].Value
		}
		return a[2]
	})
	add("map_filter", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("predicate", "fn(key:K;value:V)->Bool")}, func(ctx *Execution, result string, a []Value) Value {
		out := &Map{Type: result}
		for _, entry := range a[0].(*Map).Entries {
			CheckCancelled(ctx)
			if Invoke(ctx, a[1], []Argument{{"key", entry.Key}, {"value", entry.Value}}).(bool) {
				out.Entries = append(out.Entries, entry)
			}
		}
		return out
	})
	add("set_is_empty", "Bool", hash, []LibraryParam{p("values", "Set[T]")}, func(_ *Execution, _ string, a []Value) Value {
		return len(a[0].(*Set).Items) == 0
	})
	add("set_filter", "Set[T]", hash, []LibraryParam{p("values", "Set[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, result string, a []Value) Value {
		out := &Set{Type: result}
		for _, value := range a[0].(*Set).Items {
			CheckCancelled(ctx)
			if Invoke(ctx, a[1], []Argument{{"value", value}}).(bool) {
				out.Items = append(out.Items, value)
			}
		}
		return out
	})
	add("set_map", "Set[U]", []LibraryParam{p("T", "Hashable"), p("U", "Hashable")}, []LibraryParam{p("values", "Set[T]"), p("transform", "fn(value:T)->U")}, func(ctx *Execution, result string, a []Value) Value {
		out := &Set{Type: result}
		for _, value := range a[0].(*Set).Items {
			CheckCancelled(ctx)
			out.add(ctx, Invoke(ctx, a[1], []Argument{{"value", value}}))
		}
		return out
	})
	for _, name := range []string{"first", "last", "at"} {
		params := append([]LibraryParam{}, listParam...)
		if name == "at" {
			params = append(params, p("index", "Int"))
		}
		add(name, "Optional[T]", elements, params, func(ctx *Execution, r string, a []Value) Value {
			v := a[0].(*List)
			i := int64(0)
			if name == "last" {
				i = int64(len(v.Items)) - 1
			}
			if name == "at" {
				i = a[1].(int64)
			}
			return ListAt(ctx, v, i, r)
		})
	}
	add("is_empty", "Bool", elements, listParam, func(ctx *Execution, _ string, a []Value) Value { return len(a[0].(*List).Items) == 0 })
	for _, name := range []string{"contains", "index_of", "last_index_of"} {
		result := "Optional[Int]"
		if name == "contains" {
			result = "Bool"
		}
		add(name, result, equal, []LibraryParam{p("values", "List[T]"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
			items := a[0].(*List).Items
			start, end, step := 0, len(items), 1
			if name == "last_index_of" {
				start, end, step = len(items)-1, -1, -1
			}
			for i := start; i != end; i += step {
				CheckCancelled(ctx)
				if EqualIn(ctx, items[i], a[1]) {
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
	add("prepend", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
		v := a[0].(*List)
		v.ownItems()
		v.Items = append(v.Items, nil)
		copy(v.Items[1:], v.Items[:len(v.Items)-1])
		v.Items[0] = a[1]
		return v
	})
	add("with_value", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
		a[0].(*List).ownItems()
		items := a[0].(*List).Items
		i := relativeIndex(len(items), a[1].(int64))
		if i < 0 || i >= int64(len(items)) {
			return libraryIndexFault("List.with_value", len(items), a[1].(int64))
		}
		items[i] = a[2]
		return a[0]
	})
	add("without", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		a[0].(*List).ownItems()
		items := a[0].(*List).Items
		i := relativeIndex(len(items), a[1].(int64))
		if i < 0 || i >= int64(len(items)) {
			return libraryIndexFault("List.without", len(items), a[1].(int64))
		}
		copy(items[i:], items[i+1:])
		items[len(items)-1] = nil
		a[0].(*List).Items = items[:len(items)-1]
		return a[0]
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
			items := a[0].(*List).Items
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
		for _, v := range a[0].(*List).Items {
			CheckCancelled(ctx)
			Invoke(ctx, a[1], []Argument{{"value", v}})
		}
		return Unit{}
	})
	add("flat_map", "List[U]", []LibraryParam{p("T", ""), p("U", "")}, []LibraryParam{p("values", "List[T]"), p("transform", "fn(value:T)->List[U]")}, func(ctx *Execution, r string, a []Value) Value {
		var out []Value
		for _, v := range a[0].(*List).Items {
			CheckCancelled(ctx)
			out = append(out, Invoke(ctx, a[1], []Argument{{"value", v}}).(*List).Items...)
		}
		return &List{Type: r, Items: out}
	})
	add("fold_right", "A", []LibraryParam{p("T", ""), p("A", "")}, []LibraryParam{p("values", "List[T]"), p("initial", "A"), p("step", "fn(accumulator:A;value:T)->A")}, func(ctx *Execution, _ string, a []Value) Value {
		acc := a[1]
		items := a[0].(*List).Items
		for i := len(items) - 1; i >= 0; i-- {
			CheckCancelled(ctx)
			acc = Invoke(ctx, a[2], []Argument{{"accumulator", acc}, {"value", items[i]}})
		}
		return acc
	})
	add("with_values", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("start", "Int"), p("delete_count", "Int"), p("replacement", "List[T]")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Items
		start, count := a[1].(int64), a[2].(int64)
		if start < 0 || start > int64(len(items)) {
			return libraryRangeFault("List.with_values", "start", start, 0, int64(len(items)))
		}
		if count < 0 || count > int64(len(items))-start {
			return libraryRangeFault("List.with_values", "delete_count", count, 0, int64(len(items))-start)
		}
		spliceList(a[0].(*List), int(start), int(count), a[3].(*List))
		return a[0]
	})
	add("fill", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("value", "T"), p("start", "Int"), p("end", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Items
		s, e := a[2].(int64), a[3].(int64)
		librarySlice("List.fill", len(items), s, e)
		out := items
		for i := s; i < e; i++ {
			CheckCancelled(ctx)
			out[i] = a[1]
		}
		return a[0]
	})
	add("copy_within", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("target", "Int"), p("start", "Int"), p("end", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Items
		t, s, e := a[1].(int64), a[2].(int64), a[3].(int64)
		librarySlice("List.copy_within", len(items), s, e)
		if t < 0 || t > int64(len(items)) {
			return libraryRangeFault("List.copy_within", "target", t, 0, int64(len(items)))
		}
		copy(items[t:], items[s:e])
		return a[0]
	})
	add("list_keys", "List[Int]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		out := make([]Value, len(a[0].(*List).Items))
		for i := range out {
			CheckCancelled(ctx)
			out[i] = int64(i)
		}
		return &List{Type: r, Items: out}
	})
	add("list_entries", "List[ListEntry[T]]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Items
		out := make([]Value, len(items))
		typ := typeArguments(r)[0]
		for i, v := range items {
			CheckCancelled(ctx)
			out[i] = Record{typ, map[string]Value{"index": int64(i), "value": v}}
		}
		return &List{Type: r, Items: out}
	})
	add("to_set", "Set[T]", []LibraryParam{p("T", "Hashable")}, listParam, func(ctx *Execution, r string, a []Value) Value {
		out := &Set{Type: r}
		for _, v := range a[0].(*List).Items {
			CheckCancelled(ctx)
			out.add(ctx, v)
		}
		return out
	})
	add("filled", libraryResult("List[T]", "CollectionError"), elements, []LibraryParam{p("value", "T"), p("count", "Int"), p("max_items", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		count, max := a[1].(int64), a[2].(int64)
		if count < 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		if count > min(max, nativeMaxItems) {
			return libraryError(r, "LimitExceeded", "")
		}
		out := make([]Value, count)
		for i := range out {
			CheckCancelled(ctx)
			out[i] = a[0]
		}
		return libraryOK(r, &List{Type: typeArguments(r)[0], Items: out})
	})
	add("range", libraryResult("List[Int]", "CollectionError"), nil, []LibraryParam{p("start", "Int"), p("end", "Int"), p("step", "Int"), p("max_items", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		start, end, step, max := a[0].(int64), a[1].(int64), a[2].(int64), a[3].(int64)
		if step == 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		max = min(max, nativeMaxItems)
		// Count the terms first so a huge range fails before allocating.
		var span, size uint64
		if step > 0 && start < end {
			span, size = uint64(end)-uint64(start), uint64(step)
		} else if step < 0 && start > end {
			span, size = uint64(start)-uint64(end), -uint64(step)
		}
		if span > 0 && (span-1)/size >= uint64(max) {
			return libraryError(r, "LimitExceeded", "")
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
		return libraryOK(r, &List{Type: typeArguments(r)[0], Items: out})
	})
	add("group_by", "Map[K][List[T]]", []LibraryParam{p("T", ""), p("K", "Hashable")}, []LibraryParam{p("values", "List[T]"), p("key", "fn(value:T)->K")}, func(ctx *Execution, r string, a []Value) Value {
		out := &Map{Type: r}
		listType := typeArguments(r)[1]
		for _, v := range a[0].(*List).Items {
			CheckCancelled(ctx)
			key := Invoke(ctx, a[1], []Argument{{"value", v}})
			found := out.find(ctx, key)
			if found < 0 {
				out.Entries = append(out.Entries, Entry{key, &List{Type: listType, Items: []Value{v}}})
				keyAppended(ctx, out)
			} else {
				group := out.Entries[found].Value.(*List)
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
			values := a[0].(*Map)
			if values.find(ctx, a[1]) >= 0 {
				return values
			}
			value := a[2]
			if name == "map_with_default_from" {
				value = Invoke(ctx, value, []Argument{{"key", a[1]}})
			}
			return mapPut(ctx, values, a[1], value)
		})
	}

	add("map_clear", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]")}, func(ctx *Execution, _ string, a []Value) Value { a[0].(*Map).Entries = nil; return a[0] })
	add("map_entries", "List[MapEntry[K][V]]", mapVars, []LibraryParam{p("values", "Map[K][V]")}, func(ctx *Execution, r string, a []Value) Value {
		entries := a[0].(*Map).Entries
		out := make([]Value, len(entries))
		typ := typeArguments(r)[0]
		for i, e := range entries {
			CheckCancelled(ctx)
			out[i] = Record{typ, map[string]Value{"key": e.Key, "value": e.Value}}
		}
		return &List{Type: r, Items: out}
	})
	add("map_merge", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("other", "Map[K][V]")}, func(ctx *Execution, r string, a []Value) Value {
		out := a[0].(*Map)
		for _, e := range a[1].(*Map).Entries {
			CheckCancelled(ctx)
			out = mapPut(ctx, out, e.Key, e.Value)
		}
		return out
	})
	add("map_from_entries", "Map[K][V]", mapVars, []LibraryParam{p("entries", "List[MapEntry[K][V]]")}, func(ctx *Execution, r string, a []Value) Value {
		out := &Map{Type: r}
		for _, v := range a[0].(*List).Items {
			CheckCancelled(ctx)
			e := v.(Record)
			out = mapPut(ctx, out, e.Fields["key"], e.Fields["value"])
		}
		return out
	})
	add("map_for_each", "Unit", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("operation", "fn(key:K;value:V)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		for _, e := range a[0].(*Map).Entries {
			CheckCancelled(ctx)
			Invoke(ctx, a[1], []Argument{{"key", e.Key}, {"value", e.Value}})
		}
		return Unit{}
	})
	add("set_clear", "Set[T]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, _ string, a []Value) Value { a[0].(*Set).Items = nil; return a[0] })
	add("set_values", "List[T]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
		return &List{Type: r, Items: append([]Value{}, a[0].(*Set).Items...)}
	})
	add("set_entries", "List[List[T]]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*Set).Items
		out := make([]Value, len(items))
		typ := typeArguments(r)[0]
		for i, v := range items {
			CheckCancelled(ctx)
			out[i] = &List{Type: typ, Items: []Value{v, v}}
		}
		return &List{Type: r, Items: out}
	})
	add("set_for_each", "Unit", hash, []LibraryParam{p("values", "Set[T]"), p("operation", "fn(value:T)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		for _, v := range a[0].(*Set).Items {
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
			left, right := a[0].(*Set), a[1].(*Set)
			if name == "is_superset_of" {
				left, right = right, left
			}
			var out []Value
			for _, v := range left.Items {
				CheckCancelled(ctx)
				found := right.find(ctx, v) >= 0
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
			for _, v := range right.Items {
				CheckCancelled(ctx)
				if left.find(ctx, v) < 0 {
					out = append(out, v)
				}
			}
			return &Set{Type: r, Items: out}
		})
	}
}

func mapPut(ctx *Execution, values *Map, key, value Value) *Map {
	values.put(ctx, key, value)
	return values
}

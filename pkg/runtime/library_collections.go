package msruntime

import (
	"fmt"
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
	i := relativeIndex(list.Len(), index.(int64))
	value := Alternative{Type: result, Tag: "none"}
	if i >= 0 && i < int64(list.Len()) {
		value = Alternative{Type: result, Tag: "some", Fields: []Value{list.Get(int(i))}}
	}
	CheckCancelled(ctx)
	return value
}

// ListAtParts is ListAt without the Optional: the element and whether it exists.
func ListAtParts(ctx *Execution, receiver Value, index Value) (Value, bool) {
	CheckCancelled(ctx)
	list := receiver.(*List)
	i := relativeIndex(list.Len(), index.(int64))
	if i >= 0 && i < int64(list.Len()) {
		CheckCancelled(ctx)
		return list.Get(int(i)), true
	}
	CheckCancelled(ctx)
	return nil, false
}

// ListAtUnwrap is ListAt followed by Optional.unwrap without building the
// Optional: the element, or the unwrap fault when the index is out of range.
func ListAtUnwrap(ctx *Execution, receiver Value, index Value) Value {
	value, ok := ListAtParts(ctx, receiver, index)
	if !ok {
		return Panic(unwrapNoneMessage)
	}
	return value
}

// OptionalTag is the case tag of an Optional whose presence is present.
func OptionalTag(present bool) string {
	if present {
		return "some"
	}
	return "none"
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
	add("map_transform", "Map[K][W]", []LibraryParam{p("K", "Hashable"), p("V", ""), p("W", "")}, []LibraryParam{p("values", "Map[K][V]"), p("transform", "fn(key:K;value:V)->W")}, func(ctx *Execution, result string, args []Value) Value {
		out := &Map{Type: result}
		call := newCallback2(args[1], "key", "value")
		for _, entry := range args[0].(*Map).Entries {
			CheckCancelled(ctx)
			value := call.call2(ctx, args[1], entry.Key, entry.Value)
			out.Entries = append(out.Entries, Entry{Key: entry.Key, Value: value})
		}
		return out
	})
	add("map_transform_keys", "Map[W][V]", []LibraryParam{p("K", "Hashable"), p("V", ""), p("W", "Hashable")}, []LibraryParam{p("values", "Map[K][V]"), p("transform", "fn(key:K;value:V)->W")}, func(ctx *Execution, result string, args []Value) Value {
		out := &Map{Type: result}
		call := newCallback2(args[1], "key", "value")
		for _, entry := range args[0].(*Map).Entries {
			CheckCancelled(ctx)
			key := call.call2(ctx, args[1], entry.Key, entry.Value)
			out.put(ctx, key, entry.Value)
		}
		return out
	})
	add("map_fold_right", "A", []LibraryParam{p("K", "Hashable"), p("V", ""), p("A", "")}, []LibraryParam{p("values", "Map[K][V]"), p("initial", "A"), p("step", "fn(accumulator:A;key:K;value:V)->A")}, func(ctx *Execution, _ string, args []Value) Value {
		accumulator := args[1]
		call := newCallback3(args[2], "accumulator", "key", "value")
		entries := args[0].(*Map).Entries
		for i := len(entries) - 1; i >= 0; i-- {
			CheckCancelled(ctx)
			entry := entries[i]
			accumulator = call.call3(ctx, args[2], accumulator, entry.Key, entry.Value)
		}
		return accumulator
	})
	add("set_fold_right", "A", []LibraryParam{p("T", "Hashable"), p("A", "")}, []LibraryParam{p("values", "Set[T]"), p("initial", "A"), p("step", "fn(accumulator:A;value:T)->A")}, func(ctx *Execution, _ string, args []Value) Value {
		accumulator := args[1]
		call := newCallback2(args[2], "accumulator", "value")
		items := args[0].(*Set).Items
		for i := len(items) - 1; i >= 0; i-- {
			CheckCancelled(ctx)
			accumulator = call.call2(ctx, args[2], accumulator, items[i])
		}
		return accumulator
	})
	add("map_fold", "A", []LibraryParam{p("K", "Hashable"), p("V", ""), p("A", "")}, []LibraryParam{p("values", "Map[K][V]"), p("initial", "A"), p("step", "fn(accumulator:A;key:K;value:V)->A")}, func(ctx *Execution, _ string, a []Value) Value {
		accumulator := a[1]
		call := newCallback3(a[2], "accumulator", "key", "value")
		for _, entry := range a[0].(*Map).Entries {
			CheckCancelled(ctx)
			accumulator = call.call3(ctx, a[2], accumulator, entry.Key, entry.Value)
		}
		return accumulator
	})
	add("set_fold", "A", []LibraryParam{p("T", "Hashable"), p("A", "")}, []LibraryParam{p("values", "Set[T]"), p("initial", "A"), p("step", "fn(accumulator:A;value:T)->A")}, func(ctx *Execution, _ string, a []Value) Value {
		accumulator := a[1]
		call := newCallback2(a[2], "accumulator", "value")
		for _, value := range a[0].(*Set).Items {
			CheckCancelled(ctx)
			accumulator = call.call2(ctx, a[2], accumulator, value)
		}
		return accumulator
	})
	for _, kind := range []string{"map", "set"} {
		for _, name := range []string{"find", "find_last", "some", "every"} {
			vars := hash
			params := []LibraryParam{p("values", "Set[T]"), p("predicate", "fn(value:T)->Bool")}
			result := "Optional[T]"
			if kind == "map" {
				vars = mapVars
				params = []LibraryParam{p("values", "Map[K][V]"), p("predicate", "fn(key:K;value:V)->Bool")}
				result = "Optional[MapEntry[K][V]]"
			}
			if name != "find" && name != "find_last" {
				result = "Bool"
			}
			add(kind+"_"+name, result, vars, params, func(ctx *Execution, result string, args []Value) Value {
				return libraryCollectionQuery(ctx, kind, name, result, args)
			})
		}
	}
	add("map_is_empty", "Bool", mapVars, []LibraryParam{p("values", "Map[K][V]")}, func(_ *Execution, _ string, a []Value) Value {
		return len(a[0].(*Map).Entries) == 0
	})
	add("map_add", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("key", "K"), p("value", "V")}, func(ctx *Execution, _ string, a []Value) Value {
		return MapWithEntry(ctx, a[0], a[1], a[2], ctx.EqualityScope)
	})
	add("map_remove", "Map[K][V]", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("key", "K")}, func(ctx *Execution, _ string, a []Value) Value {
		return mapRemove(ctx, a[0].(*Map), a[1])
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
		call := newCallback2(a[1], "key", "value")
		for _, entry := range a[0].(*Map).Entries {
			CheckCancelled(ctx)
			if call.call2(ctx, a[1], entry.Key, entry.Value).(bool) {
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
		call := newCallback(a[1], "value")
		for _, value := range a[0].(*Set).Items {
			CheckCancelled(ctx)
			if call.call1(ctx, a[1], value).(bool) {
				out.Items = append(out.Items, value)
			}
		}
		return out
	})
	add("set_map", "Set[U]", []LibraryParam{p("T", "Hashable"), p("U", "Hashable")}, []LibraryParam{p("values", "Set[T]"), p("transform", "fn(value:T)->U")}, func(ctx *Execution, result string, a []Value) Value {
		out := &Set{Type: result}
		call := newCallback(a[1], "value")
		for _, value := range a[0].(*Set).Items {
			CheckCancelled(ctx)
			out.add(ctx, call.call1(ctx, a[1], value))
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
				i = int64(v.Len()) - 1
			}
			if name == "at" {
				i = a[1].(int64)
			}
			return ListAt(ctx, v, i, r)
		})
	}
	add("is_empty", "Bool", elements, listParam, func(ctx *Execution, _ string, a []Value) Value { return a[0].(*List).Len() == 0 })
	for _, name := range []string{"contains", "index_of", "last_index_of"} {
		result := "Optional[Int]"
		if name == "contains" {
			result = "Bool"
		}
		add(name, result, equal, []LibraryParam{p("values", "List[T]"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
			items := a[0].(*List).Capture()
			start, end, step := 0, items.Len(), 1
			if name == "last_index_of" {
				start, end, step = items.Len()-1, -1, -1
			}
			for i := start; i != end; i += step {
				CheckCancelled(ctx)
				if items.EqualAt(ctx, i, a[1], ctx.EqualityScope) {
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
		v.Append(a[1])
		v.copyWithin(1, 0, v.Len()-1)
		v.Set(0, a[1])
		return v
	})
	add("set", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Capture()
		i := relativeIndex(items.Len(), a[1].(int64))
		if i < 0 || i >= int64(items.Len()) {
			return libraryIndexFault("List.set", items.Len(), a[1].(int64))
		}
		a[0].(*List).Set(int(i), a[2])
		return a[0]
	})
	add("remove", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Capture()
		i := relativeIndex(items.Len(), a[1].(int64))
		if i < 0 || i >= int64(items.Len()) {
			return libraryIndexFault("List.remove", items.Len(), a[1].(int64))
		}
		list := a[0].(*List)
		list.copyWithin(int(i), int(i)+1, list.Len())
		list.truncate(list.Len() - 1)
		return a[0]
	})
	add("insert", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("index", "Int"), p("value", "T")}, func(ctx *Execution, r string, a []Value) Value {
		list := a[0].(*List)
		index := a[1].(int64)
		n := list.Len()
		i := relativeIndex(n, index)
		if i < 0 || i > int64(n) {
			return Panic(fmt.Sprintf("List.insert: index must be between %d and %d (negative indexes count from the end), found %d", -n, n, index))
		}
		list.Append(a[2])
		list.copyWithin(int(i)+1, int(i), n)
		list.Set(int(i), a[2])
		return list
	})
	add("pop", "Optional[T]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		list := a[0].(*List)
		if list.Len() == 0 {
			return Alternative{Type: r, Tag: "none"}
		}
		last := list.Get(list.Len() - 1)
		// Do not clear the tail: a running range retains its initial header.
		list.truncate(list.Len() - 1)
		return Alternative{r, "some", []Value{last}}
	})
	add("count", "Int", elements, []LibraryParam{p("values", "List[T]"), p("predicate", "fn(value:T)->Bool")}, func(ctx *Execution, _ string, a []Value) Value {
		count := int64(0)
		predicate := newCallback(a[1], "value")
		for _, value := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			if predicate.call1(ctx, a[1], value).(bool) {
				count++
			}
		}
		return count
	})
	add("distinct", "List[T]", equal, listParam, func(ctx *Execution, r string, a []Value) Value {
		out := NewList(r, nil)
		// Int and String equality is exact, so hash them instead of comparing every kept element.
		seenInts, seenStrings := map[int64]struct{}{}, map[string]struct{}{}
		for _, value := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			switch v := value.(type) {
			case int64:
				if _, dup := seenInts[v]; !dup {
					seenInts[v] = struct{}{}
					out.Append(value)
				}
				continue
			case string:
				if _, dup := seenStrings[v]; !dup {
					seenStrings[v] = struct{}{}
					out.Append(value)
				}
				continue
			}
			seen := false
			for i, kept := range out.Capture().Values() {
				if i%1024 == 1023 {
					CheckCancelled(ctx)
				}
				if EqualIn(ctx, kept, value) {
					seen = true
					break
				}
			}
			if !seen {
				out.Append(value)
			}
		}
		return out
	})
	add("set_add", "Set[T]", hash, []LibraryParam{p("values", "Set[T]"), p("value", "T")}, func(ctx *Execution, _ string, a []Value) Value {
		return setWithValue(ctx, a[0].(*Set), a[1])
	})
	add("set_remove", "Set[T]", hash, []LibraryParam{p("values", "Set[T]"), p("value", "T")}, func(ctx *Execution, _ string, a []Value) Value {
		return setRemove(ctx, a[0].(*Set), a[1])
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
			items := a[0].(*List).Capture()
			start, end, step := 0, items.Len(), 1
			if name == "find_last" || name == "find_last_index" {
				start, end, step = items.Len()-1, -1, -1
			}
			predicate := newCallback(a[1], "value")
			for i := start; i != end; i += step {
				CheckCancelled(ctx)
				value := items.Get(i)
				matches := predicate.call1(ctx, a[1], value).(bool)
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
		return listForEach(ctx, a[0].(*List), a[1])
	})
	add("flat_map", "List[U]", []LibraryParam{p("T", ""), p("U", "")}, []LibraryParam{p("values", "List[T]"), p("transform", "fn(value:T)->List[U]")}, func(ctx *Execution, r string, a []Value) Value {
		var out []Value
		transform := newCallback(a[1], "value")
		for _, v := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			out = append(out, transform.call1(ctx, a[1], v).(*List).Boxed()...)
		}
		return NewList(r, out)
	})
	add("fold_right", "A", []LibraryParam{p("T", ""), p("A", "")}, []LibraryParam{p("values", "List[T]"), p("initial", "A"), p("step", "fn(accumulator:A;value:T)->A")}, func(ctx *Execution, _ string, a []Value) Value {
		acc := a[1]
		items := a[0].(*List).Capture()
		step := newCallback2(a[2], "accumulator", "value")
		for i := items.Len() - 1; i >= 0; i-- {
			CheckCancelled(ctx)
			acc = step.call2(ctx, a[2], acc, items.Get(i))
		}
		return acc
	})
	add("splice", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("start", "Int"), p("delete_count", "Int"), p("replacement", "List[T]")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Capture()
		start, count := a[1].(int64), a[2].(int64)
		if start < 0 || start > int64(items.Len()) {
			return libraryRangeFault("List.splice", "start", start, 0, int64(items.Len()))
		}
		if count < 0 || count > int64(items.Len())-start {
			return libraryRangeFault("List.splice", "delete_count", count, 0, int64(items.Len())-start)
		}
		spliceList(a[0].(*List), int(start), int(count), a[3].(*List))
		return a[0]
	})
	add("fill", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("value", "T"), p("start", "Int"), p("end", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		list := a[0].(*List)
		s, e := a[2].(int64), a[3].(int64)
		librarySlice("List.fill", list.Len(), s, e)
		if s == e {
			return list
		}
		for i := s; i < e; i++ {
			CheckCancelled(ctx)
			list.Set(int(i), a[1])
		}
		return a[0]
	})
	add("copy_within", "List[T]", elements, []LibraryParam{p("values", "List[T]"), p("target", "Int"), p("start", "Int"), p("end", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		list := a[0].(*List)
		t, s, e := a[1].(int64), a[2].(int64), a[3].(int64)
		librarySlice("List.copy_within", list.Len(), s, e)
		if t < 0 || t > int64(list.Len()) {
			return libraryRangeFault("List.copy_within", "target", t, 0, int64(list.Len()))
		}
		if s == e || t == int64(list.Len()) {
			return list
		}
		list.copyWithin(int(t), int(s), int(e))
		return a[0]
	})
	add("list_keys", "List[Int]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		out := make([]Value, a[0].(*List).Len())
		for i := range out {
			CheckCancelled(ctx)
			out[i] = int64(i)
		}
		return NewList(r, out)
	})
	add("list_entries", "List[ListEntry[T]]", elements, listParam, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*List).Capture()
		out := make([]Value, items.Len())
		typ := typeArguments(r)[0]
		for i, v := range items.Values() {
			CheckCancelled(ctx)
			out[i] = Record{typ, map[string]Value{"index": int64(i), "value": v}}
		}
		return NewList(r, out)
	})
	add("to_set", "Set[T]", []LibraryParam{p("T", "Hashable")}, listParam, func(ctx *Execution, r string, a []Value) Value {
		out := &Set{Type: r}
		for _, v := range a[0].(*List).Capture().Values() {
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
		out := newList(typeArguments(r)[0])
		out.allocate(int(count))
		for i := 0; i < out.Len(); i++ {
			CheckCancelled(ctx)
			out.Set(i, a[0])
		}
		return libraryOK(r, out)
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
		return libraryOK(r, NewList(typeArguments(r)[0], out))
	})
	add("group_by", "Map[K][List[T]]", []LibraryParam{p("T", ""), p("K", "Hashable")}, []LibraryParam{p("values", "List[T]"), p("key", "fn(value:T)->K")}, func(ctx *Execution, r string, a []Value) Value {
		out := &Map{Type: r}
		listType := typeArguments(r)[1]
		keyOf := newCallback(a[1], "value")
		for _, v := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			key := keyOf.call1(ctx, a[1], v)
			found := out.find(ctx, key)
			if found < 0 {
				out.Entries = append(out.Entries, Entry{key, NewList(listType, []Value{v})})
				keyAppended(ctx, out)
			} else {
				group := out.Entries[found].Value.(*List)
				group.Append(v)
				out.Entries[found].Value = group
			}
		}
		return out
	})
	for _, name := range []string{"map_add_default", "map_add_default_from"} {
		params := []LibraryParam{p("values", "Map[K][V]"), p("key", "K"), p("value", "V")}
		if name == "map_add_default_from" {
			params[2] = p("create", "fn(key:K)->V")
		}
		add(name, "Map[K][V]", mapVars, params, func(ctx *Execution, r string, a []Value) Value {
			values := a[0].(*Map)
			if values.find(ctx, a[1]) >= 0 {
				return values
			}
			value := a[2]
			if name == "map_add_default_from" {
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
		return NewList(r, out)
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
		for _, v := range a[0].(*List).Capture().Values() {
			CheckCancelled(ctx)
			e := v.(Record)
			out = mapPut(ctx, out, e.Fields["key"], e.Fields["value"])
		}
		return out
	})
	add("map_for_each", "Unit", mapVars, []LibraryParam{p("values", "Map[K][V]"), p("operation", "fn(key:K;value:V)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		call := newCallback2(a[1], "key", "value")
		for _, e := range a[0].(*Map).Entries {
			CheckCancelled(ctx)
			call.call2(ctx, a[1], e.Key, e.Value)
		}
		return Unit{}
	})
	add("set_clear", "Set[T]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, _ string, a []Value) Value { a[0].(*Set).Items = nil; return a[0] })
	add("set_values", "List[T]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
		return NewList(r, append([]Value{}, a[0].(*Set).Items...))
	})
	add("set_entries", "List[List[T]]", hash, []LibraryParam{p("values", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
		items := a[0].(*Set).Items
		out := make([]Value, len(items))
		typ := typeArguments(r)[0]
		for i, v := range items {
			CheckCancelled(ctx)
			out[i] = NewList(typ, []Value{v, v})
		}
		return NewList(r, out)
	})
	add("set_for_each", "Unit", hash, []LibraryParam{p("values", "Set[T]"), p("operation", "fn(value:T)->Unit")}, func(ctx *Execution, _ string, a []Value) Value {
		call := newCallback(a[1], "value")
		for _, v := range a[0].(*Set).Items {
			CheckCancelled(ctx)
			call.call1(ctx, a[1], v)
		}
		return Unit{}
	})
	for _, name := range []string{"symmetric_difference", "is_subset_of", "is_superset_of", "is_disjoint_from"} {
		result := "Bool"
		if name == "symmetric_difference" {
			result = "Set[T]"
		}
		add(name, result, hash, []LibraryParam{p("left", "Set[T]"), p("other", "Set[T]")}, func(ctx *Execution, r string, a []Value) Value {
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

// Both receiver families share first-match and short-circuit semantics. The
// native invocation boundary has already snapshotted membership, retaining
// payload references; only a found Map entry gets a fresh record shell.
func libraryCollectionQuery(ctx *Execution, kind, name, result string, args []Value) Value {
	var entries []Entry
	var items []Value
	if kind == "map" {
		entries = args[0].(*Map).Entries
	} else {
		items = args[0].(*Set).Items
	}
	start, end, step := 0, len(entries)+len(items), 1
	if name == "find_last" {
		start, end, step = end-1, -1, -1
	}
	for i := start; i != end; i += step {
		CheckCancelled(ctx)
		var key, value Value
		var callbackArgs []Argument
		if kind == "map" {
			key, value = entries[i].Key, entries[i].Value
			callbackArgs = []Argument{{"key", key}, {"value", value}}
		} else {
			value = items[i]
			callbackArgs = []Argument{{"value", value}}
		}
		matches := Invoke(ctx, args[1], callbackArgs).(bool)
		if name == "every" {
			if !matches {
				return false
			}
		} else if matches {
			if name == "some" {
				return true
			}
			if kind == "map" {
				value = Record{Type: typeArguments(result)[0], Fields: map[string]Value{"key": key, "value": value}}
			}
			return Alternative{Type: result, Tag: "some", Fields: []Value{value}}
		}
	}
	if name == "every" {
		return true
	}
	if name == "some" {
		return false
	}
	return Alternative{Type: result, Tag: "none"}
}

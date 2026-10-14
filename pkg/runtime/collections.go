package msruntime

import (
	"fmt"
	"math"
	"math/big"
	"slices"
	"strconv"
	"unicode/utf8"
)

// MapLiteral inserts evaluated entries using the same equality and ordering as with_entry.
func MapLiteral(ctx *Execution, typ string, entries []Entry, scope TypeScope) *Map {
	child := *ctx
	if len(scope.Args) > 0 {
		child.EqualityScope = scope.Args[0]
	}
	result := &Map{Type: typ}
	for _, entry := range entries {
		CheckCancelled(&child)
		mapPut(&child, result, entry.Key, entry.Value)
	}
	return result
}

func spliceList(list *List, start, count int, replacement *List) {
	switch list.kind {
	case listInt:
		list.ints = spliceItems(list.ints, start, count, listInts(replacement), list == replacement)
	case listFloat:
		list.floats = spliceItems(list.floats, start, count, listFloats(replacement), list == replacement)
	case listBool:
		list.bools = spliceItems(list.bools, start, count, listBools(replacement), list == replacement)
	case listString:
		list.strings = spliceItems(list.strings, start, count, listStrings(replacement), list == replacement)
	default:
		items := replacement.Items
		if replacement.kind != listBoxed {
			items = replacement.Boxed()
		}
		list.Items = spliceItems(list.Items, start, count, items, list == replacement)
	}
}
func spliceItems[T any](items []T, start, count int, replacement []T, self bool) []T {
	if self {
		replacement = append([]T(nil), replacement...)
	}
	oldLength := len(items)
	newLength := oldLength - count + len(replacement)
	if newLength < oldLength-count {
		Panic("list replacement length overflow")
	}
	if newLength > oldLength {
		items = slices.Grow(items, newLength-oldLength)[:newLength]
	}
	copy(items[start+len(replacement):], items[start+count:oldLength])
	copy(items[start:], replacement)
	// Non-clearing reslice preserves valid values in captured traversal tails.
	return items[:newLength]
}

func optional(typ string, value Value, present bool) Value {
	if !present {
		return Alternative{Type: "@std/Optional[" + typ + "]", Tag: "none"}
	}
	return Alternative{Type: "@std/Optional[" + typ + "]", Tag: "some", Fields: []Value{value}}
}
func constructor(typ string, args []Argument) Value {
	name, _ := splitType(typ)
	switch name {
	case "@std/List":
		return newList(typ)
	case "@std/Map":
		return &Map{Type: typ}
	case "@std/Set":
		return &Set{Type: typ}
	case "@std/Bytes":
		values := args[0].Value.(*List).Boxed()
		bytes := make([]byte, len(values))
		for i, v := range values {
			n := v.(int64)
			if n < 0 || n > 255 {
				return libraryRangeFault("Bytes", fmt.Sprintf("values[%d]", i), n, 0, 255)
			}
			bytes[i] = byte(n)
		}
		return Bytes{bytes}
	}
	if fields := nativeOptionRecords[typ]; fields != nil {
		present := map[string]bool{}
		for _, arg := range args {
			present[arg.Name] = true
		}
		for name, fieldType := range fields {
			if !present[name] {
				args = append(args, Argument{name, optional(libraryRuntimeType(fieldType), nil, false)})
			}
		}
	}
	return NewRecord(typ, args)
}
func Construct(typ string, args []Argument) Value { return constructor(typ, args) }

// CollectionLength is the direct path for List, Map, and Set length calls.
func CollectionLength(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	switch v := receiver.(type) {
	case *List:
		return int64(v.Len())
	case *Map:
		return int64(len(v.Entries))
	case *Set:
		return int64(len(v.Items))
	}
	return Panic("runtime invariant: collection receiver")
}

// ListAppend is the direct path for List.append calls.
func ListAppend(ctx *Execution, receiver, value Value) Value {
	CheckCancelled(ctx)
	list := receiver.(*List)
	list.Append(value)
	return list
}

// ListIsEmpty is the direct path for List.is_empty calls.
func ListIsEmpty(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	return receiver.(*List).Len() == 0
}

// keyContext selects the equality scope for a keyed lookup. Primitive keys
// compare without it, so only composite keys pay for the context copy.
func keyContext(ctx *Execution, key Value, scope TypeScope) *Execution {
	switch key.(type) {
	case int64, string:
		return ctx
	}
	child := *ctx
	child.EqualityScope = scope
	return &child
}

// ListContains is the direct path for List.contains calls.
func ListContains(ctx *Execution, receiver, value Value, scope TypeScope) Value {
	items := receiver.(*List).Capture()
	for i := 0; i < items.Len(); i++ {
		CheckCancelled(ctx)
		if items.EqualAt(ctx, i, value, scope) {
			return true
		}
	}
	return false
}

// MapContains is the direct path for Map.contains calls.
func MapContains(ctx *Execution, receiver, key Value, scope TypeScope) Value {
	CheckCancelled(ctx)
	return receiver.(*Map).find(keyContext(ctx, key, scope), key) >= 0
}

// MapGet is the direct path for Map.get calls.
func MapGet(ctx *Execution, receiver, key Value, scope TypeScope, result string) Value {
	CheckCancelled(ctx)
	m := receiver.(*Map)
	found := m.find(keyContext(ctx, key, scope), key)
	if found < 0 {
		return Alternative{Type: result, Tag: "none"}
	}
	return Alternative{Type: result, Tag: "some", Fields: []Value{m.Entries[found].Value}}
}

// MapWithEntry is the direct path for Map.with_entry calls.
func MapWithEntry(ctx *Execution, receiver, key, value Value, scope TypeScope) Value {
	CheckCancelled(ctx)
	m := receiver.(*Map)
	child := keyContext(ctx, key, scope)
	if found := m.find(child, key); found >= 0 {
		m.ownEntries()
		m.Entries[found].Value = value
	} else {
		m.Entries = append(m.Entries, Entry{key, value})
		keyAppended(child, m)
	}
	return m
}

// MapRemove retains insertion order and returns the mutable receiver.
func MapRemove(ctx *Execution, receiver, key Value, scope TypeScope) Value {
	CheckCancelled(ctx)
	return mapRemove(keyContext(ctx, key, scope), receiver.(*Map), key)
}

// Bound members already select their key's equality scope.
func mapRemove(ctx *Execution, m *Map, key Value) Value {
	if found := m.find(ctx, key); found >= 0 {
		m.removeAt(ctx, found)
	}
	return m
}

// SetContains is the direct path for Set.contains calls.
func SetContains(ctx *Execution, receiver, value Value, scope TypeScope) Value {
	CheckCancelled(ctx)
	return receiver.(*Set).find(keyContext(ctx, value, scope), value) >= 0
}

// SetWithValue is the direct path for Set.with_value and Set.add calls.
func SetWithValue(ctx *Execution, receiver, value Value, scope TypeScope) Value {
	CheckCancelled(ctx)
	return setWithValue(keyContext(ctx, value, scope), receiver.(*Set), value)
}

// Bound native members already select their equality scope at invocation.
func setWithValue(ctx *Execution, s *Set, value Value) Value {
	if s.find(ctx, value) < 0 {
		s.Items = append(s.Items, value)
		keyAppended(ctx, s)
	}
	return s
}

// SetRemove retains insertion order and returns the mutable receiver.
func SetRemove(ctx *Execution, receiver, value Value, scope TypeScope) Value {
	CheckCancelled(ctx)
	return setRemove(keyContext(ctx, value, scope), receiver.(*Set), value)
}

func setRemove(ctx *Execution, s *Set, value Value) Value {
	if found := s.find(ctx, value); found >= 0 {
		s.removeAt(ctx, found)
	}
	return s
}

// StringByteLength is the direct path for String.byte_length calls.
func StringByteLength(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	return int64(len(receiver.(string)))
}

func NativeMember(receiver Value, name string) Value {
	return NativeMemberResult(receiver, name, "")
}
func NativeMemberResult(receiver Value, name, result string, scopes ...TypeScope) Value {
	if len(scopes) > 0 {
		original := NativeMemberResult(receiver, name, result).(Function)
		originalBody := original.Body
		// Scoped adaptation does not inherit the compiled body proof.
		original.BorrowedArguments = false
		original.Body = func(ctx *Execution, args []Value) Value {
			child := *ctx
			child.EqualityScope = scopes[0]
			if len(scopes[0].Args) > 0 {
				child.EqualityScope = scopes[0].Args[0]
			}
			// Key/element transformations deduplicate outputs, whose evidence
			// can differ from the receiver key/element's scope.
			_, set := receiver.(*Set)
			_, mapping := receiver.(*Map)
			outputKeys := set && name == "map" || mapping && name == "map_keys"
			if outputKeys && len(scopes) > 1 && len(scopes[1].Args) > 0 {
				child.EqualityScope = scopes[1].Args[0]
			}
			return originalBody(&child, args)
		}
		return original
	}
	if name == "equals" {
		return NewFunction([]string{"other"}, "Bool", func(ctx *Execution, args []Value) Value { return EqualIn(ctx, receiver, args[0]) })
	}
	if name == "hash" {
		return NewFunction(nil, "Int", func(ctx *Execution, _ []Value) Value { return HashIn(ctx, receiver) })
	}

	if name == "clone" {
		return NewFunction(nil, result, func(_ *Execution, _ []Value) Value { return Clone(receiver) })
	}
	if name == "toString" {
		return NewFunction(nil, "String", func(_ *Execution, _ []Value) Value { return Format(receiver) })
	}
	if function, ok := nativeLibraryMember(receiver, name, result); ok {
		return function
	}
	if native, ok := receiver.(Native); ok {
		return native.Operation(name)
	}
	if name == "milliseconds" || name == "seconds" || name == "minutes" {
		return duration(receiver, name)
	}
	labels := []string{}
	switch name {
	case "get":
		labels = []string{"index"}
		if _, ok := receiver.(*Map); ok {
			labels = []string{"key"}
		}
	case "append", "contains", "with_value":
		labels = []string{"value"}
		if _, ok := receiver.(*Map); ok {
			labels = []string{"key"}
		}
	case "concat":
		labels = []string{"values"}
	case "without":
		labels = []string{"value"}
		if _, ok := receiver.(*Map); ok {
			labels = []string{"key"}
		}
	case "with_entry":
		labels = []string{"key", "value"}
	}
	return NewFunction(labels, "", func(ctx *Execution, args []Value) Value {
		switch v := receiver.(type) {
		case *List:
			switch name {
			case "length":
				return int64(v.Len())
			case "append":
				v.Append(args[0])
				return v
			case "concat":
				out := v.CopySlice(0, v.Len())
				out.appendList(args[0].(*List))
				return out
			}
		case *Map:
			if name == "without" {
				return mapRemove(ctx, v, args[0])
			}
			typ := typeArguments(v.Type)[1]
			var key Value
			if len(args) > 0 {
				key = args[0]
			}
			found := -1
			if name != "length" {
				found = v.find(ctx, key)
			}
			switch name {
			case "length":
				return int64(len(v.Entries))
			case "contains":
				return found >= 0
			case "get":
				if found < 0 {
					return optional(typ, nil, false)
				}
				return optional(typ, v.Entries[found].Value, true)
			case "with_entry":
				if found >= 0 {
					v.ownEntries()
					v.Entries[found].Value = args[1]
				} else {
					v.Entries = append(v.Entries, Entry{key, args[1]})
					keyAppended(ctx, v)
				}
				return v
			}
		case *Set:
			if name == "with_value" {
				return setWithValue(ctx, v, args[0])
			}
			if name == "without" {
				return setRemove(ctx, v, args[0])
			}
			var value Value
			if len(args) > 0 {
				value = args[0]
			}
			found := -1
			if name != "length" {
				found = v.find(ctx, value)
			}
			switch name {
			case "length":
				return int64(len(v.Items))
			case "contains":
				return found >= 0
			}
		case string:
			switch name {
			case "byte_length":
				return int64(len(v))
			case "to_bytes":
				return Bytes{[]byte(v)}
			case "parse_int":
				if v == "" {
					return optional("Int", nil, false)
				}
				start := 0
				if v[0] == '+' || v[0] == '-' {
					start = 1
				}
				if start == len(v) {
					return optional("Int", nil, false)
				}
				for i := start; i < len(v); i++ {
					if v[i] < '0' || v[i] > '9' {
						return optional("Int", nil, false)
					}
				}
				n, err := strconv.ParseInt(v, 10, 64)
				return optional("Int", n, err == nil)
			}
		case Bytes:
			switch name {
			case "length":
				return int64(len(v.Items))
			case "concat":
				return Bytes{append(append([]byte{}, v.Items...), args[0].(Bytes).Items...)}
			case "to_text":
				return optional("String", string(v.Items), utf8.Valid(v.Items))
			}
		case int64:
			switch name {
			case "to_float":
				return float64(v)
			case "to_decimal":
				return DecimalLiteral(strconv.FormatInt(v, 10))
			}
		case float64:
			if name == "truncate_to_int" {
				if math.IsNaN(v) || math.IsInf(v, 0) || v >= 9223372036854775808.0 || v < -9223372036854775808.0 {
					return optional("Int", nil, false)
				}
				return optional("Int", int64(v), true)
			}
		case Decimal:
			switch name {
			case "to_float":
				f, _ := v.Value.Float64()
				return f
			case "truncate_to_int":
				n := v.Value.Num()
				d := v.Value.Denom()
				q := new(big.Int).Quo(n, d)
				if !q.IsInt64() {
					return optional("Int", nil, false)
				}
				return optional("Int", q.Int64(), true)
			}
		}
		return Panic("runtime invariant: unavailable member " + name)
	})
}

// Index implements List bracket lookup with the same Optional result as at.
func Index(value, index Value) Value {
	list := value.(*List)
	_, types := splitType(list.Type)
	i := relativeIndex(list.Len(), index.(int64))
	if i < 0 || i >= int64(list.Len()) {
		return optional(types[0], nil, false)
	}
	return optional(types[0], list.Get(int(i)), true)
}

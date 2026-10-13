package msruntime

import (
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
	items := replacement.Items
	if list == replacement {
		items = append([]Value{}, items...)
	}
	oldLength := len(list.Items)
	newLength := oldLength - count + len(items)
	if newLength < oldLength-count {
		Panic("list replacement length overflow")
	}
	if newLength > oldLength {
		list.Items = slices.Grow(list.Items, newLength-oldLength)[:newLength]
	}
	copy(list.Items[start+len(items):], list.Items[start+count:oldLength])
	copy(list.Items[start:], items)
	if newLength < oldLength {
		clear(list.Items[newLength:])
		list.Items = list.Items[:newLength]
	}
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
		return &List{Type: typ}
	case "@std/Map":
		return &Map{Type: typ}
	case "@std/Set":
		return &Set{Type: typ}
	case "@std/Bytes":
		values := args[0].Value.(*List).Items
		bytes := make([]byte, len(values))
		for i, v := range values {
			n := v.(int64)
			if n < 0 || n > 255 {
				return Panic("byte value must be between 0 and 255; clamp or validate the Int before storing it as a byte")
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
func NativeMember(receiver Value, name string) Value {
	return NativeMemberResult(receiver, name, "")
}
func NativeMemberResult(receiver Value, name, result string, scopes ...TypeScope) Value {
	if len(scopes) > 0 {
		original := NativeMemberResult(receiver, name, result).(Function)
		originalBody := original.Body
		original.Body = func(ctx *Execution, args []Value) Value {
			child := *ctx
			child.EqualityScope = scopes[0]
			if len(scopes[0].Args) > 0 {
				child.EqualityScope = scopes[0].Args[0]
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
				return int64(len(v.Items))
			case "append":
				v.Items = append(v.Items, args[0])
				return v
			case "concat":
				return &List{v.Type, append(append([]Value{}, v.Items...), args[0].(*List).Items...)}
			}
		case *Map:
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
					v.Entries[found].Value = args[1]
				} else {
					v.Entries = append(v.Entries, Entry{key, args[1]})
					keyAppended(ctx, v)
				}
				return v
			case "without":
				if found >= 0 {
					v.removeAt(ctx, found)
				}
				return v
			}
		case *Set:
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
			case "with_value":
				if found < 0 {
					v.Items = append(v.Items, value)
					keyAppended(ctx, v)
				}
				return v
			case "without":
				if found >= 0 {
					v.removeAt(ctx, found)
				}
				return v
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
	i := relativeIndex(len(list.Items), index.(int64))
	if i < 0 || i >= int64(len(list.Items)) {
		return optional(types[0], nil, false)
	}
	return optional(types[0], list.Items[i], true)
}

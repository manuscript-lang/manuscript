package msruntime

import (
	"math"
	"math/big"
	"strconv"
	"unicode/utf8"
)

func optional(typ string, value Value, present bool) Value {
	if !present {
		return Alternative{Type: "@std/Optional[" + typ + "]", Tag: "none"}
	}
	return Alternative{Type: "@std/Optional[" + typ + "]", Tag: "some", Fields: []Value{value}}
}
func constructor(typ string, args []Argument) Value {
	name, _, _ := splitType(typ)
	switch name {
	case "@std/Map":
		return Map{Type: typ}
	case "@std/Set":
		return Set{Type: typ}
	case "@std/Bytes":
		values := args[0].Value.(List).Items
		bytes := make([]byte, len(values))
		for i, v := range values {
			n := v.(int64)
			if n < 0 || n > 255 {
				return Panic("byte value must be between 0 and 255")
			}
			bytes[i] = byte(n)
		}
		return Bytes{bytes}
	}
	return NewRecord(typ, args)
}
func Construct(typ string, args []Argument) Value { return constructor(typ, args) }
func NativeMember(receiver Value, name string) Value {
	return NativeMemberResult(receiver, name, "")
}
func NativeMemberResult(receiver Value, name, result string) Value {
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
		if _, ok := receiver.(Map); ok {
			labels = []string{"key"}
		}
	case "append", "contains", "with_value":
		labels = []string{"value"}
		if _, ok := receiver.(Map); ok {
			labels = []string{"key"}
		}
	case "concat":
		labels = []string{"values"}
	case "without":
		labels = []string{"value"}
		if _, ok := receiver.(Map); ok {
			labels = []string{"key"}
		}
	case "with_entry":
		labels = []string{"key", "value"}
	}
	return NewFunction(labels, "", func(ctx *Execution, args []Value) Value {
		switch v := receiver.(type) {
		case List:
			element := typeArguments(v.Type)[0]
			switch name {
			case "length":
				return int64(len(v.Items))
			case "get":
				i := args[0].(int64)
				if i < 0 || i >= int64(len(v.Items)) {
					return optional(element, nil, false)
				}
				return optional(element, v.Items[i], true)
			case "append":
				values := append(append([]Value{}, v.Items...), args[0])
				return List{v.Type, values}
			case "concat":
				return List{v.Type, append(append([]Value{}, v.Items...), args[0].(List).Items...)}
			}
		case Map:
			typ := typeArguments(v.Type)[1]
			var key Value
			if len(args) > 0 {
				key = args[0]
			}
			found := -1
			for i, e := range v.Entries {
				if Equal(e.Key, key) {
					found = i
					break
				}
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
				entries := append([]Entry{}, v.Entries...)
				if found >= 0 {
					entries[found].Value = args[1]
				} else {
					entries = append(entries, Entry{key, args[1]})
				}
				return Map{v.Type, entries}
			case "without":
				entries := append([]Entry{}, v.Entries...)
				if found >= 0 {
					entries = append(entries[:found], entries[found+1:]...)
				}
				return Map{v.Type, entries}
			}
		case Set:
			var value Value
			if len(args) > 0 {
				value = args[0]
			}
			found := indexOf(v.Items, value)
			switch name {
			case "length":
				return int64(len(v.Items))
			case "contains":
				return found >= 0
			case "with_value":
				items := append([]Value{}, v.Items...)
				if found < 0 {
					items = append(items, value)
				}
				return Set{v.Type, items}
			case "without":
				items := append([]Value{}, v.Items...)
				if found >= 0 {
					items = append(items[:found], items[found+1:]...)
				}
				return Set{v.Type, items}
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
			case "get":
				i := args[0].(int64)
				if i < 0 || i >= int64(len(v.Items)) {
					return optional("Int", nil, false)
				}
				return optional("Int", int64(v.Items[i]), true)
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

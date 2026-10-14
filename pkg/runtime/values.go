// Package msruntime implements the checked operations used by generated Go.
package msruntime

import (
	"fmt"
	"iter"
	"slices"
	"strings"
)

type Value = any

type Unit struct{}

type Record struct {
	Type   string
	Fields map[string]Value
}

type Alternative struct {
	Type, Tag string
	Fields    []Value
}

// List is the authoritative mutable identity. Items is the boxed fallback for
// Go callers; typed Lists use exactly one private primitive backing slice.
// Use constructors and accessors rather than inspecting Items.
type List struct {
	Type         string
	Items        []Value
	kind         uint8
	initializing bool
	ints         []int64
	floats       []float64
	bools        []bool
	strings      []string
}

type Map struct {
	Type    string
	Entries []Entry
	keys    keyIndex
	// shared marks Entries as visible to a running for-loop; in-place writes must clone first.
	shared bool
}

type Entry struct{ Key, Value Value }

type Set struct {
	Type  string
	Items []Value
	keys  keyIndex
	// shared marks Items as visible to a running for-loop; in-place writes must clone first.
	shared bool
}

type Bytes struct{ Items []byte }

type Duration int64

type Instant struct {
	Domain *clockDomain
	Tick   int64
}

//lint:ignore U1000 A nonzero size keeps distinct clock-domain pointers distinguishable.
type clockDomain struct{ identity byte }

type Fault struct {
	Message   string
	Secondary []string
	Frames    []string
	Truncated bool
}

func (f Fault) Error() string {
	message := f.Message
	if len(f.Secondary) > 0 {
		message += "; cleanup faults: " + strings.Join(f.Secondary, "; ")
	}
	if len(f.Frames) > 0 {
		message += "\n  at " + strings.Join(f.Frames, "\n  at ")
	}
	if f.Truncated {
		message += "\n  ... outer frames omitted"
	}
	return message
}

func Panic(message string) Value { panic(newFault(message)) }

// newFault records the source frames of the stack that raises it.
func newFault(message string) Fault {
	frames, truncated := captureFrames()
	return Fault{Message: message, Frames: frames, Truncated: truncated}
}

func Bool(v Value) bool {
	if b, ok := v.(bool); ok {
		return b
	}
	Panic("runtime invariant: expected Bool")
	return false
}

// ListTable backs one large list literal whose items are all scalar
// constants. Generated code keeps the items as pointer-free package data, so
// the Go compiler and the garbage collector see one plain array instead of an
// expression or interface value per item. Every evaluation returns a List
// with its own fresh typed storage copied from that data.
type ListTable[T int64 | float64 | bool | string] struct{}

func (t *ListTable[T]) List(typ string, data []T) *List {
	l := newList(typ)
	switch d := any(data).(type) {
	case []int64:
		if l.kind == listInt {
			l.ints = slices.Clone(d)
			return l
		}
	case []float64:
		if l.kind == listFloat {
			l.floats = slices.Clone(d)
			return l
		}
	case []bool:
		if l.kind == listBool {
			l.bools = slices.Clone(d)
			return l
		}
	case []string:
		if l.kind == listString {
			l.strings = slices.Clone(d)
			return l
		}
	}
	items := make([]Value, len(data))
	for i, item := range data {
		items[i] = item
	}
	return &List{Type: typ, Items: items}
}

func NewRecord(typ string, args []Argument) Value {
	if build := structFactories[typ]; build != nil {
		s := build()
		for _, arg := range args {
			s.StructSet(structIndex(s, arg.Name), arg.Value)
		}
		return s
	}
	fields := map[string]Value{}
	for _, arg := range args {
		fields[arg.Name] = arg.Value
	}
	return Record{typ, fields}
}

func NewAlternative(typ, tag string, labels []string, args []Argument) Value {
	values := make([]Value, len(labels))
	for _, a := range args {
		for i, label := range labels {
			if a.Name == label {
				values[i] = a.Value
			}
		}
	}
	return Alternative{typ, tag, values}
}

func Field(value Value, name string) Value {
	if s, ok := value.(Struct); ok {
		return s.StructGet(structIndex(s, name))
	}
	return readField(value.(Record).Fields, name)
}

func SetField(value Value, name string, field Value) {
	if s, ok := value.(Struct); ok {
		s.StructSet(structIndex(s, name), field)
		return
	}
	writeField(value.(Record).Fields, name, field)
}

func Tag(value Value) string { return value.(Alternative).Tag }

func Payload(value Value, index int) Value { return value.(Alternative).Fields[index] }

func Positions(value Value, length int) []Value {
	var values []Value
	switch v := value.(type) {
	case *List:
		values = v.Boxed()
	default:
		Panic("runtime invariant: positional binding")
	}
	if len(values) != length {
		Panic(fmt.Sprintf("destructuring length mismatch; the pattern binds %d names but the list has %d elements", length, len(values)))
	}
	return values
}

// Iterate remains rangeable for previously emitted programs. New primitive
// lowering can use CaptureList plus typed element access without boxing.
func Iterate(value Value) iter.Seq2[int, Value] { return captureIterable(value).Values() }

func CaptureList(value Value) ListRange { return value.(*List).Capture() }

// IterateInt, IterateFloat, IterateBool and IterateString are Iterate for a
// primitive element type.
func IterateInt(value Value) iter.Seq2[int, int64]     { return captureIterable(value).Ints() }
func IterateFloat(value Value) iter.Seq2[int, float64] { return captureIterable(value).Floats() }
func IterateBool(value Value) iter.Seq2[int, bool]     { return captureIterable(value).Bools() }
func IterateString(value Value) iter.Seq2[int, string] { return captureIterable(value).Strings() }

func captureIterable(value Value) ListRange {
	switch v := value.(type) {
	case *List:
		return v.Capture()
	case *Set:
		v.shared = true
		return ListRange{List{Items: v.Items[:len(v.Items):len(v.Items)]}}
	case *Map:
		values := make([]Value, len(v.Entries))
		args := typeArguments(v.Type)
		typ := "@std/MapEntry[" + args[0] + "][" + args[1] + "]"
		for i, e := range v.Entries {
			values[i] = Record{typ, map[string]Value{"key": e.Key, "value": e.Value}}
		}
		return ListRange{List{Items: values}}
	}
	Panic("runtime invariant: iterable")
	return ListRange{}
}

func sameClock(a, b Instant) {
	if a.Domain != b.Domain {
		Panic("instants belong to different clock domains")
	}
}

// structValue converts a generated struct to its record snapshot.
func structValue(v Value) Value {
	if s, ok := v.(Struct); ok {
		return structRecord(s)
	}
	return v
}

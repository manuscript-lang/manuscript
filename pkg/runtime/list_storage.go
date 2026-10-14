package msruntime

import (
	"iter"
	"slices"
)

// ListRange captures a backing header and its initial length without copying
// elements. It deliberately retains the old array across receiver reallocation.
type ListRange struct{ list List }

func (l *List) Capture() ListRange  { return ListRange{*l} }
func (r ListRange) Len() int        { return r.list.Len() }
func (r ListRange) Get(i int) Value { return r.list.Get(i) }
func (r ListRange) Values() iter.Seq2[int, Value] {
	return func(yield func(int, Value) bool) {
		for i := 0; i < r.Len(); i++ {
			if !yield(i, r.Get(i)) {
				return
			}
		}
	}
}

// Ints, Floats, Bools and Strings iterate a captured range of that primitive
// element type without boxing each element.
func (r ListRange) Ints() iter.Seq2[int, int64] {
	return func(yield func(int, int64) bool) {
		if r.list.kind == listInt {
			for i, v := range r.list.ints {
				if !yield(i, v) {
					return
				}
			}
			return
		}
		for i := 0; i < r.Len(); i++ {
			if !yield(i, r.Get(i).(int64)) {
				return
			}
		}
	}
}
func (r ListRange) Floats() iter.Seq2[int, float64] {
	return func(yield func(int, float64) bool) {
		if r.list.kind == listFloat {
			for i, v := range r.list.floats {
				if !yield(i, v) {
					return
				}
			}
			return
		}
		for i := 0; i < r.Len(); i++ {
			if !yield(i, r.Get(i).(float64)) {
				return
			}
		}
	}
}
func (r ListRange) Bools() iter.Seq2[int, bool] {
	return func(yield func(int, bool) bool) {
		if r.list.kind == listBool {
			for i, v := range r.list.bools {
				if !yield(i, v) {
					return
				}
			}
			return
		}
		for i := 0; i < r.Len(); i++ {
			if !yield(i, r.Get(i).(bool)) {
				return
			}
		}
	}
}
func (r ListRange) Strings() iter.Seq2[int, string] {
	return func(yield func(int, string) bool) {
		if r.list.kind == listString {
			for i, v := range r.list.strings {
				if !yield(i, v) {
					return
				}
			}
			return
		}
		for i := 0; i < r.Len(); i++ {
			if !yield(i, r.Get(i).(string)) {
				return
			}
		}
	}
}

// NewList copies checked values into one authoritative backing representation.
// A dynamic or heterogeneous payload remains boxed; no boxed mirror is kept.
func NewList(typ string, values []Value) *List {
	l := newList(typ)
	for _, v := range values {
		if !l.accepts(v) {
			l.kind = listBoxed
			l.Items = append([]Value(nil), values...)
			return l
		}
	}
	l.allocate(len(values))
	for i, v := range values {
		l.Set(i, v)
	}
	return l
}
func newList(typ string) *List {
	l := &List{Type: typ}
	switch typ {
	case "@std/List[Int]":
		l.kind = listInt
	case "@std/List[Float]":
		l.kind = listFloat
	case "@std/List[Bool]":
		l.kind = listBool
	case "@std/List[String]":
		l.kind = listString
	}
	return l
}

const (
	listBoxed uint8 = iota
	listInt
	listFloat
	listBool
	listString
)

func (l *List) accepts(v Value) bool {
	switch l.kind {
	case listInt:
		_, ok := v.(int64)
		return ok
	case listFloat:
		_, ok := v.(float64)
		return ok
	case listBool:
		_, ok := v.(bool)
		return ok
	case listString:
		_, ok := v.(string)
		return ok
	}
	return true
}
func (l *List) Len() int {
	switch l.kind {
	case listInt:
		return len(l.ints)
	case listFloat:
		return len(l.floats)
	case listBool:
		return len(l.bools)
	case listString:
		return len(l.strings)
	}
	return len(l.Items)
}
func (l *List) Cap() int {
	switch l.kind {
	case listInt:
		return cap(l.ints)
	case listFloat:
		return cap(l.floats)
	case listBool:
		return cap(l.bools)
	case listString:
		return cap(l.strings)
	}
	return cap(l.Items)
}
func (l *List) Get(i int) Value {
	switch l.kind {
	case listInt:
		return l.ints[i]
	case listFloat:
		return l.floats[i]
	case listBool:
		return l.bools[i]
	case listString:
		return l.strings[i]
	}
	return l.Items[i]
}
func (l *List) Append(v Value) {
	switch l.kind {
	case listInt:
		l.ints = append(l.ints, v.(int64))
	case listFloat:
		l.floats = append(l.floats, v.(float64))
	case listBool:
		l.bools = append(l.bools, v.(bool))
	case listString:
		l.strings = append(l.strings, v.(string))
	default:
		l.Items = append(l.Items, v)
	}
}
func (l *List) Set(i int, v Value) {
	switch l.kind {
	case listInt:
		l.ints[i] = v.(int64)
	case listFloat:
		l.floats[i] = v.(float64)
	case listBool:
		l.bools[i] = v.(bool)
	case listString:
		l.strings[i] = v.(string)
	default:
		l.Items[i] = v
	}
}
func (l *List) truncate(n int) {
	switch l.kind {
	case listInt:
		l.ints = l.ints[:n]
	case listFloat:
		l.floats = l.floats[:n]
	case listBool:
		l.bools = l.bools[:n]
	case listString:
		l.strings = l.strings[:n]
	default:
		l.Items = l.Items[:n]
	}
}
func (l *List) copyWithin(target, start, end int) {
	switch l.kind {
	case listInt:
		copy(l.ints[target:], l.ints[start:end])
	case listFloat:
		copy(l.floats[target:], l.floats[start:end])
	case listBool:
		copy(l.bools[target:], l.bools[start:end])
	case listString:
		copy(l.strings[target:], l.strings[start:end])
	default:
		copy(l.Items[target:], l.Items[start:end])
	}
}
func (l *List) reverse() {
	for i, j := 0, l.Len()-1; i < j; i, j = i+1, j-1 {
		l.swap(i, j)
	}
}
func (l *List) swap(i, j int) {
	switch l.kind {
	case listInt:
		l.ints[i], l.ints[j] = l.ints[j], l.ints[i]
	case listFloat:
		l.floats[i], l.floats[j] = l.floats[j], l.floats[i]
	case listBool:
		l.bools[i], l.bools[j] = l.bools[j], l.bools[i]
	case listString:
		l.strings[i], l.strings[j] = l.strings[j], l.strings[i]
	default:
		l.Items[i], l.Items[j] = l.Items[j], l.Items[i]
	}
}

// CopySlice creates independent shallow storage, unlike Capture.
func (l *List) CopySlice(start, end int) *List {
	switch l.kind {
	case listInt:
		return NewIntList(l.Type, l.ints[start:end])
	case listFloat:
		return NewFloatList(l.Type, l.floats[start:end])
	case listBool:
		return NewBoolList(l.Type, l.bools[start:end])
	case listString:
		return NewStringList(l.Type, l.strings[start:end])
	}
	return &List{Type: l.Type, Items: append([]Value(nil), l.Items[start:end]...)}
}

// Boxed copies values only for an explicitly boxed boundary. It is never a
// mutable mirror and must not be used to implement traversal or list writers.
func (l *List) Boxed() []Value {
	out := make([]Value, l.Len())
	for i := range out {
		out[i] = l.Get(i)
	}
	return out
}
func (l *List) appendList(other *List) {
	if l.kind == other.kind {
		switch l.kind {
		case listInt:
			l.ints = append(l.ints, other.ints...)
		case listFloat:
			l.floats = append(l.floats, other.floats...)
		case listBool:
			l.bools = append(l.bools, other.bools...)
		case listString:
			l.strings = append(l.strings, other.strings...)
		default:
			l.Items = append(l.Items, other.Items...)
		}
		return
	}
	for _, v := range other.Capture().Values() {
		l.Append(v)
	}
}

// NewIntList copies values into fresh mutable backing; typ is the exact checked key.
func NewIntList(typ string, values []int64) *List {
	return &List{Type: typ, kind: listInt, ints: append([]int64(nil), values...)}
}

// ListAppendInt is the unboxed primitive append boundary.
func ListAppendInt(ctx *Execution, receiver Value, value int64) Value {
	CheckCancelled(ctx)
	l := receiver.(*List)
	if l.kind == listInt {
		l.ints = append(l.ints, value)
	} else {
		l.Append(value)
	}
	return l
}

type IntOptional struct {
	Value   int64
	Present bool
}

func (o IntOptional) Box(result string) Alternative {
	if !o.Present {
		return Alternative{Type: result, Tag: "none"}
	}
	return Alternative{Type: result, Tag: "some", Fields: []Value{o.Value}}
}
func (o IntOptional) Unwrap(ctx *Execution) int64 {
	CheckCancelled(ctx)
	if !o.Present {
		Panic("called Optional.unwrap() on none; check is_some() first, or use unwrap_or(fallback: ...) to supply a default")
	}
	CheckCancelled(ctx)
	return o.Value
}
func ListAtInt(ctx *Execution, receiver Value, index int64) IntOptional {
	CheckCancelled(ctx)
	l := receiver.(*List)
	i := relativeIndex(l.Len(), index)
	o := IntOptional{}
	if i >= 0 && i < int64(l.Len()) {
		o.Present = true
		if l.kind == listInt {
			o.Value = l.ints[i]
		} else {
			o.Value = l.Get(int(i)).(int64)
		}
	}
	CheckCancelled(ctx)
	return o
}

// NewFloatList copies values into fresh mutable backing; typ is the exact checked key.
func NewFloatList(typ string, values []float64) *List {
	return &List{Type: typ, kind: listFloat, floats: append([]float64(nil), values...)}
}

// ListAppendFloat is the unboxed primitive append boundary.
func ListAppendFloat(ctx *Execution, receiver Value, value float64) Value {
	CheckCancelled(ctx)
	l := receiver.(*List)
	if l.kind == listFloat {
		l.floats = append(l.floats, value)
	} else {
		l.Append(value)
	}
	return l
}

type FloatOptional struct {
	Value   float64
	Present bool
}

func (o FloatOptional) Box(result string) Alternative {
	if !o.Present {
		return Alternative{Type: result, Tag: "none"}
	}
	return Alternative{Type: result, Tag: "some", Fields: []Value{o.Value}}
}
func (o FloatOptional) Unwrap(ctx *Execution) float64 {
	CheckCancelled(ctx)
	if !o.Present {
		Panic("called Optional.unwrap() on none; check is_some() first, or use unwrap_or(fallback: ...) to supply a default")
	}
	CheckCancelled(ctx)
	return o.Value
}
func ListAtFloat(ctx *Execution, receiver Value, index int64) FloatOptional {
	CheckCancelled(ctx)
	l := receiver.(*List)
	i := relativeIndex(l.Len(), index)
	o := FloatOptional{}
	if i >= 0 && i < int64(l.Len()) {
		o.Present = true
		if l.kind == listFloat {
			o.Value = l.floats[i]
		} else {
			o.Value = l.Get(int(i)).(float64)
		}
	}
	CheckCancelled(ctx)
	return o
}

// NewBoolList copies values into fresh mutable backing; typ is the exact checked key.
func NewBoolList(typ string, values []bool) *List {
	return &List{Type: typ, kind: listBool, bools: append([]bool(nil), values...)}
}

// ListAppendBool is the unboxed primitive append boundary.
func ListAppendBool(ctx *Execution, receiver Value, value bool) Value {
	CheckCancelled(ctx)
	l := receiver.(*List)
	if l.kind == listBool {
		l.bools = append(l.bools, value)
	} else {
		l.Append(value)
	}
	return l
}

type BoolOptional struct {
	Value   bool
	Present bool
}

func (o BoolOptional) Box(result string) Alternative {
	if !o.Present {
		return Alternative{Type: result, Tag: "none"}
	}
	return Alternative{Type: result, Tag: "some", Fields: []Value{o.Value}}
}
func (o BoolOptional) Unwrap(ctx *Execution) bool {
	CheckCancelled(ctx)
	if !o.Present {
		Panic("called Optional.unwrap() on none; check is_some() first, or use unwrap_or(fallback: ...) to supply a default")
	}
	CheckCancelled(ctx)
	return o.Value
}
func ListAtBool(ctx *Execution, receiver Value, index int64) BoolOptional {
	CheckCancelled(ctx)
	l := receiver.(*List)
	i := relativeIndex(l.Len(), index)
	o := BoolOptional{}
	if i >= 0 && i < int64(l.Len()) {
		o.Present = true
		if l.kind == listBool {
			o.Value = l.bools[i]
		} else {
			o.Value = l.Get(int(i)).(bool)
		}
	}
	CheckCancelled(ctx)
	return o
}

// NewStringList copies values into fresh mutable backing; typ is the exact checked key.
func NewStringList(typ string, values []string) *List {
	return &List{Type: typ, kind: listString, strings: append([]string(nil), values...)}
}

// ListAppendString is the unboxed primitive append boundary.
func ListAppendString(ctx *Execution, receiver Value, value string) Value {
	CheckCancelled(ctx)
	l := receiver.(*List)
	if l.kind == listString {
		l.strings = append(l.strings, value)
	} else {
		l.Append(value)
	}
	return l
}

type StringOptional struct {
	Value   string
	Present bool
}

func (o StringOptional) Box(result string) Alternative {
	if !o.Present {
		return Alternative{Type: result, Tag: "none"}
	}
	return Alternative{Type: result, Tag: "some", Fields: []Value{o.Value}}
}
func (o StringOptional) Unwrap(ctx *Execution) string {
	CheckCancelled(ctx)
	if !o.Present {
		Panic("called Optional.unwrap() on none; check is_some() first, or use unwrap_or(fallback: ...) to supply a default")
	}
	CheckCancelled(ctx)
	return o.Value
}
func ListAtString(ctx *Execution, receiver Value, index int64) StringOptional {
	CheckCancelled(ctx)
	l := receiver.(*List)
	i := relativeIndex(l.Len(), index)
	o := StringOptional{}
	if i >= 0 && i < int64(l.Len()) {
		o.Present = true
		if l.kind == listString {
			o.Value = l.strings[i]
		} else {
			o.Value = l.Get(int(i)).(string)
		}
	}
	CheckCancelled(ctx)
	return o
}

func CollectionLengthInt(ctx *Execution, receiver Value) int64 {
	CheckCancelled(ctx)
	switch v := receiver.(type) {
	case *List:
		return int64(v.Len())
	case *Map:
		return int64(len(v.Entries))
	case *Set:
		return int64(len(v.Items))
	}
	Panic("runtime invariant: collection receiver")
	return 0
}

func listInts(l *List) []int64 {
	if l.kind == listInt {
		return l.ints
	}
	values := make([]int64, l.Len())
	for i := range values {
		values[i] = l.Get(i).(int64)
	}
	return values
}

func listFloats(l *List) []float64 {
	if l.kind == listFloat {
		return l.floats
	}
	values := make([]float64, l.Len())
	for i := range values {
		values[i] = l.Get(i).(float64)
	}
	return values
}

func listBools(l *List) []bool {
	if l.kind == listBool {
		return l.bools
	}
	values := make([]bool, l.Len())
	for i := range values {
		values[i] = l.Get(i).(bool)
	}
	return values
}

func listStrings(l *List) []string {
	if l.kind == listString {
		return l.strings
	}
	values := make([]string, l.Len())
	for i := range values {
		values[i] = l.Get(i).(string)
	}
	return values
}

// Int reads a captured header without boxing, including boxed fallback Lists.
func (r ListRange) Int(i int) int64 {
	if r.list.kind == listInt {
		return r.list.ints[i]
	}
	return r.list.Get(i).(int64)
}

// Float reads a captured header without boxing, including boxed fallback Lists.
func (r ListRange) Float(i int) float64 {
	if r.list.kind == listFloat {
		return r.list.floats[i]
	}
	return r.list.Get(i).(float64)
}

// Bool reads a captured header without boxing, including boxed fallback Lists.
func (r ListRange) Bool(i int) bool {
	if r.list.kind == listBool {
		return r.list.bools[i]
	}
	return r.list.Get(i).(bool)
}

// String reads a captured header without boxing, including boxed fallback Lists.
func (r ListRange) String(i int) string {
	if r.list.kind == listString {
		return r.list.strings[i]
	}
	return r.list.Get(i).(string)
}

func copyListItems[T any](ctx *Execution, source []T) []T {
	out := make([]T, len(source))
	for start := 0; start < len(source); start += 1024 {
		CheckCancelled(ctx)
		copy(out[start:min(start+1024, len(source))], source[start:min(start+1024, len(source))])
	}
	return out
}

func (l *List) copySliceChecked(ctx *Execution, start, end int) *List {
	out := &List{Type: l.Type, kind: l.kind}
	switch l.kind {
	case listInt:
		out.ints = copyListItems(ctx, l.ints[start:end])
	case listFloat:
		out.floats = copyListItems(ctx, l.floats[start:end])
	case listBool:
		out.bools = copyListItems(ctx, l.bools[start:end])
	case listString:
		out.strings = copyListItems(ctx, l.strings[start:end])
	default:
		out.Items = copyListItems(ctx, l.Items[start:end])
	}
	return out
}

func (l *List) allocate(n int) {
	switch l.kind {
	case listInt:
		l.ints = make([]int64, n)
	case listFloat:
		l.floats = make([]float64, n)
	case listBool:
		l.bools = make([]bool, n)
	case listString:
		l.strings = make([]string, n)
	default:
		l.Items = make([]Value, n)
	}
}

// NewSizedList starts private literal construction. Lowering evaluates and
// initializes each slot in source order, then finishes before publishing it.
func NewSizedList(typ string, length int) *List {
	list := newList(typ)
	if length < 0 {
		Panic("runtime invariant: negative List initialization length")
	}
	list.allocate(length)
	list.initializing = true
	return list
}
func checkListInitialization(list *List, index int) {
	if !list.initializing || index < 0 || index >= list.Len() {
		Panic("runtime invariant: invalid fresh List initialization")
	}
}
func InitListValue(list *List, index int, value Value) {
	checkListInitialization(list, index)
	if !list.accepts(value) {
		Panic("runtime invariant: List initialization payload type")
	}
	list.Set(index, value)
}
func FinishListInitialization(list *List) *List {
	if !list.initializing {
		Panic("runtime invariant: List initialization already finished")
	}
	list.initializing = false
	return list
}

func NewSizedIntList(typ string, length int) *List {
	if length < 0 {
		Panic("runtime invariant: negative List initialization length")
	}
	return &List{Type: typ, kind: listInt, initializing: true, ints: make([]int64, length)}
}

// InitListInt is strict fresh typed construction. The compact checks inline
// without a generic Len/Set call or a primitive Value box.
func InitListInt(list *List, index int, value int64) {
	if !list.initializing || list.kind != listInt || uint(index) >= uint(len(list.ints)) {
		Panic("runtime invariant: invalid fresh List initialization")
	}
	list.ints[index] = value
}

func NewSizedFloatList(typ string, length int) *List {
	if length < 0 {
		Panic("runtime invariant: negative List initialization length")
	}
	return &List{Type: typ, kind: listFloat, initializing: true, floats: make([]float64, length)}
}

// InitListFloat is strict fresh typed construction. The compact checks inline
// without a generic Len/Set call or a primitive Value box.
func InitListFloat(list *List, index int, value float64) {
	if !list.initializing || list.kind != listFloat || uint(index) >= uint(len(list.floats)) {
		Panic("runtime invariant: invalid fresh List initialization")
	}
	list.floats[index] = value
}

func NewSizedBoolList(typ string, length int) *List {
	if length < 0 {
		Panic("runtime invariant: negative List initialization length")
	}
	return &List{Type: typ, kind: listBool, initializing: true, bools: make([]bool, length)}
}

// InitListBool is strict fresh typed construction. The compact checks inline
// without a generic Len/Set call or a primitive Value box.
func InitListBool(list *List, index int, value bool) {
	if !list.initializing || list.kind != listBool || uint(index) >= uint(len(list.bools)) {
		Panic("runtime invariant: invalid fresh List initialization")
	}
	list.bools[index] = value
}

func NewSizedStringList(typ string, length int) *List {
	if length < 0 {
		Panic("runtime invariant: negative List initialization length")
	}
	return &List{Type: typ, kind: listString, initializing: true, strings: make([]string, length)}
}

// InitListString is strict fresh typed construction. The compact checks inline
// without a generic Len/Set call or a primitive Value box.
func InitListString(list *List, index int, value string) {
	if !list.initializing || list.kind != listString || uint(index) >= uint(len(list.strings)) {
		Panic("runtime invariant: invalid fresh List initialization")
	}
	list.strings[index] = value
}

// EqualAt compares primitive captured cells without crossing a boxed boundary.
// Composite elements retain their selected lexical equality implementation.
func (r ListRange) EqualAt(ctx *Execution, index int, value Value, scope TypeScope) bool {
	if view, ok := value.(View); ok {
		value = view.Receiver
	}
	switch r.list.kind {
	case listInt:
		v, ok := value.(int64)
		return ok && r.list.ints[index] == v
	case listFloat:
		v, ok := value.(float64)
		return ok && r.list.floats[index] == v
	case listBool:
		v, ok := value.(bool)
		return ok && r.list.bools[index] == v
	case listString:
		v, ok := value.(string)
		return ok && r.list.strings[index] == v
	}
	return EqualSelected(ctx, r.Get(index), value, scope)
}

// Primitive equality precedes custom implementation dispatch in equal. When
// both captured headers have matching primitive backing, compare directly
// instead of allocating a Value payload box for every corresponding cell.
func equalPrimitiveListRanges(left, right ListRange) (bool, bool) {
	if left.list.kind != right.list.kind {
		return false, false
	}
	switch left.list.kind {
	case listInt:
		return slices.Equal(left.list.ints, right.list.ints), true
	case listFloat:
		return slices.Equal(left.list.floats, right.list.floats), true
	case listBool:
		return slices.Equal(left.list.bools, right.list.bools), true
	case listString:
		return slices.Equal(left.list.strings, right.list.strings), true
	}
	return false, false
}

package rt

import "strconv"

// nativeMaxItems is the allocation ceiling of collection factories.
const nativeMaxItems = 1 << 28

// relativeIndex resolves a negative index against the end without negating
// MinInt64.
func relativeIndex(length int, index int64) int64 {
	if index < 0 {
		return int64(length) + index
	}
	return index
}

func indexFault(operation string, length int, index int64) {
	if length == 0 {
		Raise(operation + ": index has no valid value for an empty collection, found " + FormatInt(index))
	}
	Raise(operation + ": index must be between " + FormatInt(int64(-length)) + " and " + FormatInt(int64(length-1)) + " (negative indexes count from the end), found " + FormatInt(index))
}

func rangeFault(operation, parameter string, value, minimum, maximum int64) {
	Raise(operation + ": " + parameter + " must be between " + FormatInt(minimum) + " and " + FormatInt(maximum) + ", found " + FormatInt(value))
}

func checkSlice(operation string, length int, start, end int64) {
	if start < 0 || end < start || end > int64(length) {
		Raise(operation + ": start/end must satisfy 0 <= start <= end <= " + strconv.Itoa(length) + "; found start " + FormatInt(start) + " and end " + FormatInt(end))
	}
}

func cloneItems[T any](items []T) []T {
	out := make([]T, len(items))
	copy(out, items)
	return out
}

// List_Clone returns a shallow copy with independent storage.
func List_Clone[T any](_ *Execution, l *List[T]) *List[T] {
	return &List[T]{Items: cloneItems(l.Items)}
}

// List_Length is the element count.
func List_Length[T any](_ *Execution, l *List[T]) int64 { return int64(len(l.Items)) }

// List_IsEmpty reports whether the list has no elements.
func List_IsEmpty[T any](_ *Execution, l *List[T]) bool { return len(l.Items) == 0 }

// List_First returns the first element, or none.
func List_First[T any](_ *Execution, l *List[T]) Option[T] {
	if len(l.Items) == 0 {
		return Option[T]{}
	}
	return Some(l.Items[0])
}

// List_Last returns the last element, or none.
func List_Last[T any](_ *Execution, l *List[T]) Option[T] {
	if len(l.Items) == 0 {
		return Option[T]{}
	}
	return Some(l.Items[len(l.Items)-1])
}

// List_Contains reports whether any element equals value.
func List_Contains[T any](ctx *Execution, eq Eq[T], l *List[T], value T) bool {
	return List_IndexOf(ctx, eq, l, value).Some
}

// List_IndexOf returns the first index equal to value.
func List_IndexOf[T any](ctx *Execution, eq Eq[T], l *List[T], value T) Option[int64] {
	items, tick := l.Items, uint32(0)
	CheckCancelled(ctx)
	for i, item := range items {
		Poll(ctx, &tick)
		if eq(ctx, item, value) {
			return Some(int64(i))
		}
	}
	return Option[int64]{}
}

// List_LastIndexOf returns the last index equal to value.
func List_LastIndexOf[T any](ctx *Execution, eq Eq[T], l *List[T], value T) Option[int64] {
	items, tick := l.Items, uint32(0)
	CheckCancelled(ctx)
	for i := len(items) - 1; i >= 0; i-- {
		Poll(ctx, &tick)
		if eq(ctx, items[i], value) {
			return Some(int64(i))
		}
	}
	return Option[int64]{}
}

// List_Prepend inserts value at the front in place. Like the old runtime it
// appends then shifts, so a running loop's captured array sees the shift.
func List_Prepend[T any](_ *Execution, l *List[T], value T) *List[T] {
	n := len(l.Items)
	l.Items = append(l.Items, value)
	copy(l.Items[1:], l.Items[:n])
	l.Items[0] = value
	return l
}

// List_Insert inserts value before index (negative counts from the end;
// index == length appends).
func List_Insert[T any](_ *Execution, l *List[T], index int64, value T) *List[T] {
	n := len(l.Items)
	i := relativeIndex(n, index)
	if i < 0 || i > int64(n) {
		Raise("List.insert: index must be between " + strconv.Itoa(-n) + " and " + strconv.Itoa(n) + " (negative indexes count from the end), found " + FormatInt(index))
	}
	l.Items = append(l.Items, value)
	copy(l.Items[i+1:], l.Items[i:n])
	l.Items[i] = value
	return l
}

// List_Pop removes and returns the last element. The tail is not cleared: a
// running loop retains its initial header.
func List_Pop[T any](_ *Execution, l *List[T]) Option[T] {
	n := len(l.Items)
	if n == 0 {
		return Option[T]{}
	}
	last := l.Items[n-1]
	l.Items = l.Items[:n-1]
	return Some(last)
}

// List_Set replaces the element at a possibly negative index.
func List_Set[T any](_ *Execution, l *List[T], index int64, value T) *List[T] {
	i := relativeIndex(len(l.Items), index)
	if i < 0 || i >= int64(len(l.Items)) {
		indexFault("List.set", len(l.Items), index)
	}
	l.Items[i] = value
	return l
}

// List_Remove deletes the element at a possibly negative index.
func List_Remove[T any](_ *Execution, l *List[T], index int64) *List[T] {
	n := len(l.Items)
	i := relativeIndex(n, index)
	if i < 0 || i >= int64(n) {
		indexFault("List.remove", n, index)
	}
	copy(l.Items[i:], l.Items[i+1:])
	l.Items = l.Items[:n-1]
	return l
}

// List_Slice copies [start, end); negative bounds count from the end.
func List_Slice[T any](_ *Execution, l *List[T], start, end int64) Result[*List[T], CollectionError] {
	n := len(l.Items)
	s, e := relativeIndex(n, start), relativeIndex(n, end)
	if s < 0 || e < s || e > int64(n) {
		return Fail[*List[T], CollectionError](CollectionError_OutOfRange{})
	}
	return Ok[*List[T], CollectionError](&List[T]{Items: cloneItems(l.Items[s:e])})
}

// List_Take copies the first min(count, length) elements.
func List_Take[T any](ctx *Execution, l *List[T], count int64) *List[T] {
	CheckCancelled(ctx)
	items := l.Items
	count = takeCount("take", count, len(items))
	return &List[T]{Items: cloneItems(items[:count])}
}

// List_Drop copies everything after the first min(count, length) elements.
func List_Drop[T any](ctx *Execution, l *List[T], count int64) *List[T] {
	CheckCancelled(ctx)
	items := l.Items
	count = takeCount("drop", count, len(items))
	return &List[T]{Items: cloneItems(items[count:])}
}

func takeCount(name string, count int64, length int) int64 {
	if count < 0 {
		Raise("List." + name + ": count must be nonnegative, found " + FormatInt(count))
	}
	return min(count, int64(length))
}

// List_ReverseInPlace reverses in place and returns the same list.
func List_ReverseInPlace[T any](_ *Execution, l *List[T]) *List[T] {
	items := l.Items
	for i, j := 0, len(items)-1; i < j; i, j = i+1, j-1 {
		items[i], items[j] = items[j], items[i]
	}
	return l
}

// List_Reversed returns a reversed shallow copy.
func List_Reversed[T any](ctx *Execution, l *List[T]) *List[T] {
	return List_ReverseInPlace(ctx, List_Clone(ctx, l))
}

// List_Filter keeps the elements the predicate accepts.
func List_Filter[T any](ctx *Execution, l *List[T], keep func(*Execution, T) bool) *List[T] {
	items, tick := l.Items, uint32(0)
	out := &List[T]{}
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		if keep(ctx, item) {
			out.Items = append(out.Items, item)
		}
	}
	return out
}

// findIn returns the index of the first (or last) element pred accepts in the
// header captured at entry.
func findIn[T any](ctx *Execution, items []T, pred func(*Execution, T) bool, reverse bool) (int, T, bool) {
	tick := uint32(0)
	CheckCancelled(ctx)
	// The value passed to the predicate is the one returned: the predicate may
	// mutate the list, so the cell is not read again.
	if reverse {
		for i := len(items) - 1; i >= 0; i-- {
			Poll(ctx, &tick)
			v := items[i]
			if pred(ctx, v) {
				return i, v, true
			}
		}
		var zero T
		return 0, zero, false
	}
	for i := range items {
		Poll(ctx, &tick)
		v := items[i]
		if pred(ctx, v) {
			return i, v, true
		}
	}
	var zero T
	return 0, zero, false
}

// List_Find returns the first element the predicate accepts.
func List_Find[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) Option[T] {
	items := l.Items
	if _, v, ok := findIn(ctx, items, pred, false); ok {
		return Some(v)
	}
	return Option[T]{}
}

// List_FindLast returns the last element the predicate accepts.
func List_FindLast[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) Option[T] {
	items := l.Items
	if _, v, ok := findIn(ctx, items, pred, true); ok {
		return Some(v)
	}
	return Option[T]{}
}

// List_FindIndex returns the first index the predicate accepts.
func List_FindIndex[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) Option[int64] {
	if i, _, ok := findIn(ctx, l.Items, pred, false); ok {
		return Some(int64(i))
	}
	return Option[int64]{}
}

// List_FindLastIndex returns the last index the predicate accepts.
func List_FindLastIndex[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) Option[int64] {
	if i, _, ok := findIn(ctx, l.Items, pred, true); ok {
		return Some(int64(i))
	}
	return Option[int64]{}
}

// List_Some reports whether the predicate accepts any element.
func List_Some[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) bool {
	_, _, ok := findIn(ctx, l.Items, pred, false)
	return ok
}

// List_Every reports whether the predicate accepts every element.
func List_Every[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) bool {
	_, _, found := findIn(ctx, l.Items, func(ctx *Execution, v T) bool { return !pred(ctx, v) }, false)
	return !found
}

// List_Count counts the elements the predicate accepts.
func List_Count[T any](ctx *Execution, l *List[T], pred func(*Execution, T) bool) int64 {
	items, tick, count := l.Items, uint32(0), int64(0)
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		if pred(ctx, item) {
			count++
		}
	}
	return count
}

// List_Distinct keeps the first of each run of equal elements.
func List_Distinct[T any](ctx *Execution, eq Eq[T], l *List[T]) *List[T] {
	items, tick := l.Items, uint32(0)
	out := &List[T]{}
	// Int and String equality is exact, so hash them instead of comparing
	// every kept element.
	seenInts, seenStrings := map[int64]struct{}{}, map[string]struct{}{}
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		switch v := any(item).(type) {
		case int64:
			if _, dup := seenInts[v]; !dup {
				seenInts[v] = struct{}{}
				out.Items = append(out.Items, item)
			}
			continue
		case string:
			if _, dup := seenStrings[v]; !dup {
				seenStrings[v] = struct{}{}
				out.Items = append(out.Items, item)
			}
			continue
		}
		seen := false
		for i, kept := range out.Items {
			if i%1024 == 1023 {
				CheckCancelled(ctx)
			}
			if eq(ctx, kept, item) {
				seen = true
				break
			}
		}
		if !seen {
			out.Items = append(out.Items, item)
		}
	}
	return out
}

// List_ForEach calls operation on each element in order.
func List_ForEach[T any](ctx *Execution, l *List[T], operation func(*Execution, T) Unit) Unit {
	items, tick := l.Items, uint32(0)
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		operation(ctx, item)
	}
	return Unit{}
}

// List_GroupBy groups elements by key, preserving first-seen key order.
func List_GroupBy[T any, K comparable](ctx *Execution, keys *Keys[K], l *List[T], key func(*Execution, T) K) *Map[K, *List[T]] {
	items, tick := l.Items, uint32(0)
	out := NewMapWith[K, *List[T]](keys)
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		k := key(ctx, item)
		if group, ok := out.Lookup(k); ok {
			group.Items = append(group.Items, item)
		} else {
			out.Put(k, &List[T]{Items: []T{item}})
		}
	}
	return out
}

// List_Map transforms each element.
func List_Map[T, U any](ctx *Execution, l *List[T], transform func(*Execution, T) U) *List[U] {
	items, tick := l.Items, uint32(0)
	out := make([]U, len(items))
	CheckCancelled(ctx)
	for i, item := range items {
		Poll(ctx, &tick)
		out[i] = transform(ctx, item)
	}
	return &List[U]{Items: out}
}

// List_FlatMap concatenates the lists the transform returns.
func List_FlatMap[T, U any](ctx *Execution, l *List[T], transform func(*Execution, T) *List[U]) *List[U] {
	items, tick := l.Items, uint32(0)
	out := &List[U]{}
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		out.Items = append(out.Items, transform(ctx, item).Items...)
	}
	return out
}

// List_Fold folds left to right.
func List_Fold[T, A any](ctx *Execution, l *List[T], initial A, step func(*Execution, A, T) A) A {
	items, tick := l.Items, uint32(0)
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		initial = step(ctx, initial, item)
	}
	return initial
}

// List_FoldRight folds right to left.
func List_FoldRight[T, A any](ctx *Execution, l *List[T], initial A, step func(*Execution, A, T) A) A {
	items, tick := l.Items, uint32(0)
	CheckCancelled(ctx)
	for i := len(items) - 1; i >= 0; i-- {
		Poll(ctx, &tick)
		initial = step(ctx, initial, items[i])
	}
	return initial
}

// List_Splice replaces count elements at start with the replacement's
// elements, in place.
func List_Splice[T any](_ *Execution, l *List[T], start, count int64, replacement *List[T]) *List[T] {
	n := int64(len(l.Items))
	if start < 0 || start > n {
		rangeFault("List.splice", "start", start, 0, n)
	}
	if count < 0 || count > n-start {
		rangeFault("List.splice", "delete_count", count, 0, n-start)
	}
	items, repl := l.Items, replacement.Items
	if l == replacement {
		repl = cloneItems(repl)
	}
	oldLength := len(items)
	newLength := oldLength - int(count) + len(repl)
	if newLength < oldLength-int(count) {
		Raise("list replacement length overflow")
	}
	if newLength > oldLength {
		items = append(items, make([]T, newLength-oldLength)...)
	}
	s, c := int(start), int(count)
	copy(items[s+len(repl):], items[s+c:oldLength])
	copy(items[s:], repl)
	// Non-clearing reslice preserves valid values in captured traversal tails.
	l.Items = items[:newLength]
	return l
}

// List_Fill sets [start, end) to value.
func List_Fill[T any](ctx *Execution, l *List[T], value T, start, end int64) *List[T] {
	checkSlice("List.fill", len(l.Items), start, end)
	items, tick := l.Items, uint32(0)
	for i := start; i < end; i++ {
		Poll(ctx, &tick)
		items[i] = value
	}
	return l
}

// List_CopyWithin copies [start, end) to target within the list.
func List_CopyWithin[T any](_ *Execution, l *List[T], target, start, end int64) *List[T] {
	n := len(l.Items)
	checkSlice("List.copy_within", n, start, end)
	if target < 0 || target > int64(n) {
		rangeFault("List.copy_within", "target", target, 0, int64(n))
	}
	if start == end || target == int64(n) {
		return l
	}
	copy(l.Items[target:], l.Items[start:end])
	return l
}

// List_ToSet collects the distinct elements. Hashable elements are Go
// comparable (see Map for the key matching rule).
func List_ToSet[T comparable](ctx *Execution, keys *Keys[T], l *List[T]) *Set[T] {
	items, tick := l.Items, uint32(0)
	out := NewSetWith[T](keys)
	CheckCancelled(ctx)
	for _, item := range items {
		Poll(ctx, &tick)
		out.Add(item)
	}
	return out
}

// List_Keys returns 0 through length - 1.
func List_Keys[T any](_ *Execution, l *List[T]) *List[int64] {
	out := make([]int64, len(l.Items))
	for i := range out {
		out[i] = int64(i)
	}
	return &List[int64]{Items: out}
}

// List_Entries pairs each index with its element.
func List_Entries[T any](_ *Execution, l *List[T]) *List[*ListEntry[T]] {
	out := make([]*ListEntry[T], len(l.Items))
	for i, v := range l.Items {
		out[i] = &ListEntry[T]{Index: int64(i), Value: v}
	}
	return &List[*ListEntry[T]]{Items: out}
}

// List_Join concatenates a List[String] with separator between neighbors.
// The declaration binds only List[String]; any other element type is a
// runtime invariant fault.
func List_Join[T any](_ *Execution, l *List[T], separator string) string {
	parts, ok := any(l.Items).([]string)
	if !ok {
		Raise("runtime invariant: List.join requires List[String]")
	}
	n := 0
	if len(parts) > 0 {
		n = len(separator) * (len(parts) - 1)
	}
	for _, p := range parts {
		n += len(p)
	}
	b := make([]byte, 0, n)
	for i, p := range parts {
		if i > 0 {
			b = append(b, separator...)
		}
		b = append(b, p...)
	}
	return string(b)
}

// List_Append adds value at the end in place.
func List_Append[T any](_ *Execution, l *List[T], value T) *List[T] {
	l.Items = append(l.Items, value)
	return l
}

// List_Concat returns a new list of l's elements followed by other's.
func List_Concat[T any](_ *Execution, l, other *List[T]) *List[T] {
	out := make([]T, 0, len(l.Items)+len(other.Items))
	out = append(out, l.Items...)
	return &List[T]{Items: append(out, other.Items...)}
}

// List_Sorted returns a stably sorted shallow copy ordered by the comparator's
// negative/zero/positive results. A fault or cancellation in the comparator
// unwinds with the receiver untouched.
func List_Sorted[T any](ctx *Execution, l *List[T], compare func(*Execution, T, T) int64) *List[T] {
	out := cloneItems(l.Items)
	CheckCancelled(ctx)
	sortStable(out, func(a, b T) bool {
		CheckCancelled(ctx)
		return compare(ctx, a, b) < 0
	})
	return &List[T]{Items: out}
}

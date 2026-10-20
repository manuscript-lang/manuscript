package msruntime

import (
	"math"
)

// Errors_Message_CollectionError is the fixed diagnostic `collection: <reason>`.
func Errors_Message_CollectionError(_ *Execution, e CollectionError) string {
	switch e.(type) {
	case CollectionError_InvalidInput:
		return "collection: invalid input"
	case CollectionError_LimitExceeded:
		return "collection: limit exceeded"
	case CollectionError_OutOfRange:
		return "collection: value out of range"
	}
	return "collection: operation failed"
}

// Collections_Filled creates a list of count copies of value. An omitted
// maxItems leaves only the runtime ceiling.
func Collections_Filled[T any](ctx *Execution, value T, count int, maxItems Option[int]) Result[*List[T], CollectionError] {
	limit := math.MaxInt
	if maxItems.Some {
		limit = maxItems.Val
	}
	if count < 0 || limit < 0 {
		return Fail[*List[T], CollectionError](CollectionError_InvalidInput{})
	}
	if count > min(limit, nativeMaxItems) {
		return Fail[*List[T], CollectionError](CollectionError_LimitExceeded{})
	}
	out, tick := make([]T, count), uint32(0)
	for i := range out {
		Poll(ctx, &tick)
		out[i] = value
	}
	return Ok[*List[T], CollectionError](&List[T]{Items: out})
}

// Collections_Range creates the integers from start up to but excluding end.
func Collections_Range(ctx *Execution, start, end int) *List[int] {
	if end <= start {
		return &List[int]{Items: []int{}}
	}
	if uint64(end)-uint64(start) > nativeMaxItems {
		Raise("range: more than 268435456 items; iterate with 'for index in range(start, end)' directly or bound the list with range_by(max_items:)")
	}
	out, tick := make([]int, int(uint64(end)-uint64(start))), uint32(0)
	for i := range out {
		Poll(ctx, &tick)
		out[i] = start + i
	}
	return &List[int]{Items: out}
}

// Collections_RangeBy creates the integers from start up to but excluding end by step.
func Collections_RangeBy(ctx *Execution, start, end, step int, maxItems Option[int]) Result[*List[int], CollectionError] {
	limit := math.MaxInt
	if maxItems.Some {
		limit = maxItems.Val
	}
	if step == 0 || limit < 0 {
		return Fail[*List[int], CollectionError](CollectionError_InvalidInput{})
	}
	limit = min(limit, nativeMaxItems)
	// Count the terms first so a huge range fails before allocating.
	var span, size uint64
	if step > 0 && start < end {
		span, size = uint64(end)-uint64(start), uint64(step)
	} else if step < 0 && start > end {
		span, size = uint64(start)-uint64(end), -uint64(step)
	}
	if span == 0 {
		return Ok[*List[int], CollectionError](&List[int]{})
	}
	count := (span-1)/size + 1
	if count > uint64(limit) {
		return Fail[*List[int], CollectionError](CollectionError_LimitExceeded{})
	}
	// Avoid a large allocation when a range that would poll is already cancelled.
	if count >= 64 {
		CheckCancelled(ctx)
	}
	out := make([]int, int(count))
	n := start
	for i := range out {
		PollIndex(ctx, i)
		out[i] = n
		// Every remaining term lies within the representable end bound. Do not
		// compute the unused term after the last item, which could overflow.
		if i+1 < len(out) {
			n += step
		}
	}
	return Ok[*List[int], CollectionError](&List[int]{Items: out})
}

// Collections_MapFromEntries builds a map; later entries replace earlier
// values for a repeated key.
func Collections_MapFromEntries[K comparable, V any](ctx *Execution, keys *Keys[K], entries *List[*MapEntry[K, V]]) *Map[K, V] {
	items, tick := entries.Items, uint32(0)
	out := NewMapWith[K, V](keys)
	CheckCancelled(ctx)
	for _, e := range items {
		Poll(ctx, &tick)
		out.Put(e.Key, e.Value)
	}
	return out
}

// builderSealed is the fault of a mutation after freeze.
func builderSealed() { Raise("builder is sealed") }

// ListBuilder appends values before freezing them into a list.
type ListBuilder[T any] struct {
	list   *List[T]
	sealed bool
}

// NewListBuilder returns an empty builder.
func NewListBuilder[T any]() *ListBuilder[T] { return &ListBuilder[T]{list: &List[T]{}} }

// ListBuilder_Append adds value to the end.
func ListBuilder_Append[T any](_ *Execution, b *ListBuilder[T], value T) Unit {
	if b.sealed {
		builderSealed()
	}
	b.list.Items = append(b.list.Items, value)
	return Unit{}
}

// ListBuilder_Freeze seals the builder and returns its list without copying.
func ListBuilder_Freeze[T any](_ *Execution, b *ListBuilder[T]) *List[T] {
	b.sealed = true
	return b.list
}

// MapBuilder adds entries before freezing them into a map.
type MapBuilder[T comparable, U any] struct {
	m      *Map[T, U]
	sealed bool
}

// NewMapBuilder returns an empty builder.
func NewMapBuilder[T comparable, U any](keys *Keys[T]) *MapBuilder[T, U] {
	return &MapBuilder[T, U]{m: NewMapWith[T, U](keys)}
}

// MapBuilder_Add inserts or replaces an entry.
func MapBuilder_Add[T comparable, U any](_ *Execution, b *MapBuilder[T, U], key T, value U) Unit {
	if b.sealed {
		builderSealed()
	}
	b.m.Put(key, value)
	return Unit{}
}

// MapBuilder_Freeze seals the builder and returns its map without copying.
func MapBuilder_Freeze[T comparable, U any](_ *Execution, b *MapBuilder[T, U]) *Map[T, U] {
	b.sealed = true
	return b.m
}

// SetBuilder adds unique values before freezing them into a set.
type SetBuilder[T comparable] struct {
	s      *Set[T]
	sealed bool
}

// NewSetBuilder returns an empty builder.
func NewSetBuilder[T comparable](keys *Keys[T]) *SetBuilder[T] {
	return &SetBuilder[T]{s: NewSetWith[T](keys)}
}

// SetBuilder_Add adds value; an equal value keeps the first payload.
func SetBuilder_Add[T comparable](_ *Execution, b *SetBuilder[T], value T) Unit {
	if b.sealed {
		builderSealed()
	}
	b.s.Add(value)
	return Unit{}
}

// SetBuilder_Freeze seals the builder and returns its set without copying.
func SetBuilder_Freeze[T comparable](_ *Execution, b *SetBuilder[T]) *Set[T] {
	b.sealed = true
	return b.s
}

// Collections_Flatten concatenates the inner lists into a new list.
func Collections_Flatten[T any](ctx *Execution, lists *List[*List[T]]) *List[T] {
	CheckCancelled(ctx)
	total := 0
	for _, inner := range lists.Items {
		total += len(inner.Items)
	}
	out, tick := make([]T, 0, total), uint32(0)
	for _, inner := range lists.Items {
		Poll(ctx, &tick)
		out = append(out, inner.Items...)
	}
	return NewList(out...)
}

package rt

// Set operations. Elements match as Go compares them (see Map).

// Set_Clone returns a shallow copy.
func Set_Clone[T comparable](_ *Execution, s *Set[T]) *Set[T] { return NewSetWith(s.Keys(), s.Snapshot()...) }

// Set_IsEmpty reports whether the set has no elements.
func Set_IsEmpty[T comparable](_ *Execution, s *Set[T]) bool { return s.Len() == 0 }

// Set_Length is the element count.
func Set_Length[T comparable](_ *Execution, s *Set[T]) int64 { return int64(s.Len()) }

// Set_Filter returns a new set of the elements the predicate accepts.
func Set_Filter[T comparable](ctx *Execution, s *Set[T], keep func(*Execution, T) bool) *Set[T] {
	out, tick := NewSetWith[T](s.Keys()), uint32(0)
	CheckCancelled(ctx)
	for _, v := range s.Snapshot() {
		Poll(ctx, &tick)
		if keep(ctx, v) {
			out.Add(v)
		}
	}
	return out
}

// Set_Map transforms each element; equal results collapse to the first.
func Set_Map[T, U comparable](ctx *Execution, keys *Keys[U], s *Set[T], transform func(*Execution, T) U) *Set[U] {
	out, tick := NewSetWith[U](keys), uint32(0)
	CheckCancelled(ctx)
	for _, v := range s.Snapshot() {
		Poll(ctx, &tick)
		out.Add(transform(ctx, v))
	}
	return out
}

// Set_Fold folds the elements in insertion order.
func Set_Fold[T comparable, A any](ctx *Execution, s *Set[T], initial A, step func(*Execution, A, T) A) A {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, v := range s.Snapshot() {
		Poll(ctx, &tick)
		initial = step(ctx, initial, v)
	}
	return initial
}

// Set_FoldRight folds the elements in reverse insertion order.
func Set_FoldRight[T comparable, A any](ctx *Execution, s *Set[T], initial A, step func(*Execution, A, T) A) A {
	items, tick := s.Snapshot(), uint32(0)
	CheckCancelled(ctx)
	for i := len(items) - 1; i >= 0; i-- {
		Poll(ctx, &tick)
		initial = step(ctx, initial, items[i])
	}
	return initial
}

// Set_Find returns the first element the predicate accepts.
func Set_Find[T comparable](ctx *Execution, s *Set[T], pred func(*Execution, T) bool) Option[T] {
	items := s.Snapshot()
	if _, v, ok := findIn(ctx, items, pred, false); ok {
		return Some(v)
	}
	return Option[T]{}
}

// Set_FindLast returns the last element the predicate accepts.
func Set_FindLast[T comparable](ctx *Execution, s *Set[T], pred func(*Execution, T) bool) Option[T] {
	items := s.Snapshot()
	if _, v, ok := findIn(ctx, items, pred, true); ok {
		return Some(v)
	}
	return Option[T]{}
}

// Set_Some reports whether the predicate accepts any element.
func Set_Some[T comparable](ctx *Execution, s *Set[T], pred func(*Execution, T) bool) bool {
	_, _, ok := findIn(ctx, s.Snapshot(), pred, false)
	return ok
}

// Set_Every reports whether the predicate accepts every element.
func Set_Every[T comparable](ctx *Execution, s *Set[T], pred func(*Execution, T) bool) bool {
	_, _, found := findIn(ctx, s.Snapshot(), func(ctx *Execution, v T) bool { return !pred(ctx, v) }, false)
	return !found
}

// Set_Union returns a new set of the elements of either set.
func Set_Union[T comparable](ctx *Execution, left, right *Set[T]) *Set[T] {
	out, tick := NewSetWith(left.Keys(), left.Snapshot()...), uint32(0)
	CheckCancelled(ctx)
	for _, v := range right.Snapshot() {
		Poll(ctx, &tick)
		out.Add(v)
	}
	return out
}

// Set_Intersection returns a new set of the elements in both sets.
func Set_Intersection[T comparable](ctx *Execution, left, right *Set[T]) *Set[T] {
	return setFilter(ctx, left, func(v T) bool { return right.Has(v) })
}

// Set_Difference returns a new set of left's elements absent from right.
func Set_Difference[T comparable](ctx *Execution, left, right *Set[T]) *Set[T] {
	return setFilter(ctx, left, func(v T) bool { return !right.Has(v) })
}

func setFilter[T comparable](ctx *Execution, s *Set[T], keep func(T) bool) *Set[T] {
	out, tick := NewSetWith[T](s.Keys()), uint32(0)
	CheckCancelled(ctx)
	for _, v := range s.Snapshot() {
		Poll(ctx, &tick)
		if keep(v) {
			out.Add(v)
		}
	}
	return out
}

// Set_SymmetricDifference returns the elements in exactly one set: left's
// first, then right's.
func Set_SymmetricDifference[T comparable](ctx *Execution, left, right *Set[T]) *Set[T] {
	out := setFilter(ctx, left, func(v T) bool { return !right.Has(v) })
	tick := uint32(0)
	for _, v := range right.Snapshot() {
		Poll(ctx, &tick)
		if !left.Has(v) {
			out.Add(v)
		}
	}
	return out
}

// Set_IsSubsetOf reports whether every element of left is in right.
func Set_IsSubsetOf[T comparable](ctx *Execution, left, right *Set[T]) bool {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, v := range left.Snapshot() {
		Poll(ctx, &tick)
		if !right.Has(v) {
			return false
		}
	}
	return true
}

// Set_IsSupersetOf reports whether every element of right is in left.
func Set_IsSupersetOf[T comparable](ctx *Execution, left, right *Set[T]) bool {
	return Set_IsSubsetOf(ctx, right, left)
}

// Set_IsDisjointFrom reports whether the sets share no element.
func Set_IsDisjointFrom[T comparable](ctx *Execution, left, right *Set[T]) bool {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, v := range left.Snapshot() {
		Poll(ctx, &tick)
		if right.Has(v) {
			return false
		}
	}
	return true
}

// Set_Clear removes every element.
func Set_Clear[T comparable](_ *Execution, s *Set[T]) *Set[T] {
	s.Clear()
	return s
}

// Set_Values lists the elements in insertion order.
func Set_Values[T comparable](_ *Execution, s *Set[T]) *List[T] { return &List[T]{Items: s.Snapshot()} }

// Set_Entries lists [value, value] pairs in insertion order.
func Set_Entries[T comparable](_ *Execution, s *Set[T]) *List[*List[T]] {
	items := s.Snapshot()
	out := make([]*List[T], len(items))
	for i, v := range items {
		out[i] = &List[T]{Items: []T{v, v}}
	}
	return &List[*List[T]]{Items: out}
}

// Set_ForEach calls operation on each element in insertion order.
func Set_ForEach[T comparable](ctx *Execution, s *Set[T], operation func(*Execution, T) Unit) Unit {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, v := range s.Snapshot() {
		Poll(ctx, &tick)
		operation(ctx, v)
	}
	return Unit{}
}

// Set_Contains reports membership.
func Set_Contains[T comparable](_ *Execution, s *Set[T], item T) bool { return s.Has(item) }

// Set_Add inserts item, in place.
func Set_Add[T comparable](_ *Execution, s *Set[T], item T) *Set[T] {
	s.Add(item)
	return s
}

// Set_Remove deletes item, in place.
func Set_Remove[T comparable](_ *Execution, s *Set[T], item T) *Set[T] {
	s.Remove(item)
	return s
}

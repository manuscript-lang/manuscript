package rt

// Set is Manuscript's insertion-ordered mutable set, with the key matching of
// Map.
type Set[T comparable] struct {
	m Map[T, Unit]
}

// NewSet returns a set holding items, matching elements by Go equality.
func NewSet[T comparable](items ...T) *Set[T] { return NewSetWith(nil, items...) }

// Keys is how the set matches elements.
func (s *Set[T]) Keys() *Keys[T] { return s.m.keys }

// NewSetWith returns a set holding items, matching elements as keys say.
func NewSetWith[T comparable](keys *Keys[T], items ...T) *Set[T] {
	s := &Set[T]{m: *NewMapWith[T, Unit](keys)}
	for _, item := range items {
		s.Add(item)
	}
	return s
}

// Len is the number of elements.
func (s *Set[T]) Len() int { return s.m.Len() }

// Has reports whether item is a member.
func (s *Set[T]) Has(item T) bool { _, ok := s.m.Lookup(item); return ok }

// Add inserts item and reports whether it was new.
func (s *Set[T]) Add(item T) bool {
	if s.Has(item) {
		return false
	}
	s.m.Put(item, Unit{})
	return true
}

// Remove deletes item and reports whether it was present.
func (s *Set[T]) Remove(item T) bool { return s.m.Delete(item) }

// Clear removes every element.
func (s *Set[T]) Clear() { s.m.Clear() }

// Snapshot returns the elements in insertion order.
func (s *Set[T]) Snapshot() []T {
	entries := s.m.Snapshot()
	out := make([]T, len(entries))
	for i, e := range entries {
		out[i] = e.Key
	}
	return out
}

package rt

// ListEqual compares two lists element-wise with eq. Both headers are
// captured first: element equality may mutate either list, and growth or
// reallocation must not change the arrays or membership being compared.
func ListEqual[T any](ctx *Execution, a, b *List[T], eq Eq[T]) bool {
	left, right := a.Items, b.Items
	if len(left) != len(right) {
		return false
	}
	tick := uint32(0)
	for i := range left {
		Poll(ctx, &tick)
		if !eq(ctx, left[i], right[i]) {
			return false
		}
	}
	return true
}

// SetEqual reports whether two sets hold the same elements, in any order.
// Membership is Go equality (see Map).
func SetEqual[T comparable](ctx *Execution, a, b *Set[T]) bool {
	if a.Len() != b.Len() {
		return false
	}
	tick := uint32(0)
	for _, v := range a.Snapshot() {
		Poll(ctx, &tick)
		if !b.Has(v) {
			return false
		}
	}
	return true
}

// MapEqual reports whether two maps hold the same keys (Go equality, see Map)
// with values equal under eq, in any order.
func MapEqual[K comparable, V any](ctx *Execution, a, b *Map[K, V], eq Eq[V]) bool {
	if a.Len() != b.Len() {
		return false
	}
	tick := uint32(0)
	for _, e := range a.Snapshot() {
		Poll(ctx, &tick)
		other, ok := b.Lookup(e.Key)
		if !ok || !eq(ctx, e.Value, other) {
			return false
		}
	}
	return true
}

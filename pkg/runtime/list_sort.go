package msruntime

import "slices"

// sortStable sorts items stably by less. Equal elements keep their order, and
// a panic in less (a comparator fault or cancellation) propagates.
func sortStable[T any](items []T, less func(a, b T) bool) {
	slices.SortStableFunc(items, func(a, b T) int {
		if less(a, b) {
			return -1
		}
		return 0
	})
}

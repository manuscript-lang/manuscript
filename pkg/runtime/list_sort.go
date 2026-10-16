package msruntime

// sortStable sorts items stably by less. Equal elements keep their order, and
// a panic in less (a comparator fault or cancellation) propagates. It is a
// merge sort over a scratch buffer: about n log n comparisons and moves, where
// the in-place stable sort in the standard library does several times more
// work.
func sortStable[T any](items []T, less func(a, b T) bool) {
	if len(items) < 2 {
		return
	}
	buf := make([]T, len(items))
	mergeSort(items, buf, less)
}

const insertionRun = 12

func mergeSort[T any](items, buf []T, less func(a, b T) bool) {
	n := len(items)
	if n <= insertionRun {
		for i := 1; i < n; i++ {
			x := items[i]
			j := i
			for j > 0 && less(x, items[j-1]) {
				items[j] = items[j-1]
				j--
			}
			items[j] = x
		}
		return
	}
	mid := n / 2
	mergeSort(items[:mid], buf[:mid], less)
	mergeSort(items[mid:], buf[mid:], less)
	if !less(items[mid], items[mid-1]) {
		return
	}
	copy(buf[:mid], items[:mid])
	left, right, out := buf[:mid], items[mid:], 0
	li, ri := 0, 0
	for li < len(left) && ri < len(right) {
		if less(right[ri], left[li]) {
			items[out] = right[ri]
			ri++
		} else {
			items[out] = left[li]
			li++
		}
		out++
	}
	copy(items[out:], left[li:])
}

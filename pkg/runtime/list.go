package msruntime

// List is Manuscript's ordered mutable collection. Items is the backing
// slice; a for loop ranges over it directly, which captures the slice and its
// initial length exactly as the language specifies.
type List[T any] struct {
	Items []T
}

// NewList returns a list holding items.
func NewList[T any](items ...T) *List[T] { return &List[T]{Items: items} }

// Positions checks that a list has exactly n elements, for destructuring.
func Positions[T any](l *List[T], n int) []T {
	if len(l.Items) != n {
		Raise("destructuring length mismatch; the pattern binds " + FormatInt(int(n)) + " names but the list has " + FormatInt(len(l.Items)) + " elements")
	}
	return l.Items
}

// List_Get returns the element at a possibly negative index, else the default;
// an invalid index without a default is a fault.
func List_Get[T any](_ *Execution, l *List[T], index int, def Option[T]) T {
	// Keep the common nonnegative read within Go's inline budget. Relative
	// indices and missing values keep the same normalization and diagnostics.
	if uint(index) < uint(len(l.Items)) {
		return l.Items[index]
	}
	return listGetSlow(l, index, def)
}

// ItemsOf samples a list's Items for a loop that cannot replace them: the
// compiler hoists it so indexed reads and writes keep the slice in registers.
func ItemsOf[T any](l *List[T]) []T {
	if l == nil {
		return nil
	}
	return l.Items
}

// List_GetCached is List_Get over items sampled from l by ItemsOf.
func List_GetCached[T any](items []T, l *List[T], index int, def Option[T]) T {
	if uint(index) < uint(len(items)) {
		return items[index]
	}
	return listGetSlow(l, index, def)
}

// List_SetCached is a discarded List_Set over items sampled from l by ItemsOf.
func List_SetCached[T any](items []T, l *List[T], index int, value T) {
	if uint(index) < uint(len(items)) {
		items[index] = value
		return
	}
	List_Set(nil, l, index, value)
}

func listGetSlow[T any](l *List[T], index int, def Option[T]) T {
	n := len(l.Items)
	i := index
	if i < 0 {
		i += n
	}
	if i >= 0 && i < n {
		return l.Items[i]
	}
	return missingIndex(index, n, def)
}

// missingIndex returns the default of a failed index read, or faults without one.
func missingIndex[T any](index, length int, def Option[T]) T {
	if def.Some {
		return def.Val
	}
	Raise("index " + FormatInt(index) + " out of range for length " + FormatInt(length) + "; pass a default: get(index:, default: ...)")
	panic("unreachable")
}

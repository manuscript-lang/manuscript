package rt

// List is Manuscript's ordered mutable collection. Items is the backing
// slice; a for loop ranges over it directly, which captures the slice and its
// initial length exactly as the language specifies.
type List[T any] struct {
	Items []T
}

// Positions checks that a list has exactly n elements, for destructuring.
func Positions[T any](l *List[T], n int) []T {
	if len(l.Items) != n {
		Fault("destructuring length mismatch; the pattern binds " + FormatInt(int64(n)) + " names but the list has " + FormatInt(int64(len(l.Items))) + " elements")
	}
	return l.Items
}

// List_At returns the element at a possibly negative index, or none.
func List_At[T any](_ *Execution, l *List[T], index int64) Option[T] {
	n := int64(len(l.Items))
	if index < 0 {
		index += n
	}
	if index < 0 || index >= n {
		return Option[T]{}
	}
	return Option[T]{Val: l.Items[index], Some: true}
}

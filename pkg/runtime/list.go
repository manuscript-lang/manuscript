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

// List_At returns the element at a possibly negative index, or none.
func List_At[T any](_ *Execution, l *List[T], index int) Option[T] {
	n := len(l.Items)
	if index < 0 {
		index += n
	}
	if index < 0 || index >= n {
		return Option[T]{}
	}
	return Option[T]{Val: l.Items[index], Some: true}
}
